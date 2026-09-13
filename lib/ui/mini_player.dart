import 'package:flutter/material.dart';

import '../main.dart';
import '../models/book.dart';
import '../models/naming.dart';
import 'reader_page.dart';

/// Compact now-playing strip shown above the bottom of the library / book list.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: player.currentBookId,
      builder: (context, bookId, _) {
        if (bookId == null) return const SizedBox.shrink();
        final book = library.byId(bookId);
        if (book == null) return const SizedBox.shrink();
        return ValueListenableBuilder<int>(
          valueListenable: player.currentChapter,
          builder: (context, chapterIndex, _) {
            final chapter = chapterIndex < book.chapters.length
                ? book.chapters[chapterIndex]
                : null;
            return _Strip(book: book, chapter: chapter);
          },
        );
      },
    );
  }
}

class _Strip extends StatelessWidget {
  const _Strip({required this.book, required this.chapter});

  final Book book;
  final Chapter? chapter;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ReaderPage(book: book)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.menu_book_outlined, color: scheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        book.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      if (chapter != null)
                        Text(
                          fullChapterTitle(chapter!),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
                StreamBuilder<bool>(
                  stream: player.playerStateStream.map((s) => s.playing),
                  initialData: player.playing,
                  builder: (context, snapshot) {
                    final playing = snapshot.data ?? false;
                    return IconButton(
                      iconSize: 34,
                      icon: Icon(playing
                          ? Icons.pause_circle_filled
                          : Icons.play_circle_fill),
                      onPressed: () =>
                          playing ? player.pause() : player.play(),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
