import 'package:flutter/material.dart';

import '../models/book.dart';
import '../services/sharing.dart';

enum _ShareAction { askChatGpt, askOtherAi, shareFiles }

/// Bottom sheet listing the ways to send passages onward. "Ask ChatGPT" sits
/// on top — the go-to assistant — followed by the same prompt through the
/// system share sheet for any other AI, then a plain file share.
///
/// Returns true when an action actually shared something, so callers can
/// leave selection mode.
Future<bool> showPassageShareSheet(
  BuildContext context, {
  required Book book,
  required List<Chapter> chapters,
}) async {
  final many = chapters.length > 1;
  final action = await showModalBottomSheet<_ShareAction>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.smart_toy_outlined),
            title: const Text('Ask ChatGPT'),
            subtitle: Text(
                'Opens ChatGPT with a Türkçe "bu pasajı açıkla" prompt for '
                '${many ? 'the selected parts' : 'this part'}'),
            onTap: () => Navigator.pop(context, _ShareAction.askChatGpt),
          ),
          ListTile(
            leading: const Icon(Icons.auto_awesome_outlined),
            title: const Text('Ask another AI…'),
            subtitle: const Text('Same prompt — pick the app yourself'),
            onTap: () => Navigator.pop(context, _ShareAction.askOtherAi),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: Text(many ? 'Share as text files' : 'Share as a text file'),
            subtitle: const Text('Just the text, no prompt around it'),
            onTap: () => Navigator.pop(context, _ShareAction.shareFiles),
          ),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return false;

  void toast(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  switch (action) {
    case _ShareAction.askChatGpt:
    case _ShareAction.askOtherAi:
      final (passages, skipped) =
          await ShareService.loadPassages(book, chapters);
      if (!context.mounted) return false;
      if (passages.isEmpty) {
        toast(many
            ? 'None of the selected parts have text to ask about.'
            : 'This part has no text to ask about.');
        return false;
      }
      if (skipped > 0) {
        toast('$skipped selected part(s) have no text and were left out.');
      }
      final prompt = ShareService.buildAskPrompt(
          bookTitle: book.title, passages: passages);
      if (action == _ShareAction.askChatGpt) {
        await ShareService.askChatGpt(prompt);
      } else {
        await ShareService.shareText(prompt, subject: book.title);
      }
      return true;
    case _ShareAction.shareFiles:
      final outcome = await ShareService.shareChapterTexts(book, chapters);
      if (!context.mounted) return !outcome.nothingToShare;
      if (outcome.nothingToShare) {
        toast(many
            ? 'None of the selected parts have text to share.'
            : 'This part has no text to share.');
        return false;
      }
      if (outcome.skipped > 0) {
        toast(
            '${outcome.skipped} selected part(s) have no text and were left out.');
      }
      return true;
  }
}
