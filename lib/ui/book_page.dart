import 'package:flutter/material.dart';

import '../main.dart';
import '../models/book.dart';
import '../models/naming.dart';
import '../services/sharing.dart';
import 'format.dart';
import 'mini_player.dart';
import 'reader_page.dart';

/// Table of contents for one book: sections, and the parts inside them.
/// Choosing a part is how you pick which text gets read aloud.
class BookPage extends StatefulWidget {
  const BookPage({super.key, required this.book});

  final Book book;

  @override
  State<BookPage> createState() => _BookPageState();
}

class _BookPageState extends State<BookPage> {
  late final List<Section> _sections = buildSections(widget.book.chapters);

  /// Chapter indices picked for sharing. Long-press any part to start
  /// selecting; a share button appears in the app bar.
  final Set<int> _selected = {};

  Book get book => widget.book;

  bool get _selecting => _selected.isNotEmpty;

  void _toggleSelected(int chapterIndex) {
    setState(() {
      if (!_selected.remove(chapterIndex)) _selected.add(chapterIndex);
    });
  }

  /// Long-pressing a section header selects the whole section (or clears it
  /// if every part was already selected).
  void _toggleSection(Section section) {
    setState(() {
      final allIn = section.chapterIndices.every(_selected.contains);
      if (allIn) {
        _selected.removeAll(section.chapterIndices);
      } else {
        _selected.addAll(section.chapterIndices);
      }
    });
  }

  Future<void> _shareSelected() async {
    final indices = _selected.toList()..sort();
    final chapters = [for (final i in indices) book.chapters[i]];
    final outcome = await ShareService.shareChapterTexts(book, chapters);
    if (!mounted) return;
    if (outcome.nothingToShare) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('None of the selected parts have text to share.')));
      return;
    }
    if (outcome.skipped > 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '${outcome.skipped} selected part(s) have no text and were left out.')));
    }
    setState(() => _selected.clear());
  }

  Future<void> _open(int chapterIndex, {bool autoPlay = true}) async {
    await player.openBook(
      book,
      chapterIndex: chapterIndex,
      // Starting a part plays it from the beginning; resuming keeps its offset.
      position: Duration.zero,
      autoPlay: autoPlay,
    );
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ReaderPage(book: book)),
    );
  }

  Future<void> _resume() async {
    await player.openBook(
      book,
      chapterIndex: book.safeChapterIndex,
      position: book.progress.position,
      autoPlay: true,
    );
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ReaderPage(book: book)),
    );
  }

  /// Index of the section containing [chapterIndex].
  int _sectionOf(int chapterIndex) {
    for (var i = 0; i < _sections.length; i++) {
      if (_sections[i].chapterIndices.contains(chapterIndex)) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Back leaves selection mode before it leaves the page.
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _selected.clear());
      },
      child: Scaffold(
        appBar: _selecting
            ? AppBar(
                leading: IconButton(
                  tooltip: 'Cancel selection',
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => _selected.clear()),
                ),
                title: Text('${_selected.length} selected'),
                actions: [
                  IconButton(
                    tooltip: 'Share selected parts as text files',
                    icon: const Icon(Icons.share),
                    onPressed: _shareSelected,
                  ),
                ],
              )
            : AppBar(title: Text(book.title, maxLines: 1)),
        bottomNavigationBar: const MiniPlayer(),
        body: ListenableBuilder(
        listenable: library,
        builder: (context, _) {
          final current = _sectionOf(book.safeChapterIndex);
          return ValueListenableBuilder<int>(
            valueListenable: player.currentChapter,
            builder: (context, playingIndex, _) {
              final loaded = player.isLoaded(book.id);
              return ListView.builder(
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: _sections.length + 1,
                itemBuilder: (context, i) {
                  if (i == 0) return _Header(book: book, onResume: _resume);
                  final section = _sections[i - 1];
                  final containsPlaying = loaded &&
                      section.chapterIndices.contains(playingIndex);
                  return _SectionTile(
                    book: book,
                    section: section,
                    initiallyExpanded: i - 1 == current,
                    playingIndex: loaded ? playingIndex : -1,
                    highlight: containsPlaying,
                    selecting: _selecting,
                    selected: _selected,
                    onSelect: _open,
                    onToggleSelect: _toggleSelected,
                    onToggleSection: _toggleSection,
                  );
                },
              );
            },
          );
        },
      ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.book, required this.onResume});

  final Book book;
  final VoidCallback onResume;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final started = book.progress.isStarted;
    final chapter = book.chapters[book.safeChapterIndex];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${formatLongDuration(book.totalDuration)} · '
            '${book.chapters.length} parts',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          if (started) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                  value: book.fraction, minHeight: 6),
            ),
            const SizedBox(height: 8),
            Text(
              'At ${fullChapterTitle(chapter)} · '
              '${formatDuration(book.progress.position)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onResume,
              icon: Icon(started ? Icons.play_arrow : Icons.headphones),
              label: Text(started ? 'Continue listening' : 'Start listening'),
            ),
          ),
          const SizedBox(height: 8),
          const Divider(),
        ],
      ),
    );
  }
}

