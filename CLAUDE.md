# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`riya_play` — a Flutter client for the Riya Play video service (catalog, TV channels,
favorites, playback, and offline downloads). Flutter 3.44 / Dart 3.12, `sdk: ^3.7.2`.

**Android-only.** There is no `ios/` directory even though `flutter_native_splash.yaml`,
`flutter_launcher_icons.yaml`, and `pubspec.yaml` carry iOS keys and `screen_brightness_ios`.
Treat those as leftovers, not a supported target.

Code comments and all user-facing strings are in Uzbek. Keep both in Uzbek when editing.

## Commands

```bash
flutter pub get
flutter run                       # debug on the attached device
flutter analyze                   # the only static check; see lint notes below
flutter build apk --release
flutter build apk --debug
```

There is no `test/` directory and no test dependency in `pubspec.yaml`. Do not claim tests
pass; if a change needs verification, run the app or inspect via `adb`.

Regenerating launcher assets after changing the source images:

```bash
dart run flutter_native_splash:create
dart run flutter_launcher_icons
```

### Build prerequisites

Two gitignored files under `android/` must exist or the Gradle configure phase fails:

- `android/local.properties` — `build.gradle.kts` reads it unconditionally for `flutter.sdk`.
- `android/key.properties` — `keyAlias` / `keyPassword` / `storeFile` / `storePassword`.
  The `release` signing config casts these with `as String`, so a missing file throws even
  when only building debug.

Java and Kotlin both target 17 (`JavaLanguageVersion.of(17)`), `compileSdk = 36`,
`minSdk = 26`, `targetSdk = 34`. Gradle lint is deliberately non-fatal
(`abortOnError = false`, `checkReleaseBuilds = false`).

App version comes from `pubspec.yaml` (`versionCode = flutter.versionCode`,
`versionName = flutter.versionName`), so `version: 1.0.0+1` is the single place to bump.
Debug adds `-debug` to the name via `versionNameSuffix`.

### Debug builds are a separate app

`applicationIdSuffix = ".debug"` means debug installs as `uz.mrlg.riyaplay.debug`, side by
side with a release install so the release session survives. Any `adb` command targeting the
app must use the suffixed id:

```bash
adb shell run-as uz.mrlg.riyaplay.debug ls /data/data/uz.mrlg.riyaplay.debug/app_flutter/
```

Downloaded videos land in `/sdcard/Movies/RiyaPlay/`.

## Architecture

### Navigation and shell

`main.dart` holds the whole app shell. There are no named routes — the `routes` map was
removed deliberately. Startup order matters: `DownloadManager.instance.restore()` is awaited
*before* `runApp` so the downloads list is populated before any screen reads it.

Auth is a single gate: a `FutureBuilder` reads `auth_token` from `SharedPreferences` and
renders `AuthScreen` or `MainScreen`. `MainScreen` is a 5-tab `TabBarView`
(Bosh sahifa / TV / Katalog / Sevimlilar / Profil), each tab wrapped in `KeepAliveWrapper`
so tab state survives switching.

### Theme

`ThemeProvider` is a **palette, not a toggle** — `isDarkMode` and `isInitialized` are
hardcoded `true`. The light theme was removed after status-bar rendering glitches; don't
reintroduce a runtime theme switch. It is still registered as a `ChangeNotifier` via
`MultiProvider` and read with `Provider.of<ThemeProvider>(context)` throughout.

### API layer

Three tiers, in `lib/services/`:

1. `api/api_client.dart` — base URL (`https://finalapi.riyaplay.uz`), shared headers, and
   `sendRequest`. It identifies as `User-Agent: okhttp/4.9.2`; some CDN edges 403 Dart's
   default agent, so every request that touches media must send the same headers.
2. `api/{auth,user,films,favorites}_api.dart` — domain calls.
3. `api_service.dart` — a thin facade re-exporting all of the above. It exists so existing
   `ApiService.xxx(...)` call sites keep working; add new methods to the domain file and
   forward them here.

**`sendRequest` never throws.** Non-200 and network errors both come back as a map with
`success: false` plus `statusCode` or `error`. Callers must check the payload shape, not
`try/catch`. Responses are decoded with `utf8.decode(response.bodyBytes)` — required for
Uzbek/Russian titles.

TV channels bypass this stack entirely: `tv_api_service.dart` fans out to three unrelated
third-party providers (`SalomTV`, `SpecUZ`, `BizTV`), each with its own base URL.

### Downloads — the most intricate part

Split across two Dart files plus native Kotlin.

