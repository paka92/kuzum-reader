# Kuzum Reader

Offline Android/iOS reader for zipped book packages: each part's **text and its
audio narration stay paired**, playback keeps running with the phone locked, and
your place is remembered.

Built with Flutter so the same code targets both platforms.

## Preparing a book

Books are generated with [text2audiobook-webapp](https://github.com/paka92/text2audiobook-webapp),
which turns text into the paired audio/text package this app reads. It needs a
Google TTS API key; the free tier covers roughly 4000 pages of text-to-speech.

**Supported languages:** Turkish, English.

## What a book package looks like

A `.zip` with one folder inside, holding a `manifest.json` plus one `.m4a` and
one `.txt` per part:

```
Batı Felsefesi Tarihi 01 (İlk Çağ Felsefesi).zip
└── Batı Felsefesi Tarihi 01 (İlk Çağ Felsefesi)/
    ├── manifest.json
    ├── playlist.m3u                    (ignored)
    ├── 001_00_onsoz_part_01.m4a
    ├── 001_00_onsoz_part_01.txt
    ├── 002_01_giris_part_01.m4a
    └── ...
```

`manifest.json` drives everything:

```json
{
  "book": "Batı Felsefesi Tarihi 01 (İlk Çağ Felsefesi)",
  "seconds": 39495.044,
  "chapters": [
    { "index": 1, "title": "001_00_onsoz_part_01",
      "audio": "001_00_onsoz_part_01.m4a",
      "text":  "001_00_onsoz_part_01.txt",
      "seconds": 230.03 }
  ]
}
```

Part names follow `NNN_GG_section_part_PP`, which the app uses to group the
174 parts of the sample book into 32 readable sections (`Önsöz`, `Giriş`,
`Bölüm 1` …). Names that don't follow the convention still work — they just
become standalone sections.

## How it behaves

**Imported once.** Pick a `.zip` and it is unpacked into the app's private
storage, with the archive's top-level folder flattened away. After that the zip
is never read again — opening the book reads the unpacked files directly. Import
runs on a background isolate, so the UI stays responsive while ~235 MB is
written, and a half-finished import cleans up after itself. Re-importing the
same book is detected by title and asks before unpacking again.

**Text matched to audio, part by part.** Sections expand into their parts; tap a
part and that part's text opens while its narration plays. Not word-level
syncing — the pairing is per part, which is what the package provides.

**Your place is kept.** Chapter index and offset within it are saved while you
listen (coalesced to one write every few seconds, plus on pause and on
backgrounding). The library shows percentage and time left; "Continue
listening" drops you back exactly where you stopped.

**Plays from a pocket.** The whole book is loaded as one queue, so parts roll
into the next one without the app on screen. An Android foreground service with
a MediaSession keeps audio alive with the screen locked and puts
rewind / play-pause / forward on the lock screen; headset and Bluetooth buttons
work too. 30-second jumps and 0.75×–2× speed, remembered between sessions.

## Layout

```
lib/
  main.dart                      app entry, audio service init, globals
  models/
    book.dart                    Book / Chapter / BookProgress, manifest parsing
    naming.dart                  part-name parsing, section grouping, titles
  services/
    importer.dart                one-time zip unpacking on a background isolate
    library_store.dart           library index + settings on disk
    library_controller.dart      in-memory library, progress coalescing
    player_handler.dart          just_audio + audio_service, lock-screen controls
  ui/
    library_page.dart            book list, import, delete
    book_page.dart               sections and parts
    reader_page.dart             text + transport controls
    mini_player.dart             now-playing strip
    format.dart                  duration / size formatting
```

The library index (`library.json`) stores only metadata and your position; each
book's unpacked `manifest.json` stays the single source of truth for its parts.

## Running it

```bash
flutter pub get
flutter test                       # unit tests, no device needed
flutter run                        # with a device connected
flutter build apk --release        # installable APK
```

Requires the Android SDK and JDK 17. If `flutter doctor` cannot find them,
point Flutter at your own install:

```bash
flutter config --android-sdk <path-to-android-sdk>
flutter config --jdk-dir <path-to-jdk-17>
```

### iOS

The iOS side is scaffolded and `UIBackgroundModes: audio` is set, so background
playback is in place. To actually build it you still need a complete Xcode
install plus CocoaPods:

```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
brew install cocoapods
flutter build ios
```

### Checking a new package

To confirm a `.zip` unpacks cleanly and every file the manifest promises is
present, before trusting it on a phone:

```bash
dart run tool/verify_real_zip.dart path/to/Book.zip /tmp/unpacked
```

## App identity and icon

The app is **Kuzum Reader** (`android:label`, iOS `CFBundleDisplayName`, and the
Flutter `MaterialApp` title). The Dart package is `kuzum_reader`.

Identifiers match the name too: Android `applicationId` and `namespace` are
`com.karakaya.kuzum_reader`, the iOS bundle id is `com.karakaya.kuzumReader`
(camelCase, since iOS bundle ids should avoid underscores), and books are stored
under a `kuzum_reader/` directory in app-private storage.

Changing any of these makes the app install as a separate copy that cannot see
an existing library, so treat them as fixed from here on.

Launcher icons are generated from `icon.png` in the repo root by
`tool/generate_icons.py` (see that file for how to run it). It produces legacy
and round icons, Android 8+ adaptive layers, and the full iOS icon set. The
adaptive foreground is scaled to the largest size whose rounded corners still
sit inside a circular launcher mask, on a background colour sampled from the
artwork's own border, so no mask shape clips the artwork or shows a seam.

## Android build notes

Three non-default settings exist for concrete reasons — don't "tidy" them away:

- **`android/build.gradle.kts` raises every plugin's `compileSdk` to 36.**
  `just_audio`, `audio_session` and `file_picker` still declare 34/35, while
  `flutter_plugin_android_lifecycle` requires its consumers to compile against
  36, so the AAR metadata check fails without this. It is registered *before*
  the `evaluationDependsOn(":app")` block, because that evaluates subprojects
  eagerly and `afterEvaluate` cannot be added afterwards.
- **`android/gradle.properties` asks for a 3 GB heap**, down from the template's
  `-Xmx8G` plus 4 GB metaspace, which caused swapping on a 16 GB machine.
  Heap-dump-on-OOM is off so a crash cannot drop a multi-GB `.hprof`.
- **The NDK is required even though this app has no native code.** AGP 9
  provisions it regardless (~5 GB), so `ndkVersion` stays pinned to
  `flutter.ndkVersion` for a deterministic toolchain. Suppressing the strip step
  via `packaging { jniLibs { keepDebugSymbols } }` does *not* avoid the
  download, and inflates the debug APK from 154 MB to 1.4 GB — don't.

A debug APK is ~175 MB — all ABIs, an unoptimised Dart kernel blob and the
Vulkan validation layer; a release build is far smaller. If Gradle reports a suspiciously fast build after changing packaging or
stripping options, run `flutter clean` — it caches native-library merges
aggressively and will happily hand back the previous APK.

## Notes and limits

- Books live in app-private storage, so "clear app data" or uninstalling removes
  them; your original `.zip` files are never modified or deleted.
- Packages carry no cover art, so the library draws a deterministic colored tile
  from the title instead.
- `playlist.m3u` in the package is ignored — `manifest.json` covers it.
- No sleep timer or bookmarks yet; both would fit naturally on the reader screen.