class _SectionTile extends StatelessWidget {
  const _SectionTile({
    required this.book,
    required this.section,
    required this.initiallyExpanded,
    required this.playingIndex,
    required this.highlight,
    required this.selecting,
    required this.selected,
    required this.onSelect,
    required this.onToggleSelect,
    required this.onToggleSection,
  });

  final Book book;
  final Section section;
  final bool initiallyExpanded;
  final int playingIndex;
  final bool highlight;
  final bool selecting;
  final Set<int> selected;
  final void Function(int chapterIndex) onSelect;
  final void Function(int chapterIndex) onToggleSelect;
  final void Function(Section section) onToggleSection;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final single = section.chapterIndices.length == 1;

    // A one-part section needs no expansion — tapping it just plays.
    if (single) {
      final index = section.chapterIndices.first;
      final isPlaying = index == playingIndex;
      final isSelected = selected.contains(index);
      return ListTile(
        selected: isSelected,
        selectedTileColor: scheme.primaryContainer.withValues(alpha: 0.35),
        leading: Icon(
          selecting
              ? (isSelected
                  ? Icons.check_circle
                  : Icons.radio_button_unchecked)
              : (isPlaying ? Icons.graphic_eq : Icons.article_outlined),
          color: isSelected || isPlaying ? scheme.primary : null,
        ),
        title: Text(
          section.title,
          style: TextStyle(
            fontWeight: isPlaying ? FontWeight.w700 : FontWeight.w500,
            color: isPlaying ? scheme.primary : null,
          ),
        ),
        trailing: Text(formatDuration(section.duration),
            style: Theme.of(context).textTheme.bodySmall),
        onTap: () =>
            selecting ? onToggleSelect(index) : onSelect(index),
        onLongPress: () => onToggleSelect(index),
      );
    }

    return ExpansionTile(
      initiallyExpanded: initiallyExpanded,
      shape: const Border(),
      collapsedShape: const Border(),
      leading: Icon(
        highlight ? Icons.graphic_eq : Icons.folder_outlined,
        color: highlight ? scheme.primary : null,
      ),
      // Long-press the section title to select or clear every part in it.
      title: GestureDetector(
        onLongPress: () => onToggleSection(section),
        child: Text(
          section.title,
          style: TextStyle(
            fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
            color: highlight ? scheme.primary : null,
          ),
        ),
      ),
      subtitle: Text(
        '${section.chapterIndices.length} parts · '
        '${formatLongDuration(section.duration)}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      childrenPadding: const EdgeInsets.only(left: 12),
      children: [
        for (final index in section.chapterIndices)
          _PartRow(
            chapter: book.chapters[index],
            isPlaying: index == playingIndex,
            selecting: selecting,
            isSelected: selected.contains(index),
            onTap: () =>
                selecting ? onToggleSelect(index) : onSelect(index),
            onLongPress: () => onToggleSelect(index),
          ),
      ],
    );
  }
}

class _PartRow extends StatelessWidget {
  const _PartRow({
    required this.chapter,
    required this.isPlaying,
    required this.selecting,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
  });

  final Chapter chapter;
  final bool isPlaying;
  final bool selecting;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      selected: isSelected,
      selectedTileColor: scheme.primaryContainer.withValues(alpha: 0.35),
      leading: Icon(
        selecting
            ? (isSelected ? Icons.check_circle : Icons.radio_button_unchecked)
            : (isPlaying ? Icons.graphic_eq : Icons.play_arrow_outlined),
        size: 20,
        color: isSelected
            ? scheme.primary
            : (isPlaying ? scheme.primary : scheme.onSurfaceVariant),
      ),
      title: Text(
        chapterPartLabel(chapter),
        style: TextStyle(
          color: isPlaying ? scheme.primary : null,
          fontWeight: isPlaying ? FontWeight.w700 : null,
        ),
      ),
      subtitle: chapter.hasText
          ? null
          : Text('No text for this part',
              style: Theme.of(context).textTheme.bodySmall),
      trailing: Text(formatDuration(chapter.duration),
          style: Theme.of(context).textTheme.bodySmall),
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}
