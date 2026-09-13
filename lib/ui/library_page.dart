import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../models/book.dart';
import '../services/importer.dart';
import 'book_page.dart';
import 'format.dart';
import 'mini_player.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  Future<void> _addBook() async {
    FilePickerResult? picked;
    try {
      // FileType.any rather than a 'zip' filter: Android file providers report
      // zips under several MIME types (application/zip, x-zip-compressed,
      // octet-stream), and a custom filter can hide the file entirely. The
      // extension is checked below instead.
      picked = await FilePicker.platform.pickFiles(type: FileType.any);
    } catch (e) {
      _toast('Could not open the file picker: $e');
      return;
    }
    if (picked == null || picked.files.isEmpty) return;
    final path = picked.files.single.path;
    if (path == null) {
      _toast('That file could not be opened from storage.');
      return;
    }
    if (!path.toLowerCase().endsWith('.zip')) {
      _toast('Pick a book .zip package.');
      return;
    }

    await _runImport(path);
    // The picker copies the chosen file into a cache dir; don't leave 200 MB
    // of it sitting there.
    try {
      await FilePicker.platform.clearTemporaryFiles();
    } catch (_) {/* best effort */}
  }

  Future<void> _runImport(String path, {bool replace = false}) async {
    try {
      final result = await library.importZip(path, replace: replace);
      if (!mounted) return;
      if (result.alreadyPresent) {
        final again = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Already in your library'),
            content: Text(
              '“${result.book.title}” is already unpacked, so nothing was '
              'extracted. Unpack it again from this zip?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Keep existing'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Unpack again'),
              ),
            ],
          ),
        );
        if (again == true) await _runImport(path, replace: true);
        return;
      }
      _toast('Added “${result.book.title}”');
    } on ImportException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('Import failed: $e');
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _confirmDelete(Book book) async {
    final sizeBytes = await library.sizeOnDisk(book);
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove “${book.title}”?'),
        content: Text(
          'This deletes the unpacked files (${formatBytes(sizeBytes)}) and your '
          'place in the book. Your original .zip is not touched.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true) await library.remove(book);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: library,
      builder: (context, _) {
        final books = library.books;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Library'),
          ),
          floatingActionButton: library.isImporting
              ? null
              : FloatingActionButton.extended(
                  onPressed: _addBook,
                  icon: const Icon(Icons.add),
                  label: const Text('Add book'),
                ),
          bottomNavigationBar: const MiniPlayer(),
          body: Builder(
            builder: (context) {
              if (library.loading) {
                return const Center(child: CircularProgressIndicator());
              }
              if (library.isImporting) {
                return _ImportingView(progress: library.importProgress!);
              }
              if (books.isEmpty) return const _EmptyLibrary();
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                itemCount: books.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) => _BookCard(
                  book: books[i],
                  onOpen: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => BookPage(book: books[i])),
                  ),
                  onDelete: () => _confirmDelete(books[i]),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _ImportingView extends StatelessWidget {
  const _ImportingView({required this.progress});

  final ImportProgress progress;

  @override
  Widget build(BuildContext context) {
    final fraction = progress.fraction;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 220,
              child: LinearProgressIndicator(value: fraction),
            ),
            const SizedBox(height: 20),
            Text(progress.label,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              progress.total > 0
                  ? '${progress.done} of ${progress.total} files'
                  : 'Please wait…',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 18),
            Text(
              'This happens once per book. Afterwards it opens straight from '
              'the unpacked copy.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.library_books_outlined,
                size: 72, color: scheme.primary.withValues(alpha: 0.7)),
            const SizedBox(height: 20),
            Text('No books yet',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            Text(
              'Tap “Add book” and pick a book .zip. It gets unpacked once and '
              'then lives in your library — audio and text together.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _BookCard extends StatelessWidget {
  const _BookCard({
    required this.book,
    required this.onOpen,
    required this.onDelete,
  });

  final Book book;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final remaining = book.totalDuration - book.elapsed;
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Cover(title: book.title),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${formatLongDuration(book.totalDuration)} · '
                      '${book.chapters.length} parts',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 10),
                    if (book.progress.isStarted) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: book.fraction,
                          minHeight: 5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${(book.fraction * 100).round()}% · '
                        '${formatLongDuration(remaining)} left',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ] else
                      Text(
                        'Not started',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Remove',
                icon: const Icon(Icons.delete_outline),
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Deterministic stand-in cover, since packages carry no artwork.
class _Cover extends StatelessWidget {
  const _Cover({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    var hash = 0;
    for (final unit in title.codeUnits) {
      hash = (hash * 31 + unit) & 0x7FFFFFFF;
    }
    final hue = (hash % 360).toDouble();
    final top = HSLColor.fromAHSL(1, hue, 0.45, 0.42).toColor();
    final bottom = HSLColor.fromAHSL(1, (hue + 38) % 360, 0.5, 0.28).toColor();
    final initials = title
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();

    return Container(
      width: 58,
      height: 84,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [top, bottom],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 20,
        ),
      ),
    );
  }
}
