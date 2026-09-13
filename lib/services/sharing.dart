import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/book.dart';
import '../models/naming.dart';

/// What a share attempt did, so the UI can explain partial results.
class ShareOutcome {
  final int shared;
  final int skipped;

  const ShareOutcome({required this.shared, required this.skipped});

  bool get nothingToShare => shared == 0;
}

/// Hands passages to the system share sheet — the route into chat apps,
/// messengers, and anything else that accepts text or files.
class ShareService {
  static final RegExp _unsafeFileChars = RegExp(r'[\\/:*?"<>|\x00-\x1F]');
  static final RegExp _spaces = RegExp(r'\s+');

  /// A name safe for receivers on any platform, with the words kept readable.
  static String safeFileName(String name) {
    final cleaned =
        name.replaceAll(_unsafeFileChars, ' ').replaceAll(_spaces, ' ').trim();
    if (cleaned.isEmpty) return 'passage';
    // Some receivers reject very long names.
    return cleaned.length > 120 ? cleaned.substring(0, 120).trim() : cleaned;
  }

  /// Shares the text of [chapters] as .txt files named after the book and
  /// part, so the receiving app (or chatbot) sees which passage is which.
  ///
  /// Files are copied into a fresh cache folder first: the library lives in
  /// app-private storage that other apps cannot read, while the share
  /// framework can expose cache files to the receiver.
  static Future<ShareOutcome> shareChapterTexts(
      Book book, List<Chapter> chapters) async {
    final tmpRoot = await getTemporaryDirectory();
    final shareDir = Directory(p.join(tmpRoot.path, 'share'));
    if (await shareDir.exists()) await shareDir.delete(recursive: true);
    await shareDir.create(recursive: true);

    final files = <XFile>[];
    var skipped = 0;
    for (final chapter in chapters) {
      final path = book.textPathFor(chapter);
      if (path == null || !await File(path).exists()) {
        skipped++;
        continue;
      }
      final name =
          '${safeFileName('${book.title} — ${fullChapterTitle(chapter)}')}.txt';
      final copy = await File(path).copy(p.join(shareDir.path, name));
      files.add(XFile(copy.path, mimeType: 'text/plain'));
    }

    if (files.isNotEmpty) {
      await SharePlus.instance.share(ShareParams(
        files: files,
        title: book.title,
      ));
    }
    return ShareOutcome(shared: files.length, skipped: skipped);
  }

  /// Shares a selected passage of text directly (e.g. into a chat app).
  static Future<void> shareText(String text, {String? subject}) =>
      SharePlus.instance.share(ShareParams(text: text, subject: subject));
}
