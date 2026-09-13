import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/book.dart';
import 'importer.dart';
import 'library_store.dart';

/// Outcome of an import.
class ImportResult {
  final Book book;

  /// True when the book was already unpacked and nothing was extracted again.
  final bool alreadyPresent;

  const ImportResult(this.book, {required this.alreadyPresent});
}

/// Owns the in-memory library and keeps it in sync with disk.
class LibraryController extends ChangeNotifier {
  LibraryController(this._store);

  final LibraryStore _store;

  List<Book> _books = [];
  bool _loading = true;
  ImportProgress? _importProgress;
  Timer? _progressFlushTimer;
  bool _progressDirty = false;
  double _fontScale = 1.0;
  double _speed = 1.0;

  List<Book> get books => List.unmodifiable(_books);

  /// Reader text size multiplier.
  double get fontScale => _fontScale;

  /// Last chosen playback speed, reapplied to new books.
  double get speed => _speed;
  bool get loading => _loading;
  ImportProgress? get importProgress => _importProgress;
  bool get isImporting => _importProgress != null;

  /// Most recently listened-to book, for the "Continue" shortcut.
  Book? get lastOpened {
    Book? best;
    for (final book in _books) {
      final at = book.progress.updatedAt;
      if (at == null) continue;
      if (best == null || at.isAfter(best.progress.updatedAt!)) best = book;
    }
    return best;
  }

  Future<void> init() async {
    final settings = await _store.loadSettings();
    _fontScale = (settings['fontScale'] as num?)?.toDouble() ?? 1.0;
    _speed = (settings['speed'] as num?)?.toDouble() ?? 1.0;
    _books = await _store.load();
    _sort();
    _loading = false;
    notifyListeners();
  }

  void setFontScale(double value) {
    if ((_fontScale - value).abs() < 0.001) return;
    _fontScale = value;
    notifyListeners();
    _saveSettings();
  }

  void setSpeed(double value) {
    if ((_speed - value).abs() < 0.001) return;
    _speed = value;
    notifyListeners();
    _saveSettings();
  }

  Future<void> _saveSettings() =>
      _store.saveSettings({'fontScale': _fontScale, 'speed': _speed});

  void _sort() {
    _books.sort((a, b) {
      final aAt = a.progress.updatedAt;
      final bAt = b.progress.updatedAt;
      if (aAt != null && bAt != null) return bAt.compareTo(aAt);
      if (aAt != null) return -1;
      if (bAt != null) return 1;
      return b.importedAt.compareTo(a.importedAt);
    });
  }

  Book? byId(String id) {
    for (final book in _books) {
      if (book.id == id) return book;
    }
    return null;
  }

  /// Imports a zip: unpacks it once into app storage and adds it to the library.
  ///
  /// Returns the imported book. If the same book is already present, its
  /// existing unpacked copy is returned untouched unless [replace] is set, so a
  /// second import never re-extracts hundreds of megabytes by accident.
  Future<ImportResult> importZip(String zipPath, {bool replace = false}) async {
    if (isImporting) {
      throw ImportException('Another import is already running.');
    }
    _importProgress = const ImportProgress('Reading package…');
    notifyListeners();

    try {
      final manifest = await BookImporter.inspect(zipPath);
      final id = BookImporter.idForTitle(manifest.title);
      final existing = byId(id);
      if (existing != null && !replace) {
        return ImportResult(existing, alreadyPresent: true);
      }

      final destDir = await _store.pathForBookId(id);
      await for (final progress in BookImporter.unpack(
        zipPath: zipPath,
        destDir: destDir,
      )) {
        _importProgress = progress;
        notifyListeners();
      }

      // Re-read the manifest from the unpacked copy — that file is now the
      // source of truth for this book.
      final unpacked = await BookManifest.fromFile('$destDir/manifest.json');
      final book = Book(
        id: id,
        title: unpacked.title,
        dirPath: destDir,
        chapters: unpacked.chapters,
        totalDuration: unpacked.totalDuration,
        importedAt: DateTime.now(),
        // Keep the old resume point when re-importing the same book.
        progress: existing?.progress ?? BookProgress(),
      );

      _books.removeWhere((b) => b.id == id);
      _books.add(book);
      _sort();
      await _store.save(_books);
      return ImportResult(book, alreadyPresent: false);
    } finally {
      _importProgress = null;
      notifyListeners();
    }
  }

  Future<void> remove(Book book) async {
    _books.removeWhere((b) => b.id == book.id);
    notifyListeners();
    await _store.deleteBookFiles(book.dirPath);
    await _store.save(_books);
  }

  Future<int> sizeOnDisk(Book book) => _store.sizeOnDisk(book.dirPath);

  /// Records the resume point. Called very often while audio plays, so disk
  /// writes are coalesced onto a timer.
  void updateProgress(String bookId, int chapterIndex, Duration position) {
    final book = byId(bookId);
    if (book == null) return;
    final progress = book.progress;
    if (progress.chapterIndex == chapterIndex &&
        (progress.position - position).abs() < const Duration(seconds: 1)) {
      return;
    }
    progress.chapterIndex = chapterIndex;
    progress.position = position;
    progress.updatedAt = DateTime.now();
    _progressDirty = true;
    notifyListeners();

    _progressFlushTimer ??= Timer(const Duration(seconds: 5), () {
      _progressFlushTimer = null;
      flushProgress();
    });
  }

  /// Writes any pending resume point immediately (on pause, backgrounding…).
  Future<void> flushProgress() async {
    if (!_progressDirty) return;
    _progressDirty = false;
    _progressFlushTimer?.cancel();
    _progressFlushTimer = null;
    try {
      await _store.save(_books);
    } catch (_) {
      _progressDirty = true;
    }
  }

  @override
  void dispose() {
    _progressFlushTimer?.cancel();
    super.dispose();
  }
}
