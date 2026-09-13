import 'package:flutter_test/flutter_test.dart';
import 'package:kuzum_reader/services/sharing.dart';

void main() {
  group('ShareService.safeFileName', () {
    test('keeps readable names, Turkish characters included', () {
      expect(
        ShareService.safeFileName(
            'Batı Felsefesi Tarihi 01 — Bölüm 22 · Part 3'),
        'Batı Felsefesi Tarihi 01 — Bölüm 22 · Part 3',
      );
    });

    test('strips characters receivers reject', () {
      expect(ShareService.safeFileName('a/b\\c:d*e?f"g<h>i|j'),
          'a b c d e f g h i j');
    });

    test('collapses whitespace and trims', () {
      expect(ShareService.safeFileName('  a   b\t c  '), 'a b c');
    });

    test('never returns an empty name', () {
      expect(ShareService.safeFileName('///'), 'passage');
      expect(ShareService.safeFileName(''), 'passage');
    });

    test('caps very long names', () {
      final long = ShareService.safeFileName('x' * 300);
      expect(long.length, lessThanOrEqualTo(120));
    });
  });

  group('ShareService.buildAskPrompt', () {
    test('single passage: Turkish prompt naming the book, then the text', () {
      final prompt = ShareService.buildAskPrompt(
        bookTitle: 'Batı Felsefesi Tarihi 01',
        passages: [(title: 'Bölüm 3 · Part 2', text: 'Thales her şeyin su olduğunu söyler.')],
      );
      expect(prompt,
          startsWith('Aşağıdaki pasaj "Batı Felsefesi Tarihi 01" adlı kitaptan alındı.'));
      expect(prompt, contains('Bu pasajı anlamama yardım et:'));
      expect(prompt, contains('Pasajın ana fikrini açıkla.'));
      expect(prompt, contains('yer adları veya kişiler'));
      expect(prompt, contains('terminoloji'));
      expect(prompt, contains('Cevabını tamamen Türkçe yaz.'));
      expect(prompt, contains('--- Bölüm 3 · Part 2 ---'));
      expect(prompt, endsWith('Thales her şeyin su olduğunu söyler.'));
      // Instructions come before the passage, so the bot reads them first.
      expect(prompt.indexOf('Türkçe yaz'), lessThan(prompt.indexOf('---')));
    });

    test('multiple passages: plural wording and every part labelled', () {
      final prompt = ShareService.buildAskPrompt(
        bookTitle: 'Kitap',
        passages: [
          (title: 'Bölüm 1 · Part 1', text: 'Birinci pasaj.'),
          (title: 'Bölüm 1 · Part 2', text: 'İkinci pasaj.'),
        ],
      );
      expect(prompt, startsWith('Aşağıdaki pasajlar "Kitap" adlı kitaptan alındı.'));
      expect(prompt, contains('Bu pasajları anlamama yardım et:'));
      expect(prompt, contains('--- Bölüm 1 · Part 1 ---\nBirinci pasaj.'));
      expect(prompt, contains('--- Bölüm 1 · Part 2 ---\nİkinci pasaj.'));
    });
  });

  group('ShareOutcome', () {
    test('nothingToShare only when zero files went out', () {
      expect(const ShareOutcome(shared: 0, skipped: 3).nothingToShare, isTrue);
      expect(const ShareOutcome(shared: 2, skipped: 1).nothingToShare, isFalse);
    });
  });
}
