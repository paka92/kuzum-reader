import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../main.dart';
import '../models/book.dart';
import '../models/naming.dart';
import '../services/sharing.dart';
import 'format.dart';
import 'share_sheet.dart';

/// Reading view. The text shown is always the part the player has loaded, so
/// text and audio stay matched part-by-part — select a part and it reads that
/// part, while the position inside it is remembered.
class ReaderPage extends StatefulWidget {
  const ReaderPage({super.key, required this.book});

  final Book book;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  final ScrollController _scroll = ScrollController();
  final Map<int, Future<String>> _textCache = {};

  Book get book => widget.book;

  @override
  void initState() {
    super.initState();
    // Opened from the mini player or a cold start: make sure this book is the
    // one loaded, but don't start playing on its own.
    if (!player.isLoaded(book.id)) {
      player.openBook(
        book,
        chapterIndex: book.safeChapterIndex,
        position: book.progress.position,
        autoPlay: false,
      );
    }
    player.currentChapter.addListener(_onChapterChanged);
  }

  @override
  void dispose() {
    player.currentChapter.removeListener(_onChapterChanged);
    _scroll.dispose();
    super.dispose();
  }

  void _onChapterChanged() {
    // A new part started (often because the previous one finished while the
    // phone was in a pocket) — show it from the top.
    if (!mounted) return;
    if (_scroll.hasClients) _scroll.jumpTo(0);
    setState(() {});
  }

