/// Parsing and prettifying of the chapter file naming convention used by the
/// book packages: `008_02_bolum_01_part_01` ->
/// sequence 8, section `02_bolum_01`, part 1.
library;

import 'book.dart';

final RegExp _namePattern = RegExp(r'^(\d+)_(\d+)_(.+?)_part_(\d+)$');
final RegExp _leadingSequence = RegExp(r'^\d+_');
final RegExp _separators = RegExp(r'[_\s-]+');

/// Known slug -> display word translations. Unknown slugs fall back to
/// capitalisation, so packages in any language still read sensibly.
const Map<String, String> _slugWords = {
  'onsoz': 'Önsöz',
  'oensoz': 'Önsöz',
  'giris': 'Giriş',
  'bolum': 'Bölüm',
  'kisim': 'Kısım',
  'sonsoz': 'Sonsöz',
  'sonuc': 'Sonuç',
  'kaynakca': 'Kaynakça',
  'kaynaklar': 'Kaynaklar',
  'dizin': 'Dizin',
  'ek': 'Ek',
  'ekler': 'Ekler',
  'preface': 'Preface',
  'intro': 'Introduction',
  'introduction': 'Introduction',
  'chapter': 'Chapter',
  'prologue': 'Prologue',
  'epilogue': 'Epilogue',
  'appendix': 'Appendix',
  'afterword': 'Afterword',
  'foreword': 'Foreword',
  'notes': 'Notes',
  'index': 'Index',
};

class ParsedChapterName {
  final int sequence;
  final int sectionOrder;
  final String sectionSlug;
  final int part;

  const ParsedChapterName({
    required this.sequence,
    required this.sectionOrder,
    required this.sectionSlug,
    required this.part,
  });

  /// Stable key that groups all parts of one section together.
  String get sectionKey => '${sectionOrder}_$sectionSlug';
}

ParsedChapterName? parseChapterName(String raw) {
  final m = _namePattern.firstMatch(raw.trim());
  if (m == null) return null;
  final seq = int.tryParse(m.group(1)!);
  final order = int.tryParse(m.group(2)!);
  final part = int.tryParse(m.group(4)!);
  if (seq == null || order == null || part == null) return null;
  return ParsedChapterName(
    sequence: seq,
    sectionOrder: order,
    sectionSlug: m.group(3)!,
    part: part,
  );
}

String _capitalize(String word) {
  if (word.isEmpty) return word;
  return word[0].toUpperCase() + word.substring(1);
}

/// `bolum_01` -> `Bölüm 1`, `giris` -> `Giriş`, `some_other_name` -> `Some Other Name`.
String prettifySlug(String slug) {
  final words = <String>[];
  for (final token in slug.split(_separators)) {
    if (token.isEmpty) continue;
    final asNumber = int.tryParse(token);
    if (asNumber != null) {
      words.add(asNumber.toString());
      continue;
    }
    words.add(_slugWords[token.toLowerCase()] ?? _capitalize(token));
  }
  return words.isEmpty ? slug : words.join(' ');
}

/// Fallback for names that do not follow the convention at all.
String prettifyRawTitle(String raw) =>
    prettifySlug(raw.replaceFirst(_leadingSequence, ''));

/// Title for a chapter on its own, e.g. `Bölüm 1 · Part 3`.
String fullChapterTitle(Chapter chapter) {
  final parsed = parseChapterName(chapter.rawTitle);
  if (parsed == null) return prettifyRawTitle(chapter.rawTitle);
  return '${prettifySlug(parsed.sectionSlug)} · Part ${parsed.part}';
}

/// Short title used inside an already-labelled section, e.g. `Part 3`.
String chapterPartLabel(Chapter chapter) {
  final parsed = parseChapterName(chapter.rawTitle);
  if (parsed == null) return prettifyRawTitle(chapter.rawTitle);
  return 'Part ${parsed.part}';
}

/// A run of consecutive chapters that belong to the same section.
class Section {
  final String title;
  final List<int> chapterIndices;
  final Duration duration;

  const Section({
    required this.title,
    required this.chapterIndices,
    required this.duration,
  });
}

/// Groups chapters into sections, preserving manifest order. Chapters whose
/// names do not match the convention each become their own section.
List<Section> buildSections(List<Chapter> chapters) {
  final sections = <Section>[];
  String? currentKey;
  String currentTitle = '';
  var bucket = <int>[];

  void flush() {
    if (bucket.isEmpty) return;
    var total = Duration.zero;
    for (final i in bucket) {
      total += chapters[i].duration;
    }
    sections.add(Section(
      title: currentTitle,
      chapterIndices: List.unmodifiable(bucket),
      duration: total,
    ));
    bucket = <int>[];
  }

  for (var i = 0; i < chapters.length; i++) {
    final parsed = parseChapterName(chapters[i].rawTitle);
    final key = parsed?.sectionKey ?? 'unparsed_$i';
    final title = parsed != null
        ? prettifySlug(parsed.sectionSlug)
        : prettifyRawTitle(chapters[i].rawTitle);
    if (key != currentKey) {
      flush();
      currentKey = key;
      currentTitle = title;
    }
    bucket.add(i);
  }
  flush();
  return sections;
}
