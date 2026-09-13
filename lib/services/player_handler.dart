import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import '../models/book.dart';
import '../models/naming.dart';

/// Called when the listening position moves, so it can be persisted.
typedef ProgressSink = void Function(
    String bookId, int chapterIndex, Duration position);

/// Backs playback for the whole app.
///
/// Lives inside an Android foreground service / iOS audio session via
/// `audio_service`, which is what keeps audio running — and the lock-screen
/// controls working — while the phone is locked and in a pocket.
class PlayerHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  PlayerHandler() {
    _player.playbackEventStream.listen(
      _broadcastState,
      onError: (Object e, StackTrace st) => _error.value = '$e',
    );

    // The queue index is the chapter index: audio and text stay paired by it.
    _player.currentIndexStream.listen((index) {
      if (index == null || index < 0 || index >= _chapters.length) return;
      if (currentChapter.value != index) currentChapter.value = index;
      mediaItem.add(queue.value.length > index ? queue.value[index] : null);
      _persist(force: true);
    });

    _player.positionStream.listen((_) => _persist());

    _player.playerStateStream.listen((state) {
      if (!state.playing) _persist(force: true);
      if (state.processingState == ProcessingState.completed) {
        _persist(force: true);
      }
    });
  }

  final AudioPlayer _player = AudioPlayer();

  /// Index of the chapter currently loaded — drives the text shown in the reader.
  final ValueNotifier<int> currentChapter = ValueNotifier<int>(0);

  /// Id of the book currently loaded, or null when nothing is loaded.
  final ValueNotifier<String?> currentBookId = ValueNotifier<String?>(null);

  final ValueNotifier<String?> _error = ValueNotifier<String?>(null);
  ValueNotifier<String?> get error => _error;

  ProgressSink? onProgress;

  List<Chapter> _chapters = const [];
  DateTime _lastPersist = DateTime.fromMillisecondsSinceEpoch(0);

  /// True while a book is being loaded or seeked into place. Position events in
  /// that window do not describe where the listener actually is yet, so saving
  /// one would overwrite the resume point we are in the middle of restoring.
  bool _restoring = false;

  AudioPlayer get player => _player;
  List<Chapter> get chapters => _chapters;

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  Stream<double> get speedStream => _player.speedStream;
  Duration get position => _player.position;
  bool get playing => _player.playing;
  double get speed => _player.speed;

  bool isLoaded(String bookId) => currentBookId.value == bookId;

  /// Duration of the loaded chapter, preferring the player's own measurement.
  Duration get chapterDuration {
    final reported = _player.duration;
    if (reported != null && reported > Duration.zero) return reported;
    final index = currentChapter.value;
    if (index >= 0 && index < _chapters.length) return _chapters[index].duration;
    return Duration.zero;
  }

  /// Loads [book] as a single queue of all its chapters, positioned at
  /// [chapterIndex]/[position]. Because the whole book is one queue, playback
  /// rolls from one chapter into the next without the app being on screen.
  Future<void> openBook(
    Book book, {
    int? chapterIndex,
    Duration? position,
    bool autoPlay = false,
  }) async {
    final targetIndex =
        (chapterIndex ?? book.safeChapterIndex).clamp(0, book.chapters.length - 1);
    final targetPosition = position ?? Duration.zero;

    if (currentBookId.value == book.id) {
      // Same book already queued — just move within it.
      _restoring = true;
      try {
        await _player.seek(targetPosition, index: targetIndex);
        currentChapter.value = targetIndex;
      } finally {
        _restoring = false;
      }
      if (autoPlay && !_player.playing) await _player.play();
      return;
    }

    _error.value = null;
    _restoring = true;
    _chapters = book.chapters;
    currentBookId.value = book.id;
    currentChapter.value = targetIndex;

    final items = [
      for (final chapter in book.chapters) _mediaItemFor(book, chapter),
    ];
    queue.add(items);
    mediaItem.add(items[targetIndex]);

    try {
      await _player.setAudioSource(
        ConcatenatingAudioSource(
          children: [
            for (final chapter in book.chapters)
              AudioSource.file(book.audioPathFor(chapter)),
          ],
        ),
        initialIndex: targetIndex,
        initialPosition: targetPosition,
      );
      _restoring = false;
      if (autoPlay) await _player.play();
    } catch (e) {
      _error.value = 'Could not start playback: $e';
    } finally {
      _restoring = false;
    }
  }

  MediaItem _mediaItemFor(Book book, Chapter chapter) => MediaItem(
        id: '${book.id}#${chapter.index}',
        title: fullChapterTitle(chapter),
        album: book.title,
        artist: book.title,
        duration: chapter.duration,
        extras: {
          'bookId': book.id,
          'chapterIndex': chapter.index,
          'audio': book.audioPathFor(chapter),
        },
      );

  /// Jumps to a chapter — this is what "select a text part and it reads it" does.
  Future<void> playChapter(int index, {bool autoPlay = true}) async {
    if (index < 0 || index >= _chapters.length) return;
    await _player.seek(Duration.zero, index: index);
    currentChapter.value = index;
    if (autoPlay && !_player.playing) await _player.play();
  }

  void _persist({bool force = false}) {
    final bookId = currentBookId.value;
    final sink = onProgress;
    if (bookId == null || sink == null || _restoring) return;
    final now = DateTime.now();
    if (!force && now.difference(_lastPersist) < const Duration(seconds: 5)) {
      return;
    }
    _lastPersist = now;
    sink(bookId, currentChapter.value, _player.position);
  }

  void _broadcastState(PlaybackEvent event) {
    final playing = _player.playing;
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        MediaControl.rewind,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.fastForward,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      // Rewind / play-pause / fast-forward on the compact notification.
      androidCompactActionIndices: const [1, 2, 3],
      processingState: switch (_player.processingState) {
        ProcessingState.idle => AudioProcessingState.idle,
        ProcessingState.loading => AudioProcessingState.loading,
        ProcessingState.buffering => AudioProcessingState.buffering,
        ProcessingState.ready => AudioProcessingState.ready,
        ProcessingState.completed => AudioProcessingState.completed,
      },
      playing: playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: event.currentIndex,
    ));
  }

  // --- AudioHandler overrides: these are what lock-screen / headset buttons hit.

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() async {
    await _player.pause();
    _persist(force: true);
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() => _player.seekToNext();

  @override
  Future<void> skipToPrevious() => _player.seekToPrevious();

  @override
  Future<void> skipToQueueItem(int index) => playChapter(index);

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  @override
  Future<void> stop() async {
    _persist(force: true);
    await _player.stop();
    await super.stop();
  }

  Future<void> disposePlayer() async {
    _persist(force: true);
    await _player.dispose();
  }
}
