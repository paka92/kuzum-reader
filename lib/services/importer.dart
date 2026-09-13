import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import '../models/book.dart';

/// Progress of an in-flight import.
class ImportProgress {
  final String label;
  final int done;
  final int total;

  const ImportProgress(this.label, {this.done = 0, this.total = 0});

  double? get fraction => total <= 0 ? null : (done / total).clamp(0.0, 1.0);
}

class ImportException implements Exception {
  final String message;
  ImportException(this.message);
  @override
  String toString() => message;
}

/// Result of peeking into a zip without unpacking it.
class _ZipPeek {
  final String manifestJson;

  /// Directory prefix inside the zip that contains `manifest.json`
  /// (`'Book Name/'`, or `''` when the manifest sits at the root).
  final String prefix;

  const _ZipPeek(this.manifestJson, this.prefix);
}

/// Unpacks book zips into app-private storage exactly once.
///
/// The zip is never read again after import: the library points at the
/// unpacked directory and every later read goes straight to those files.
class BookImporter {
  /// Builds a filesystem-safe, stable folder name from the book title so that
  /// re-importing the same book maps onto the same directory instead of
  /// creating a duplicate.
  static String idForTitle(String title) {
    final normalized = title.trim().toLowerCase();
    final slug = normalized
        .replaceAll(RegExp(r'[^a-z0-9À-ɏ]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    final base = slug.isEmpty ? 'book' : slug;
    // Short digest keeps distinct titles apart even if their slugs collide.
    var hash = 0x811c9dc5;
    for (final unit in normalized.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xFFFFFFFF;
    }
    final suffix = hash.toRadixString(16).padLeft(8, '0');
    final trimmed = base.length > 48 ? base.substring(0, 48) : base;
    return '$trimmed-$suffix';
  }

  /// Reads just `manifest.json` out of the zip. Cheap: the zip's central
  /// directory is read, chapter audio is not.
  static Future<BookManifest> inspect(String zipPath) async {
    final peek = await _peekInIsolate(zipPath);
    return BookManifest.parse(peek.manifestJson);
  }

  /// Kept separate so the closure handed to [Isolate.run] captures nothing but
  /// [zipPath].
  static Future<_ZipPeek> _peekInIsolate(String zipPath) =>
      Isolate.run(() => _peekZip(zipPath));

  /// Unpacks [zipPath] into [destDir] (created fresh) and returns the manifest.
  ///
  /// Extraction runs on a background isolate so the UI stays responsive while
  /// a few hundred megabytes are written.
  static Stream<ImportProgress> unpack({
    required String zipPath,
    required String destDir,
  }) {
    final controller = StreamController<ImportProgress>();

    Future<void> run() async {
      final receive = ReceivePort();
      Isolate? isolate;
      try {
        controller.add(const ImportProgress('Reading package…'));
        final peek = await BookImporter._peekInIsolate(zipPath);
        // Validate before writing anything to disk.
        BookManifest.parse(peek.manifestJson);

        final dir = Directory(destDir);
        if (await dir.exists()) await dir.delete(recursive: true);
        await dir.create(recursive: true);

        isolate = await Isolate.spawn(
          _extractIsolate,
          _ExtractRequest(
            zipPath: zipPath,
            destDir: destDir,
            prefix: peek.prefix,
            port: receive.sendPort,
          ),
        );

        await for (final message in receive) {
          if (message is! Map) continue;
          if (message['error'] != null) {
            throw ImportException(message['error'] as String);
          }
          if (message['done'] == true) break;
          controller.add(ImportProgress(
            'Unpacking files…',
            done: (message['count'] as num?)?.toInt() ?? 0,
            total: (message['total'] as num?)?.toInt() ?? 0,
          ));
        }
      } catch (e) {
        // Never leave a half-unpacked book behind.
        try {
          final dir = Directory(destDir);
          if (await dir.exists()) await dir.delete(recursive: true);
        } catch (_) {/* best effort */}
        controller.addError(e is ImportException ? e : ImportException('$e'));
      } finally {
        receive.close();
        isolate?.kill(priority: Isolate.immediate);
        await controller.close();
      }
    }

    controller.onListen = run;
    return controller.stream;
  }
}

/// Reads the manifest entry out of a zip without unpacking the archive.
_ZipPeek _peekZip(String zipPath) {
  final input = InputFileStream(zipPath);
  try {
    final archive = ZipDecoder().decodeBuffer(input);
    ArchiveFile? manifest;
    for (final file in archive.files) {
      if (!file.isFile) continue;
      if (p.basename(file.name).toLowerCase() != 'manifest.json') continue;
      // Prefer the shallowest manifest.json in the archive.
      if (manifest == null ||
          p.split(file.name).length < p.split(manifest.name).length) {
        manifest = file;
      }
    }
    if (manifest == null) {
      throw ImportException(
          'This zip has no manifest.json, so it is not a book package.');
    }
    final content = manifest.content;
    final bytes = content is List<int> ? content : const <int>[];
    final json = utf8.decode(bytes, allowMalformed: true);
    final dir = p.dirname(manifest.name);
    final prefix = (dir == '.' || dir.isEmpty) ? '' : '$dir/';
    return _ZipPeek(json, prefix);
  } finally {
    input.closeSync();
  }
}

class _ExtractRequest {
  final String zipPath;
  final String destDir;
  final String prefix;
  final SendPort port;

  const _ExtractRequest({
    required this.zipPath,
    required this.destDir,
    required this.prefix,
    required this.port,
  });
}

/// Streams every entry under the manifest's directory onto disk, flattening the
/// archive's top-level folder away.
void _extractIsolate(_ExtractRequest request) {
  final port = request.port;
  InputFileStream? input;
  try {
    input = InputFileStream(request.zipPath);
    final archive = ZipDecoder().decodeBuffer(input);

    final wanted = <ArchiveFile>[];
    for (final file in archive.files) {
      if (!file.isFile) continue;
      final relative = _relativeName(file.name, request.prefix);
      if (relative == null) continue;
      wanted.add(file);
    }

    final destRoot = p.normalize(request.destDir);
    var count = 0;
    for (final file in wanted) {
      final relative = _relativeName(file.name, request.prefix)!;
      final outPath = p.normalize(p.join(destRoot, relative));
      // Guard against path traversal entries in a malformed zip.
      if (!p.isWithin(destRoot, outPath)) continue;

      Directory(p.dirname(outPath)).createSync(recursive: true);
      final out = OutputFileStream(outPath);
      try {
        file.writeContent(out);
      } finally {
        out.closeSync();
      }
      count++;
      if (count % 4 == 0 || count == wanted.length) {
        port.send({'count': count, 'total': wanted.length});
      }
    }
    port.send({'done': true});
  } catch (e) {
    port.send({'error': '$e'});
  } finally {
    input?.closeSync();
  }
}

/// Path of [name] relative to [prefix], or null if it should be skipped.
String? _relativeName(String name, String prefix) {
  var cleaned = name.replaceAll('\\', '/');
  if (prefix.isNotEmpty) {
    if (!cleaned.startsWith(prefix)) return null;
    cleaned = cleaned.substring(prefix.length);
  }
  if (cleaned.isEmpty) return null;
  final segments = p.posix.split(cleaned);
  // Skip archive cruft and any hidden files.
  if (segments.any((s) => s == '__MACOSX' || s.startsWith('.') || s == '..')) {
    return null;
  }
  return p.joinAll(segments);
}
