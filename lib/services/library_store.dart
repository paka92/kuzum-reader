import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../models/book.dart';

/// On-disk home of the library: an index file plus one directory per unpacked
/// book.
class LibraryStore {
  static const _indexFileName = 'library.json';
  static const _settingsFileName = 'settings.json';
  static const _booksDirName = 'books';

  Directory? _root;

  Future<Directory> root() async {
    final cached = _root;
    if (cached != null) return cached;
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'kuzum_reader'));
    if (!await dir.exists()) await dir.create(recursive: true);
    _root = dir;
    return dir;
  }

  Future<Directory> booksDir() async {
    final dir = Directory(p.join((await root()).path, _booksDirName));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<String> pathForBookId(String id) async =>
      p.join((await booksDir()).path, id);

  Future<File> _indexFile() async =>
      File(p.join((await root()).path, _indexFileName));

  /// Loads the library. Each entry's chapter list comes from its own unpacked
  /// `manifest.json`, so the zip is never touched again.
  Future<List<Book>> load() async {
    final file = await _indexFile();
    if (!await file.exists()) return [];

    final List<dynamic> entries;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, dynamic> && decoded['books'] is List) {
        entries = decoded['books'] as List<dynamic>;
      } else {
        return [];
      }
    } catch (_) {
      return [];
    }

    final books = <Book>[];
    for (final entry in entries) {
      if (entry is! Map<String, dynamic>) continue;
      final id = entry['id'] as String?;
      final dirPath = entry['dir'] as String?;
      if (id == null || dirPath == null) continue;
      // Skip books whose files are gone (app data cleared, storage detached).
      if (!await Directory(dirPath).exists()) continue;
      try {
        final manifest = await BookManifest.fromFile(p.join(dirPath, 'manifest.json'));
        final progress = entry['progress'] is Map<String, dynamic>
            ? BookProgress.fromJson(entry['progress'] as Map<String, dynamic>)
            : BookProgress();
        if (progress.chapterIndex >= manifest.chapters.length) {
          progress.chapterIndex = manifest.chapters.length - 1;
        }
        if (progress.chapterIndex < 0) progress.chapterIndex = 0;
        books.add(Book(
          id: id,
          title: (entry['title'] as String?)?.trim().isNotEmpty == true
              ? (entry['title'] as String).trim()
              : manifest.title,
          dirPath: dirPath,
          chapters: manifest.chapters,
          totalDuration: manifest.totalDuration,
          importedAt: DateTime.tryParse(entry['importedAt'] as String? ?? '') ??
              DateTime.now(),
          progress: progress,
        ));
      } catch (_) {
        // A corrupt manifest shouldn't take the whole library down.
        continue;
      }
    }
    return books;
  }

  /// Writes the index atomically so a crash mid-write cannot corrupt it.
  Future<void> save(List<Book> books) async {
    final file = await _indexFile();
    final payload = jsonEncode({
      'version': 1,
      'books': [for (final b in books) b.toIndexJson()],
    });
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(payload, flush: true);
    await tmp.rename(file.path);
  }

  Future<File> _settingsFile() async =>
      File(p.join((await root()).path, _settingsFileName));

  Future<Map<String, dynamic>> loadSettings() async {
    try {
      final file = await _settingsFile();
      if (!await file.exists()) return {};
      final decoded = jsonDecode(await file.readAsString());
      return decoded is Map<String, dynamic> ? decoded : {};
    } catch (_) {
      return {};
    }
  }

  Future<void> saveSettings(Map<String, dynamic> settings) async {
    try {
      final file = await _settingsFile();
      await file.writeAsString(jsonEncode(settings), flush: true);
    } catch (_) {/* settings are a convenience, not worth failing over */}
  }

  Future<void> deleteBookFiles(String dirPath) async {
    final dir = Directory(dirPath);
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  /// Sums the bytes held by an unpacked book, for display.
  Future<int> sizeOnDisk(String dirPath) async {
    var total = 0;
    final dir = Directory(dirPath);
    if (!await dir.exists()) return 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        try {
          total += await entity.length();
        } catch (_) {/* ignore unreadable */}
      }
    }
    return total;
  }
}
