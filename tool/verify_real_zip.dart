// Command-line check of the importer against a real book package: unpacks it
// and verifies every file the manifest promises actually landed on disk.
// Usage: dart run tool/verify_real_zip.dart <zip> <destDir>
//
// ignore_for_file: avoid_print -- stdout is this tool's output.
import 'dart:io';

import 'package:kuzum_reader/models/book.dart';
import 'package:kuzum_reader/models/naming.dart';
import 'package:kuzum_reader/services/importer.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    print('usage: dart run tool/verify_real_zip.dart <zip> <destDir>');
    exitCode = 64;
    return;
  }
  final zipPath = args[0];
  final destDir = args[1];

  final started = DateTime.now();
  final manifest = await BookImporter.inspect(zipPath);
  print('inspect: "${manifest.title}"');
  print('  chapters   : ${manifest.chapters.length}');
  print('  total       : ${manifest.totalDuration}');
  print('  id          : ${BookImporter.idForTitle(manifest.title)}');
  print('  inspect took: ${DateTime.now().difference(started).inMilliseconds}ms');

  final unpackStart = DateTime.now();
  var lastDone = 0;
  await for (final progress
      in BookImporter.unpack(zipPath: zipPath, destDir: destDir)) {
    lastDone = progress.done;
  }
  print('unpack: $lastDone files in '
      '${DateTime.now().difference(unpackStart).inSeconds}s');

  // Everything the manifest promises must actually be on disk.
  final unpacked = await BookManifest.fromFile(p.join(destDir, 'manifest.json'));
  var missingAudio = 0, missingText = 0, audioBytes = 0;
  for (final c in unpacked.chapters) {
    final a = File(p.join(destDir, c.audioFile));
    if (a.existsSync()) {
      audioBytes += a.lengthSync();
    } else {
      missingAudio++;
      print('  MISSING AUDIO: ${c.audioFile}');
    }
    if (c.textFile != null && !File(p.join(destDir, c.textFile!)).existsSync()) {
      missingText++;
      print('  MISSING TEXT: ${c.textFile}');
    }
  }
  print('verify: ${unpacked.chapters.length} chapters, '
      'missingAudio=$missingAudio missingText=$missingText');
  print('  audio on disk: ${(audioBytes / 1024 / 1024).toStringAsFixed(1)} MB');
  print('  nested folder recreated: '
      '${Directory(p.join(destDir, unpacked.title)).existsSync()}');

  // Section grouping on real data.
  final sections = buildSections(unpacked.chapters);
  final covered = sections.expand((s) => s.chapterIndices).toSet();
  print('sections: ${sections.length}, covering ${covered.length} chapters');
  for (final s in sections.take(4)) {
    print('  ${s.title}: ${s.chapterIndices.length} parts, ${s.duration}');
  }
  print('  last -> ${sections.last.title}: '
      '${sections.last.chapterIndices.length} parts');

  // Text must be readable as UTF-8 with Turkish characters intact.
  final firstText = File(p.join(destDir, unpacked.chapters.first.textFile!));
  final sample = (await firstText.readAsString()).trim();
  print('text sample: ${sample.substring(0, 60).replaceAll('\n', ' / ')}');
  print('  reads as UTF-8: ${sample.contains('ö') || sample.contains('İ') || sample.contains('ı')}');

  print('TOTAL ${DateTime.now().difference(started).inSeconds}s');
}