`services/download_manager.dart` — the queue. Singleton `ChangeNotifier`, persisted in
`SharedPreferences` under `download_tasks` (newest 100 kept). Notable behavior:

- A task that was mid-flight when the process died is restored as `failed`, not `running`:
  bytes stay on disk for "Davom ettirish" but nothing auto-starts on launch.
- `wifiOnly` (`download_wifi_only`) gates the queue; a `connectivity_plus` subscription
  pauses on an unusable connection and resumes when one returns.
- `_persist()` is called on status transitions only, never on progress ticks.
- `enqueue` de-duplicates; `enqueueAll` batch-queues a season and skips finished titles.
- A requested tier ("720p") is carried as a label and resolved when the episode's turn
  comes, because resolving every master playlist up front would be one request per episode.

`services/download_service.dart` — the transfer. Handles both direct files and HLS
`.m3u8`: parses master/media playlists, decrypts AES-128 segments with `pointycastle`
(keys are per-segment and may rotate), honors `#EXT-X-BYTERANGE` and `#EXT-X-MAP` (fMP4),
resumes via a `_ResumeState` keyed on the URL *without* its query string (stream tokens
expire, so keying on them would discard the partial file every attempt), checks free space
up front (`InsufficientStorageException`), then remuxes `.ts` → `.mp4` with
`FFmpegKit.execute('-c copy')` — container swap only, no codecs, which is why the `_min`
FFmpeg variant is used (LGPL, smallest APK impact).

Error classification is load-bearing: `HttpStatusException` is kept distinct from
connection failures so a 404 segment isn't retried every 15 seconds forever.

Downloaded episodes are named via `utils/episode_naming.dart`
(`Kalmar o'yini (1-fasl, 3-qism)`) — a bare `3-qism.mp4` used to overwrite across series.

### Native bridge

`MethodChannel('uz.mrlg.riyaplay/media_store')`, implemented in
`android/app/src/main/kotlin/uz/mrlg/riyaplay/MainActivity.kt`:
`saveToMovies`, `startDownloadService`, `updateDownloadService`, `stopDownloadService`,
`getFreeBytes`.

Dart downloads into app-private storage and hands the finished file to Kotlin, which copies
it through `MediaStore` into `Movies/RiyaPlay`. This indirection is required: under scoped
storage plain file I/O can't write `/sdcard/Movies`, and raw path writes to a *pending*
MediaStore entry fail too (FUSE rejects the `.pending-…` placeholder with `EEXIST`) — the
bytes must go through the resolver's `OutputStream`. On API ≤ 28 it falls back to a direct
copy plus `MediaScannerConnection`.

`ensureStoragePermission()` only requests `WRITE_EXTERNAL_STORAGE` on API ≤ 28. On API 33+
that permission no longer exists and requesting it always returns denied, which would block
downloads that are in fact allowed.

`DownloadService.kt` is a `dataSync` foreground service that owns the progress notification.

### Shared UI helpers

`utils/pagination_controller.dart` is the standard infinite-scroll driver: screens construct
a `PaginationController<T>` in `initState` with `fetchPage`/`idOf`, then
`..addListener(() => setState(() {}))..loadInitial()`. It owns the `ScrollController` and
de-duplicates across pages. Prefer it over hand-rolled paging.

`services/preferences_service.dart` (`StorageUtils`) prunes `playback_position_*` keys older
than 30 days.

## Lint

`analysis_options.yaml` includes `flutter_lints` but demotes a long list of rules to
`ignore` under `analyzer.errors` — including `deprecated_member_use`,
`use_build_context_synchronously`, `empty_catches`, and
`curly_braces_in_flow_control_structures`. Match the surrounding code rather than
"fixing" patterns the config has deliberately silenced.

Note the config contradicts itself on `avoid_print`: silenced under `analyzer.errors`, then
enabled under `linter.rules`. Logging goes through `utils/app_logger.dart` (`appLogger`),
not `print`.

`flutter analyze` currently reports 5 pre-existing `library_private_types_in_public_api`
infos (in `latestviewed_screen.dart`, `profile_screen.dart`, and two `profile/` screens) and
no errors or warnings. That is the clean baseline — compare against it rather than expecting
zero output.

## Vendored and forked dependencies

- `packages/flutter_iconly` — a local path package, vendored from pub `flutter_iconly-1.0.2`
  with the `IconlyXxxData` classes rewritten to plain `IconData` with `fontPackage`.
  Changes here won't come from `pub upgrade`.
- `better_player` — pinned to the `Lo4D/better-player-ultra` git fork, not pub.
- Firebase is commented out in `pubspec.yaml`; there is no Firebase integration.
