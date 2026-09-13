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

  group('ShareOutcome', () {
    test('nothingToShare only when zero files went out', () {
      expect(const ShareOutcome(shared: 0, skipped: 3).nothingToShare, isTrue);
      expect(const ShareOutcome(shared: 2, skipped: 1).nothingToShare, isFalse);
    });
  });
}