  Future<String> _textFor(int index) {
    return _textCache.putIfAbsent(index, () async {
      final chapter = book.chapters[index];
      final path = book.textPathFor(chapter);
      if (path == null) return '';
      final file = File(path);
      if (!await file.exists()) return '';
      try {
        return await file.readAsString();
      } catch (_) {
        // Fall back to a lenient decode for oddly encoded text files.
        return String.fromCharCodes(await file.readAsBytes());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: player.currentChapter,
      builder: (context, playingIndex, _) {
        final index = player.isLoaded(book.id)
            ? playingIndex.clamp(0, book.chapters.length - 1)
            : book.safeChapterIndex;
        final chapter = book.chapters[index];

        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(fullChapterTitle(chapter),
                    style: const TextStyle(fontSize: 16)),
                Text(
                  'Part ${index + 1} of ${book.chapters.length}',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'Ask AI about this part, or share it',
                icon: const Icon(Icons.share),
                onPressed: () => showPassageShareSheet(context,
                    book: book, chapters: [chapter]),
              ),
              PopupMenuButton<double>(
                tooltip: 'Text size',
                icon: const Icon(Icons.format_size),
                onSelected: library.setFontScale,
                itemBuilder: (context) => [
                  for (final scale in const [0.85, 1.0, 1.15, 1.35, 1.6])
                    CheckedPopupMenuItem(
                      value: scale,
                      checked: (library.fontScale - scale).abs() < 0.01,
                      child: Text('${(scale * 100).round()}%'),
                    ),
                ],
              ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: FutureBuilder<String>(
                  future: _textFor(index),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final text = snapshot.data ?? '';
                    if (text.trim().isEmpty) {
                      return _NoText(hasFile: chapter.hasText);
                    }
                    return ListenableBuilder(
                      listenable: library,
                      builder: (context, _) => Scrollbar(
                        controller: _scroll,
                        child: SingleChildScrollView(
                          controller: _scroll,
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                          child: SelectableText(
                            text.trim(),
                            style: TextStyle(
                              fontSize: 17 * library.fontScale,
                              height: 1.65,
                            ),
                            // Adds Share to the copy/select-all toolbar, so a
                            // highlighted passage can go straight to a chat
                            // app or chatbot.
                            contextMenuBuilder: (context, editableState) {
                              final value = editableState.textEditingValue;
                              final passage = value.selection.isValid
                                  ? value.selection.textInside(value.text)
                                  : '';
                              final items = [
                                // The go-to chatbot leads the toolbar, with
                                // the explain-this-passage prompt wrapped
                                // around the highlighted text.
                                if (passage.trim().isNotEmpty)
                                  ContextMenuButtonItem(
                                    label: 'Ask ChatGPT',
                                    onPressed: () {
                                      ContextMenuController.removeAny();
                                      ShareService.askChatGpt(
                                          ShareService.buildAskPrompt(
                                        bookTitle: book.title,
                                        passages: [
                                          (
                                            title: fullChapterTitle(chapter),
                                            text: passage.trim(),
                                          ),
                                        ],
                                      ));
                                    },
                                  ),
                                ...editableState.contextMenuButtonItems,
                                if (passage.trim().isNotEmpty)
                                  ContextMenuButtonItem(
                                    label: 'Share',
                                    onPressed: () {
                                      ContextMenuController.removeAny();
                                      ShareService.shareText(passage.trim());
                                    },
                                  ),
                              ];
                              return AdaptiveTextSelectionToolbar.buttonItems(
                                anchors: editableState.contextMenuAnchors,
                                buttonItems: items,
                              );
                            },
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              _PlayerPanel(book: book, chapterIndex: index),
            ],
          ),
        );
      },
    );
  }
}

class _NoText extends StatelessWidget {
  const _NoText({required this.hasFile});

  final bool hasFile;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.text_snippet_outlined, size: 48),
            const SizedBox(height: 12),
            Text(
              hasFile
                  ? 'The text file for this part could not be read.'
                  : 'This part has audio only — no text in the package.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Text('Playback works either way.',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// Transport controls. Mirrors what the lock-screen notification offers, so the
/// two behave identically.
class _PlayerPanel extends StatefulWidget {
  const _PlayerPanel({required this.book, required this.chapterIndex});

  final Book book;
  final int chapterIndex;

  @override
  State<_PlayerPanel> createState() => _PlayerPanelState();
}

class _PlayerPanelState extends State<_PlayerPanel> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              StreamBuilder<Duration>(
                stream: player.positionStream,
                initialData: player.position,
                builder: (context, snapshot) {
                  final total = player.chapterDuration;
                  final position = snapshot.data ?? Duration.zero;
                  final totalMs = total.inMilliseconds;
                  final value = _dragValue ??
                      (totalMs <= 0
                          ? 0.0
                          : position.inMilliseconds
                              .clamp(0, totalMs)
                              .toDouble());
                  return Column(
                    children: [
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3,
                          overlayShape:
                              const RoundSliderOverlayShape(overlayRadius: 14),
                        ),
                        child: Slider(
                          min: 0,
                          max: totalMs <= 0 ? 1 : totalMs.toDouble(),
                          value: totalMs <= 0 ? 0 : value,
                          onChanged: totalMs <= 0
                              ? null
                              : (v) => setState(() => _dragValue = v),
                          onChangeEnd: (v) {
                            setState(() => _dragValue = null);
                            player.seek(Duration(milliseconds: v.round()));
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              formatDuration(Duration(
                                  milliseconds: (_dragValue ?? value).round())),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            Text(formatDuration(total),
                                style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    tooltip: 'Previous part',
                    icon: const Icon(Icons.skip_previous),
                    onPressed: widget.chapterIndex > 0
                        ? () => player.skipToPrevious()
                        : null,
                  ),
                  IconButton(
                    tooltip: 'Back 30 seconds',
                    icon: const Icon(Icons.replay_30),
                    onPressed: () => player.rewind(),
                  ),
                  StreamBuilder<PlayerState>(
                    stream: player.playerStateStream,
                    builder: (context, snapshot) {
                      final state = snapshot.data;
                      final processing = state?.processingState;
                      final busy = processing == ProcessingState.loading ||
                          processing == ProcessingState.buffering;
                      final playing = state?.playing ?? false;
                      if (busy) {
                        return const SizedBox(
                          width: 56,
                          height: 56,
                          child: Center(
                            child: SizedBox(
                              width: 28,
                              height: 28,
                              child: CircularProgressIndicator(strokeWidth: 3),
                            ),
                          ),
                        );
                      }
                      return IconButton(
                        iconSize: 56,
                        icon: Icon(playing
                            ? Icons.pause_circle_filled
                            : Icons.play_circle_fill),
                        onPressed: () =>
                            playing ? player.pause() : player.play(),
                      );
                    },
                  ),
                  IconButton(
                    tooltip: 'Forward 30 seconds',
                    icon: const Icon(Icons.forward_30),
                    onPressed: () => player.fastForward(),
                  ),
                  IconButton(
                    tooltip: 'Next part',
                    icon: const Icon(Icons.skip_next),
                    onPressed:
                        widget.chapterIndex < widget.book.chapters.length - 1
                            ? () => player.skipToNext()
                            : null,
                  ),
                ],
              ),
              StreamBuilder<double>(
                stream: player.speedStream,
                initialData: player.speed,
                builder: (context, snapshot) {
                  final speed = snapshot.data ?? 1.0;
                  return Align(
                    alignment: Alignment.centerRight,
                    child: PopupMenuButton<double>(
                      tooltip: 'Playback speed',
                      onSelected: (v) {
                        player.setSpeed(v);
                        library.setSpeed(v);
                      },
                      itemBuilder: (context) => [
                        for (final s in const [0.75, 1.0, 1.25, 1.5, 1.75, 2.0])
                          CheckedPopupMenuItem(
                            value: s,
                            checked: (speed - s).abs() < 0.01,
                            child: Text('$s×'),
                          ),
                      ],
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.speed, size: 18),
                            const SizedBox(width: 6),
                            Text('$speed×'),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
