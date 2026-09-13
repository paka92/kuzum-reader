import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/book.dart';
import '../models/naming.dart';

/// One passage headed for a chatbot: where it came from, plus the text.
typedef Passage = ({String title, String text});

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

  static const MethodChannel _channel = MethodChannel('kuzum_reader/share');

  /// ChatGPT's Android application id.
  static const chatGptPackage = 'com.openai.chatgpt';

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

  /// Reads the text of [chapters] as passages for a chatbot prompt. Parts
  /// without text are counted as skipped rather than sent empty.
  static Future<(List<Passage>, int)> loadPassages(
      Book book, List<Chapter> chapters) async {
    final passages = <Passage>[];
    var skipped = 0;
    for (final chapter in chapters) {
      final path = book.textPathFor(chapter);
      if (path == null || !await File(path).exists()) {
        skipped++;
        continue;
      }
      final file = File(path);
      String text;
      try {
        text = await file.readAsString();
      } catch (_) {
        // Same lenient fallback the reader uses for oddly encoded files.
        text = String.fromCharCodes(await file.readAsBytes());
      }
      if (text.trim().isEmpty) {
        skipped++;
        continue;
      }
      passages.add((title: fullChapterTitle(chapter), text: text.trim()));
    }
    return (passages, skipped);
  }

  /// Wraps passages in a Turkish "help me understand this" prompt, so a
  /// chatbot immediately knows the source book and what to do: explain the
  /// main idea, brief the people and places, unpack the terminology — and
  /// answer in Turkish.
  static String buildAskPrompt({
    required String bookTitle,
    required List<Passage> passages,
  }) {
    final plural = passages.length > 1;
    final b = StringBuffer()
      ..writeln(plural
          ? 'Aşağıdaki pasajlar "$bookTitle" adlı kitaptan alındı.'
          : 'Aşağıdaki pasaj "$bookTitle" adlı kitaptan alındı.')
      ..writeln()
      ..writeln(plural
          ? 'Bu pasajları anlamama yardım et:'
          : 'Bu pasajı anlamama yardım et:')
      ..writeln('- Pasajın ana fikrini açıkla.')
      ..writeln(
          '- Geçen yer adları veya kişiler varsa, her biri hakkında kısa bilgi ver.')
      ..writeln('- Özel terimler (terminoloji) varsa, bunları açıkla.')
      ..writeln('Cevabını tamamen Türkçe yaz.');
    for (final passage in passages) {
      b
        ..writeln()
        ..writeln('--- ${passage.title} ---')
        ..writeln(passage.text);
    }
    return b.toString().trimRight();
  }

  /// Opens [prompt] straight in the ChatGPT app — the go-to assistant. When
  /// ChatGPT isn't installed (or on iOS, where a specific app can't be
  /// targeted), falls back to the system share sheet so any assistant works.
  static Future<void> askChatGpt(String prompt) async {
    if (Platform.isAndroid) {
      try {
        final opened = await _channel.invokeMethod<bool>('sendTextTo', {
          'text': prompt,
          'package': chatGptPackage,
        });
        if (opened == true) return;
      } on PlatformException {
        // Fall through to the share sheet.
      }
    }
    await shareText(prompt);
  }
}
