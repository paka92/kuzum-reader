import 'package:kuzum_reader/models/book.dart';
import 'package:kuzum_reader/services/importer.dart';
import 'package:flutter_test/flutter_test.dart';

const _sample = '''
{
  "book": "Batı Felsefesi Tarihi 01 (İlk Çağ Felsefesi)",
  "created": "2026-09-12T11:31:01.580854+00:00",
  "audio": {"container": "m4a", "codec": "aac"},
  "seconds": 39495.044,
  "chapters": [
    {"index": 1, "title": "001_00_onsoz_part_01", "audio": "001_00_onsoz_part_01.m4a",
     "text": "001_00_onsoz_part_01.txt", "seconds": 230.03, "bytes": 1428855},
    {"index": 2, "title": "002_01_giris_part_01", "audio": "002_01_giris_part_01.m4a",
     "text": "002_01_giris_part_01.txt", "seconds": 260.4, "bytes": 1610233}
  ]
}
''';

void main() {
  group('BookManifest.parse', () {
    test('reads title, chapters and total duration', () {
      final manifest = BookManifest.parse(_sample);
      expect(manifest.title, 'Batı Felsefesi Tarihi 01 (İlk Çağ Felsefesi)');
      expect(manifest.chapters.length, 2);
      expect(manifest.totalDuration.inSeconds, 39495);

      final first = manifest.chapters.first;
      expect(first.rawTitle, '001_00_onsoz_part_01');
      expect(first.audioFile, '001_00_onsoz_part_01.m4a');
      expect(first.textFile, '001_00_onsoz_part_01.txt');
      expect(first.duration, const Duration(milliseconds: 230030));
      expect(first.hasText, isTrue);
    });

    test('falls back to summing chapters when seconds is absent', () {
      final manifest = BookManifest.parse('''
      {"book": "X", "chapters": [
        {"index": 1, "title": "a", "audio": "a.m4a", "seconds": 10},
        {"index": 2, "title": "b", "audio": "b.m4a", "seconds": 5}
      ]}''');
      expect(manifest.totalDuration, const Duration(seconds: 15));
    });

    test('treats a chapter with no text file as audio-only', () {
      final manifest = BookManifest.parse(
          '{"book":"X","chapters":[{"index":1,"title":"a","audio":"a.m4a","seconds":1}]}');
      expect(manifest.chapters.first.hasText, isFalse);
      expect(manifest.chapters.first.textFile, isNull);
    });

    test('rejects packages that are not books', () {
      expect(() => BookManifest.parse('not json'),
          throwsA(isA<ManifestException>()));
      expect(() => BookManifest.parse('{"book":"X"}'),
          throwsA(isA<ManifestException>()));
      expect(() => BookManifest.parse('{"book":"X","chapters":[]}'),
          throwsA(isA<ManifestException>()));
      expect(() => BookManifest.parse('[1,2,3]'),
          throwsA(isA<ManifestException>()));
    });

    test('supplies a title when the manifest omits one', () {
      final manifest = BookManifest.parse(
          '{"chapters":[{"index":1,"title":"a","audio":"a.m4a","seconds":1}]}');
      expect(manifest.title, 'Untitled book');
    });
  });

  group('BookImporter.idForTitle', () {
    test('is stable for the same title', () {
      final a = BookImporter.idForTitle('Batı Felsefesi Tarihi 01');
      final b = BookImporter.idForTitle('Batı Felsefesi Tarihi 01');
      expect(a, b);
    });

    test('differs between titles', () {
      expect(BookImporter.idForTitle('Book One'),
          isNot(BookImporter.idForTitle('Book Two')));
    });

    test('produces a filesystem-safe name', () {
      final id = BookImporter.idForTitle('Batı: Felsefesi/Tarihi 01 (İlk Çağ)!');
      expect(id, matches(RegExp(r'^[a-zà-ɏ0-9-]+$')));
      expect(id.contains('/'), isFalse);
    });
  });

  group('Book progress', () {
    Book book(int chapterIndex, Duration position) => Book(
          id: 'x',
          title: 'X',
          dirPath: '/tmp/x',
          chapters: [
            for (var i = 0; i < 4; i++)
              Chapter(
                index: i + 1,
                rawTitle: 'c$i',
                audioFile: 'c$i.m4a',
                textFile: 'c$i.txt',
                duration: const Duration(seconds: 100),
              ),
          ],
          totalDuration: const Duration(seconds: 400),
          importedAt: DateTime(2026),
          progress: BookProgress(
              chapterIndex: chapterIndex, position: position),
        );

    test('elapsed counts whole chapters plus the offset', () {
      expect(book(2, const Duration(seconds: 30)).elapsed,
          const Duration(seconds: 230));
    });

    test('fraction stays within 0..1', () {
      expect(book(0, Duration.zero).fraction, 0);
      expect(book(3, const Duration(seconds: 100)).fraction, 1);
      expect(book(3, const Duration(seconds: 9999)).fraction, 1);
    });

    test('clamps an out-of-range saved chapter', () {
      expect(book(99, Duration.zero).safeChapterIndex, 3);
    });
  });
}
