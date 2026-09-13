import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// One audio part and its matching text file, as listed in `manifest.json`.
class Chapter {
  final int index;
  final String rawTitle;
  final String audioFile;
  final String? textFile;
  final Duration duration;

  const Chapter({
    required this.index,
    required this.rawTitle,
    required this.audioFile,
    required this.textFile,
    required this.duration,
  });

  factory Chapter.fromManifest(Map<String, dynamic> json) {
    final seconds = (json['seconds'] as num?)?.toDouble() ?? 0;
    final text = json['text'];
    return Chapter(
      index: (json['index'] as num?)?.toInt() ?? 0,
      rawTitle: (json['title'] as String?)?.trim() ?? '',
      audioFile: (json['audio'] as String?)?.trim() ?? '',
      textFile: (text is String && text.trim().isNotEmpty) ? text.trim() : null,
      duration: Duration(milliseconds: (seconds * 1000).round()),
    );
  }

  bool get hasText => textFile != null;
}

/// Where the listener left off in a book.
class BookProgress {
  int chapterIndex;
  Duration position;
  DateTime? updatedAt;

  BookProgress({
    this.chapterIndex = 0,
    this.position = Duration.zero,
    this.updatedAt,
  });

  factory BookProgress.fromJson(Map<String, dynamic> json) => BookProgress(
        chapterIndex: (json['chapterIndex'] as num?)?.toInt() ?? 0,
        position: Duration(
            milliseconds: (json['positionMs'] as num?)?.toInt() ?? 0),
        updatedAt: json['updatedAt'] == null
            ? null
            : DateTime.tryParse(json['updatedAt'] as String),
      );

  Map<String, dynamic> toJson() => {
        'chapterIndex': chapterIndex,
        'positionMs': position.inMilliseconds,
        'updatedAt': updatedAt?.toIso8601String(),
      };

  bool get isStarted => chapterIndex > 0 || position > Duration.zero;
}

/// A book that has already been unpacked into the app's own storage. The zip is
/// read exactly once, at import time; everything afterwards reads these files.
class Book {
  final String id;
  final String title;

  /// Absolute directory holding `manifest.json` and the media files.
  final String dirPath;
  final List<Chapter> chapters;
  final Duration totalDuration;
  final DateTime importedAt;
  final BookProgress progress;

  Book({
    required this.id,
    required this.title,
    required this.dirPath,
    required this.chapters,
    required this.totalDuration,
    required this.importedAt,
    required this.progress,
  });

  String get manifestPath => p.join(dirPath, 'manifest.json');

  String audioPathFor(Chapter chapter) => p.join(dirPath, chapter.audioFile);

  String? textPathFor(Chapter chapter) =>
      chapter.textFile == null ? null : p.join(dirPath, chapter.textFile!);

  /// Elapsed time across the whole book at the saved position, used for the
  /// library progress bar.
  Duration get elapsed {
    var total = Duration.zero;
    final limit = progress.chapterIndex.clamp(0, chapters.length);
    for (var i = 0; i < limit; i++) {
      total += chapters[i].duration;
    }
    return total + progress.position;
  }

  double get fraction {
    final totalMs = totalDuration.inMilliseconds;
    if (totalMs <= 0) return 0;
    return (elapsed.inMilliseconds / totalMs).clamp(0.0, 1.0);
  }

  /// Index stored in progress, guaranteed to be addressable.
  int get safeChapterIndex =>
      chapters.isEmpty ? 0 : progress.chapterIndex.clamp(0, chapters.length - 1);

  /// Library-index form. Chapters are intentionally not duplicated here — the
  /// unpacked `manifest.json` stays the single source of truth for them.
  Map<String, dynamic> toIndexJson() => {
        'id': id,
        'title': title,
        'dir': dirPath,
        'importedAt': importedAt.toIso8601String(),
        'progress': progress.toJson(),
      };
}

/// Thrown when a zip does not look like a book package.
class ManifestException implements Exception {
  final String message;
  ManifestException(this.message);
  @override
  String toString() => message;
}

/// Parsed `manifest.json` contents.
class BookManifest {
  final String title;
  final List<Chapter> chapters;
  final Duration totalDuration;

  const BookManifest({
    required this.title,
    required this.chapters,
    required this.totalDuration,
  });

  factory BookManifest.parse(String jsonSource) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(jsonSource);
    } on FormatException catch (e) {
      throw ManifestException('manifest.json is not valid JSON: ${e.message}');
    }
    if (decoded is! Map<String, dynamic>) {
      throw ManifestException('manifest.json must contain a JSON object.');
    }
    final rawChapters = decoded['chapters'];
    if (rawChapters is! List || rawChapters.isEmpty) {
      throw ManifestException('manifest.json lists no chapters.');
    }

    final chapters = <Chapter>[];
    for (final entry in rawChapters) {
      if (entry is! Map<String, dynamic>) continue;
      final chapter = Chapter.fromManifest(entry);
      if (chapter.audioFile.isEmpty) continue;
      chapters.add(chapter);
    }
    if (chapters.isEmpty) {
      throw ManifestException('No chapters in manifest.json have audio files.');
    }

    final declared = (decoded['seconds'] as num?)?.toDouble();
    final total = declared != null && declared > 0
        ? Duration(milliseconds: (declared * 1000).round())
        : chapters.fold(Duration.zero, (sum, c) => sum + c.duration);

    var title = (decoded['book'] as String?)?.trim() ?? '';
    if (title.isEmpty) title = 'Untitled book';

    return BookManifest(
      title: title,
      chapters: List.unmodifiable(chapters),
      totalDuration: total,
    );
  }

  static Future<BookManifest> fromFile(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw ManifestException('manifest.json is missing at $path');
    }
    return BookManifest.parse(await file.readAsString());
  }
}
