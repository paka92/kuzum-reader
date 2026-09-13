import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import 'services/library_controller.dart';
import 'services/library_store.dart';
import 'services/player_handler.dart';
import 'ui/library_page.dart';

/// Playback handler, live for the whole process lifetime (including while the
/// UI is gone and only the foreground service is running).
late final PlayerHandler player;
late final LibraryController library;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  player = await AudioService.init(
    builder: () => PlayerHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.karakaya.kuzumreader.playback',
      androidNotificationChannelName: 'Kuzum Reader playback',
      androidNotificationChannelDescription:
          'Controls for the book you are listening to',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
      // Audiobook-sized jumps rather than music-sized ones.
      fastForwardInterval: Duration(seconds: 30),
      rewindInterval: Duration(seconds: 30),
    ),
  );

  library = LibraryController(LibraryStore());
  player.onProgress = library.updateProgress;
  await library.init();
  // Restore the listener's preferred speed before anything plays.
  if (library.speed != 1.0) await player.setSpeed(library.speed);

  runApp(const BookReaderApp());
}

class BookReaderApp extends StatefulWidget {
  const BookReaderApp({super.key});

  @override
  State<BookReaderApp> createState() => _BookReaderAppState();
}

class _BookReaderAppState extends State<BookReaderApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Make sure the resume point survives the app being swiped away.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      library.flushProgress();
    }
  }

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF6D5BD0);
    return MaterialApp(
      title: 'Kuzum Reader',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const LibraryPage(),
    );
  }
}
