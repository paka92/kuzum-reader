import 'package:kuzum_reader/models/book.dart';
import 'package:kuzum_reader/models/naming.dart';
import 'package:flutter_test/flutter_test.dart';

Chapter ch(String title, {int seconds = 100, String? text}) => Chapter(
      index: 1,
      rawTitle: title,
      audioFile: '$title.m4a',
      textFile: text ?? '$title.txt',
      duration: Duration(seconds: seconds),
    );

void main() {
  group('parseChapterName', () {
    test('parses the package naming convention', () {
      final parsed = parseChapterName('008_02_bolum_01_part_01');
      expect(parsed, isNotNull);
      expect(parsed!.sequence, 8);
      expect(parsed.sectionOrder, 2);
      expect(parsed.sectionSlug, 'bolum_01');
      expect(parsed.part, 1);
      expect(parsed.sectionKey, '2_bolum_01');
    });

    test('parses single-word sections', () {
      final parsed = parseChapterName('001_00_onsoz_part_01');
      expect(parsed!.sectionSlug, 'onsoz');
      expect(parsed.sectionOrder, 0);
    });

    test('returns null for names off the convention', () {
      expect(parseChapterName('intro'), isNull);
      expect(parseChapterName('01-chapter-one'), isNull);
      expect(parseChapterName(''), isNull);
    });
  });

  group('prettifySlug', () {
    test('translates known Turkish slugs and strips zero padding', () {
      expect(prettifySlug('bolum_01'), 'Bölüm 1');
      expect(prettifySlug('onsoz'), 'Önsöz');
      expect(prettifySlug('giris'), 'Giriş');
      expect(prettifySlug('bolum_30'), 'Bölüm 30');
    });

    test('falls back to capitalisation for unknown words', () {
      expect(prettifySlug('some_other_name'), 'Some Other Name');
      expect(prettifySlug('chapter_07'), 'Chapter 7');
    });
  });

  group('titles', () {
    test('full title combines section and part', () {
      expect(fullChapterTitle(ch('010_02_bolum_01_part_03')),
          'Bölüm 1 · Part 3');
    });

    test('part label is short', () {
      expect(chapterPartLabel(ch('010_02_bolum_01_part_03')), 'Part 3');
    });

    test('unconventional names still produce something readable', () {
      expect(fullChapterTitle(ch('05_strange_name')), 'Strange Name');
    });
  });

  group('buildSections', () {
    test('groups consecutive parts and sums their durations', () {
      final chapters = [
        ch('001_00_onsoz_part_01', seconds: 230),
        ch('002_01_giris_part_01', seconds: 260),
        ch('003_01_giris_part_02', seconds: 249),
        ch('004_02_bolum_01_part_01', seconds: 233),
      ];
      final sections = buildSections(chapters);

      expect(sections.length, 3);
      expect(sections[0].title, 'Önsöz');
      expect(sections[0].chapterIndices, [0]);
      expect(sections[1].title, 'Giriş');
      expect(sections[1].chapterIndices, [1, 2]);
      expect(sections[1].duration, const Duration(seconds: 509));
      expect(sections[2].title, 'Bölüm 1');
      expect(sections[2].chapterIndices, [3]);
    });

    test('keeps every chapter exactly once', () {
      final chapters = [
        for (var i = 1; i <= 20; i++)
          ch('${i.toString().padLeft(3, '0')}_'
              '${(i ~/ 5).toString().padLeft(2, '0')}_bolum_0${i ~/ 5}_part_0${i % 5}'),
      ];
      final sections = buildSections(chapters);
      final covered = sections.expand((s) => s.chapterIndices).toList()..sort();
      expect(covered, List.generate(20, (i) => i));
    });

    test('unparseable names each become their own section', () {
      final sections = buildSections([ch('weird_one'), ch('weird_two')]);
      expect(sections.length, 2);
    });

    test('handles an empty book', () {
      expect(buildSections(const []), isEmpty);
    });
  });
}
