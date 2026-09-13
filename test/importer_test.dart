import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:kuzum_reader/services/importer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const _manifest = '''
{
  "book": "Test Book (Ünïcode)",
  "seconds": 30,
  "chapters": [
    {"index": 1, "title": "001_00_onsoz_part_01", "audio": "001_00_onsoz_part_01.m4a",
     "text": "001_00_onsoz_part_01.txt", "seconds": 10},
    {"index": 2, "title": "002_01_giris_part_01", "audio": "002_01_giris_part_01.m4a",
     "text": "002_01_giris_part_01.txt", "seconds": 20}
  ]
}
''';

/// Builds a zip shaped like a real book package: one top-level folder, plus the
/// junk that archives collected on macOS tend to carry.
File buildZip(Directory dir, {String root = 'Test Book (Ünïcode)'}) {
  final archive = Archive();

  void add(String name, List<int> bytes) =>
      archive.addFile(ArchiveFile(name, bytes.length, bytes));

  add('$root/manifest.json', utf8.encode(_manifest));
  add('$root/001_00_onsoz_part_01.txt', utf8.encode('Önsöz metni.'));
  add('$root/001_00_onsoz_part_01.m4a', List.filled(64, 7));
  add('$root/002_01_giris_part_01.txt', utf8.encode('Giriş metni.'));
  add('$root/002_01_giris_part_01.m4a', List.filled(64, 9));
  // Junk that must not land in the library.
  add('__MACOSX/$root/._manifest.json', utf8.encode('junk'));
  add('$root/.DS_Store', utf8.encode('junk'));

  final zipPath = p.join(dir.path, 'book.zip');
  final encoded = ZipEncoder().encode(archive);
  File(zipPath).writeAsBytesSync(encoded!);
  return File(zipPath);
}

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('kuzum_reader_test'));
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('inspect reads the manifest without unpacking the archive', () async {
    final zip = buildZip(tmp);
    final manifest = await BookImporter.inspect(zip.path);

    expect(manifest.title, 'Test Book (Ünïcode)');
    expect(manifest.chapters.length, 2);
    expect(manifest.totalDuration, const Duration(seconds: 30));
  });

  test('unpack flattens the top folder and skips junk', () async {
    final zip = buildZip(tmp);
    final dest = p.join(tmp.path, 'unpacked');

    final labels = <String>[];
    await for (final progress
        in BookImporter.unpack(zipPath: zip.path, destDir: dest)) {
      labels.add(progress.label);
    }

    // manifest + 2 text + 2 audio, at the destination root.
    expect(File(p.join(dest, 'manifest.json')).existsSync(), isTrue);
    expect(File(p.join(dest, '001_00_onsoz_part_01.txt')).readAsStringSync(),
        'Önsöz metni.');
    expect(File(p.join(dest, '001_00_onsoz_part_01.m4a')).lengthSync(), 64);
    expect(File(p.join(dest, '002_01_giris_part_01.txt')).existsSync(), isTrue);

    // The archive's own folder must not be recreated inside the destination.
    expect(Directory(p.join(dest, 'Test Book (Ünïcode)')).existsSync(), isFalse);
    expect(Directory(p.join(dest, '__MACOSX')).existsSync(), isFalse);
    expect(File(p.join(dest, '.DS_Store')).existsSync(), isFalse);

    final names = Directory(dest)
        .listSync()
        .map((e) => p.basename(e.path))
        .toList()
      ..sort();
    expect(names.length, 5);
    expect(labels, isNotEmpty);
  });

  test('unpack reports progress that reaches the file count', () async {
    final zip = buildZip(tmp);
    final dest = p.join(tmp.path, 'unpacked2');

    ImportProgress? last;
    await for (final progress
        in BookImporter.unpack(zipPath: zip.path, destDir: dest)) {
      if (progress.total > 0) last = progress;
    }
    expect(last, isNotNull);
    expect(last!.done, last.total);
    expect(last.fraction, 1.0);
  });

  test('unpack replaces a previous copy rather than merging into it', () async {
    final zip = buildZip(tmp);
    final dest = p.join(tmp.path, 'unpacked3');
    Directory(dest).createSync(recursive: true);
    File(p.join(dest, 'stale.txt')).writeAsStringSync('left over');

    await BookImporter.unpack(zipPath: zip.path, destDir: dest).drain<void>();

    expect(File(p.join(dest, 'stale.txt')).existsSync(), isFalse);
    expect(File(p.join(dest, 'manifest.json')).existsSync(), isTrue);
  });

  test('a zip without a manifest is rejected and leaves nothing behind',
      () async {
    final archive = Archive()
      ..addFile(ArchiveFile('random.txt', 4, utf8.encode('test')));
    final zipPath = p.join(tmp.path, 'bad.zip');
    File(zipPath).writeAsBytesSync(ZipEncoder().encode(archive)!);
    final dest = p.join(tmp.path, 'nope');

    await expectLater(
      BookImporter.unpack(zipPath: zipPath, destDir: dest).drain<void>(),
      throwsA(isA<ImportException>()),
    );
    expect(Directory(dest).existsSync(), isFalse);
  });

  test('inspect surfaces a clear error for a non-book zip', () async {
    final archive = Archive()
      ..addFile(ArchiveFile('random.txt', 4, utf8.encode('test')));
    final zipPath = p.join(tmp.path, 'bad2.zip');
    File(zipPath).writeAsBytesSync(ZipEncoder().encode(archive)!);

    await expectLater(
      BookImporter.inspect(zipPath),
      throwsA(predicate((e) => '$e'.contains('manifest.json'))),
    );
  });
}
