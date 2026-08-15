# RiyaPlay — Debugging & Development Status

Checkpoint written at the end of a long debugging/feature session. Everything
below was verified against the actual files in the working tree, not from
conversation memory.

---

## Project Overview

`riya_play` is a Flutter client for the Riya Play video service: catalog, TV
channels, favourites, playback and offline downloads.

- **Flutter/Dart**: `sdk: ^3.7.2` (Dart 3.7 line). `flutter analyze` is the
  only static check configured; there is **no `test/` directory and no test
  dependency** in `pubspec.yaml`.
- **Platform**: Android only. There is no `ios/` directory even though
  `pubspec.yaml`, `flutter_native_splash.yaml` and
  `flutter_launcher_icons.yaml` still carry iOS keys.
- **Android config**: `compileSdk = 36`, `minSdk = 26`, `targetSdk = 34`,
  Java/Kotlin 17. Debug builds install as a **separate package**
  (`applicationIdSuffix = ".debug"` → `uz.mrlg.riyaplay.debug`) so a debug
  build can sit next to a release install without touching its session.
- **Language**: all user-facing strings and code comments are in Uzbek. Keep
  it that way when editing.

### Architecture notes

- `main.dart` holds the whole app shell; there are no named routes. Startup
  awaits `DownloadManager.instance.restore()` **before** `runApp` so the
  download list exists before any screen reads it.
- Auth is a single gate: a `FutureBuilder` reads `auth_token` from
  `SharedPreferences` and renders `AuthScreen` or `MainScreen` (5 tabs).
- `ThemeProvider` is a **palette, not a toggle** — `isDarkMode` is hardcoded
  `true`. Do not reintroduce a runtime light/dark switch.
- API layer is three tiers in `lib/services/`: `api/api_client.dart` (base URL
  `https://finalapi.riyaplay.uz`, shared headers, `sendRequest` that **never
  throws** — it returns `success: false` maps), `api/{auth,user,films,
  favorites}_api.dart`, and `api_service.dart` as a thin re-exporting facade.
- TV channels bypass that stack entirely via `tv_api_service.dart`
  (SalomTV / SpecUZ / BizTV).
- Downloads are the most intricate part: `services/download_manager.dart`
  (queue, persistence, network gating) + `services/download_service.dart`
  (HLS parsing, transfer, resume, remux) + Kotlin
  `MainActivity.kt` / `DownloadService.kt` over
  `MethodChannel('uz.mrlg.riyaplay/media_store')`.

---

## Current Debugging Status

The session covered four areas, in order:

1. **Download subsystem** — rewritten from a screen-owned transfer into a
   persistent queue with resume, disk pre-checks, correct HLS parsing,
   Wi-Fi-only gating, batch/season/multi-select downloads. Extensively tested
   on a physical device.
2. **Film screen UI** — poster now renders behind the status bar.
3. **Ported features from the `tplaytv` (Android TV) sibling project** —
   server-side watch progress, actors, centralized error handling, home
   caching, OTA updates.
4. **"Ko'rishni davom ettirish" (continue watching) bugs** — wrong film id,
   wrong progress denominator, wrong sort order; plus the cards now start
   playback directly instead of opening the film page.

### Session of 2026-08-15 — OTA updates from GitHub Releases

The app ships outside Google Play, so it has to update itself. An
`update_service.dart` already existed (ported from the TV build) but pointed
at a repository that does not exist (`riyaplay-releases`), was startup-only,
and reported nothing when a check failed. It was rewritten against the real
repository, **`d4rk73rr0r/rplay-releases`**.

**Investigation notes (facts, not assumptions):**

- **The release repository is currently empty.** `releases.atom` has no
  entries and the releases page renders "There aren't any releases here", so
  `GET /repos/d4rk73rr0r/rplay-releases/releases/latest` answers **404**. The
  asset naming convention therefore *could not be inspected* and the picker
  had to be written defensively (see below).
- **Version source**: `pubspec.yaml` `version: 1.0.1+2` →
  `flutter.versionName` / `flutter.versionCode` in
  `android/app/build.gradle.kts`. Debug builds add `versionNameSuffix =
  "-debug"`, so `PackageInfo.version` can read `1.0.1-debug` — the parser has
  to tolerate that. The release install on the test device reports
  `versionName=1.0.1, versionCode=2002`, i.e. release APKs are built with a
  custom build number.
- **Permissions**: the `ota_update` plugin already declares
  `REQUEST_INSTALL_PACKAGES` and ships its own `FileProvider`
  (`<applicationId>.ota_update_provider`), so no provider wiring is needed in
  the app. The permission is now also declared explicitly in the app manifest
  so the flow is visible to anyone reading it.
- **Networking**: `ApiClient` is bound to the Riya Play API (auth headers,
  its own base URL), so the GitHub call stays on plain `package:http`, with a
  `User-Agent` (GitHub rejects requests without one) and the
  `application/vnd.github+json` Accept header.
- **Settings UI**: there is no separate settings screen — `ProfileScreen` is
  the settings list, built from `_buildListTile`. The manual check was added
  there.

### Session of 2026-08-13, part 4 — "00:00 on first playback" and the crash

Reported: a film watched for the first time (Catalog → FilmScreen → play →
Android Back **without pausing**) shows up in "Ko'rishni davom ettirish" with
`00:00` and restarts from zero, while the *second* session of the same film
saves its position correctly. Separately, the app sometimes dies mid-playback.

Two independent root causes were found; both are described in Bugs 17 and 18
below. Neither is a UI-rendering problem, and the app never sends `0` — the
`00:00` row is a latest-viewed entry that has **no** `second` record at all
(verified with the API: `second.time` is absent, not zero, for the affected
films).

### Session of 2026-08-13, part 3 — comparison with `tplaytv` and ports

The sibling Android-TV project `D:\Android\Projects\tplaytv` was compared
screen by screen for the watch-position feature. The **API layer is identical**
in both: same write endpoint (`POST /v2/films/second/{episodeId}`, body
`{"second": n}`, answer either a bare `true` or a map), same episode read
(`/v1/series/{id}?include=track,ads,files,screenshots.file,second`), and the
same latest-viewed query (same `include`, `sort=-updated_at`, `_t` cache
buster). Episode ids are derived the same way.

The differences, and what happened to each:

| Area | tplaytv | riya_play | Action |
| --- | --- | --- | --- |
| Write on pause | no | yes | — |
| Periodic write during playback | no | yes, 30 s | — (riya_play is ahead; a backport to `tplaytv` is worth doing) |
| Write on exit | yes | yes (fixed in part 2) | — |
| Write on `finished` | yes, writes the full duration then pops | was missing | **PORTED** |
| Refresh after the player closes | `RouteObserver` + `RouteAware.didPopNext` with a 500 ms delay | per-call-site callbacks only | **PORTED**, without the arbitrary delay — it waits for the actual write |
| Episode id when only the film id is known | `getEpisodeIdByFilmId` (marked `@Deprecated` there) | none | **PORTED** as `getFirstEpisode`, narrowed to single-episode films and documented as such |
| One shared play/resume/chooser path | `VideoLauncher.playVideo` used by every screen | two near-identical `_playVideo` copies | **PORTED** — `VideoLauncher.playWithChooser` |
| Progress-bar denominator | `film.playback_time * 60` — the field is absent, so every bar reads full | item `duration` (fixed earlier as Bug 9) | **NOT ported** — `tplaytv` still has this bug |
| `network_service.dart`, `performance_monitor.dart`, `registerQr`/`qr_screen` | present | absent | **NOT ported** — dead code there, or the TV half of the pairing flow |

### Session of 2026-08-13, part 2 — watch-position writes

A user report ("there is a serious bug in `VideoPlayerScreen`") turned out to
be four related defects, all confirmed on device and all now fixed: the exit
write was dead code (Bug 13), nothing wrote during playback (Bug 14), the
continue-watching lists never refreshed after the player closed (Bug 15), and
the new refresh could outrun the exit write (Bug 16).

Server truth was checked directly against
`/v2/films/latest-viewed?include=film,second&sort=-updated_at` with the
device's own token, not just through the UI.

### Session of 2026-08-13 (continuation)

Started from the previous checkpoint's "Next Recommended Step" and closed it,
plus the three follow-ups it named:

- Segment concurrency constants made coherent (Bug 0) and re-verified with a
  full 448 MB download on the device — no restart, 9.11 MB/s effective.
- `_DownloadProfile.report()` gated behind `kDebugMode`.
- `latestviewed_screen` tap → resume dialog → playback verified on device.
- 5-qism duration discrepancy closed: a clean re-download is exactly 47:01 and
  decodes without errors.

No behaviour outside `lib/services/download_service.dart` was changed.

`flutter analyze lib` reports **5 issues, all pre-existing
`library_private_types_in_public_api` infos** in
`latestviewed_screen.dart`, `profile_screen.dart` and two `profile/` screens.
That is the clean baseline — compare against it, do not expect zero output.

Debug APK builds and installs successfully. Device used for testing:
**Samsung Galaxy A55 (SM-A556E), Android 16 / API 36**, package
`uz.mrlg.riyaplay.debug`.

---

## Bugs Found

### 0. Segment concurrency constants contradicted each other

- **Symptoms**: only the first batch of an HLS download opened 48 connections;
  every later batch was silently clamped to 16.
- **Root cause**: `_initialSegmentConcurrency = 48` was larger than
  `_maxSegmentConcurrency = 16`, and `_adaptConcurrency` clamps to
  `[_minSegmentConcurrency, _maxSegmentConcurrency]`. The 48-wide first batch
  was also the configuration that coincided with an app restart during earlier
  testing.
- **Affected files**: `lib/services/download_service.dart:316-324`.
- **Status**: **FIXED** — `_maxSegmentConcurrency = 24` and
  `_initialSegmentConcurrency = _maxSegmentConcurrency`, so the value cannot
  drift apart again.
- **Verified on device** (SM-A556E, mobile data, 2026-08-13): a clean 720p
  download of "Kalmar o'yini (1-fasl, 5-qism)" moved 448.0 MB in 49.2 s —
  9.44 MB/s network, 9.11 MB/s effective — with no restart and no failed
  segment.

### 1. Leaving the download screen cancelled the download

- **Symptoms**: navigating away from `DownloadScreen` aborted an in-progress
  download and deleted the partial file.
- **Root cause**: the whole transfer lived in `_DownloadScreenState`;
  `dispose()` set `_cancelled = true`, and `download_service.dart` deleted the
  temp file on any exception.
- **Affected files**: `lib/screens/download_screen.dart`,
  `lib/services/download_service.dart`.
- **Confirmed by**: reading the code, then reproducing on device (backed out
  at 13% and the download died).
- **Status**: **FIXED** — work moved to `DownloadManager` singleton.
- **Notes**: verified on device — backing out at 13% now continues to 100%.

### 2. HTTP status errors were classified as network errors

- **Symptoms**: at 99% a download showed "Internet aloqasi uzildi" and retried
  forever without ever succeeding.
- **Root cause**: `_fetchWithRetry` threw `http.ClientException` for any
  status ≥ 400, and `DownloadManager._isNetworkError` treated **every**
  `ClientException` as a connectivity failure → the queue entered
  "waiting for network" and a 15-second timer retried a permanent 404 forever.
- **Affected files**: `lib/services/download_service.dart`,
  `lib/services/download_manager.dart`.
- **Confirmed by**: device logcat —
  `⛔ Yuklab olishda xato: ClientException: HTTP 404 ... /segment244.ts`
  followed by endless `Navbat qayta urinilmoqda (taymer)`.
- **Status**: **FIXED** — dedicated `HttpStatusException` with an
  `isTransient` flag; 4xx fails fast with an accurate message.

### 3. Source playlist advertises a segment the CDN does not serve

- **Symptoms**: "Kalmar o'yini (1-fasl, 3-qism)" could never finish; the last
  of 244 segments returned 404 on every attempt.
- **Root cause**: **server-side content defect**, not an app bug. The media
  playlist lists `segment244.ts` but the CDN returns 404 for it. Reproduced on
  a completely fresh download, so neither resume nor the parser is involved
  (other episodes with 128/229 segments complete normally).
- **Affected files**: none (external), mitigated in
  `lib/services/download_service.dart`.
- **Status**: **FIXED (mitigated)** — a 4xx on the **last 1–2** segments is
  skipped, the download completes, and the user is told in the UI.
- **Notes**: the skipped tail segment turned out to be near-zero length — the
  finished file's duration matched the catalogue exactly (49:22).

### 4. HLS parser kept only the last `#EXT-X-KEY`

- **Symptoms**: none observed on this provider's content (single-key,
  MPEG-TS), but any stream that rotates AES keys mid-stream would decrypt to
  garbage.
- **Root cause**: the old single-pass scan overwrote `encryptionKey` for every
  `#EXT-X-KEY` line it saw and used the final value for all segments.
- **Affected files**: `lib/services/download_service.dart`.
- **Confirmed by**: code reading only.
- **Status**: **FIXED**, but **NEEDS VERIFICATION** — this provider does not
  serve rotating keys, so the fixed path was never exercised at runtime.

### 5. `#EXT-X-MAP` and `#EXT-X-BYTERANGE` were ignored

- **Symptoms**: fMP4 (CMAF) streams would download without their
  initialisation segment and be unplayable; byte-range playlists would fetch
  the same bytes repeatedly.
- **Root cause**: the parser collected only non-`#` lines as segment URLs.
- **Affected files**: `lib/services/download_service.dart`.
- **Status**: **FIXED**, but **NEEDS VERIFICATION** — provider serves only
  MPEG-TS, so neither path was exercised.

### 6. Film poster was cut off at the status bar

- **Symptoms**: on `FilmScreen` a solid black band covered the status bar area
  instead of the poster.
- **Root cause**: `extendBodyBehindAppBar: true` was already set, but the
  Android theme applied after Flutter starts (`NormalTheme`) did not set
  `windowDrawsSystemBarBackgrounds`, so the system owned and painted the
  status bar region.
- **Affected files**: the four `android/app/src/main/res/values*/styles.xml`,
  `lib/screens/film_screen.dart`.
- **Confirmed by**: on-device screenshots before/after; a temporary solid-red
  scrim proved the Flutter side rendered correctly once the theme allowed it.
- **Status**: **FIXED**.
- **Notes**: side effect — the status bar is now transparent **app-wide**.
  Home, downloads and episode-grid screens were checked and look correct.

### 7. `AppBar.flexibleSpace` gradient never rendered

- **Symptoms**: the darkening scrim meant to protect status-bar icons on
  `FilmScreen` was absent — visible in screenshots from **before** any change
  in this session.
- **Root cause**: **UNKNOWN**. Not diagnosed. The gradient was moved into the
  poster's own `Stack`, where it renders correctly.
- **Affected files**: `lib/screens/film_screen.dart`.
- **Status**: **FIXED (worked around)** — root cause not established.

### 8. Continue-watching cards opened the wrong film

- **Symptoms**: tapping a card in `latestviewed_screen.dart` opened an
  unrelated/non-existent film.
- **Root cause**: the code read the film id from `item['second']['film_id']`.
  That field is **not a film id** — its sibling `model` is
  `common\models\Series` and its value equals the item's own `id`, i.e. it is
  the **episode** id. The real film id is the item's top-level `film_id`
  (identical to `film.id`).
- **Affected files**: `lib/screens/latestviewed_screen.dart`.
- **Confirmed by**: fetching `/v2/films/latest-viewed` directly with `curl`
  using the device's auth token and inspecting the JSON.
- **Status**: **FIXED** — verified on device: tapping "Farishtalar shahri
  (1998, Melodrama)" now opens that exact film.

### 9. Continue-watching progress bar was always full

- **Symptoms**: every card showed a 100% progress bar regardless of position.
- **Root cause**: progress was `viewedTime / (film['playback_time'] * 60)`,
  but `playback_time` **does not exist** in the response (it appears once in a
  446 KB payload, inside an unrelated object). The `?? 1` fallback made the
  denominator 60 seconds. The correct denominator is the item's own
  `duration`, in seconds. `latestviewed_screen.dart` additionally never
  clamped the result.
- **Affected files**: `lib/screens/index_screen.dart`,
  `lib/screens/latestviewed_screen.dart`.
- **Confirmed by**: raw API inspection (`"duration":3022` vs
  `"second":{"time":1221}`) plus before/after device screenshots.
- **Status**: **FIXED**.

### 10. Continue-watching list was sorted by creation, not recency

- **Symptoms**: re-watching an old title did not move it to the front.
- **Root cause**: the query used `sort=-id`. The TV app uses
  `sort=-updated_at`.
- **Affected files**: `lib/services/api/films_api.dart`.
- **Status**: **FIXED**.

### 11. `VideoPlayerScreen.startAt` was accepted and silently discarded

- **Symptoms**: callers passed `startAt:` and it had no effect; resume worked
  only because the player independently read a local position.
- **Root cause**: the constructor declared `Duration? startAt` as a plain
  parameter with no matching field.
- **Affected files**: `lib/screens/video_player_screen.dart`.
- **Status**: **FIXED** — now a real field, and the only resume mechanism.

### 12. Watch position was local-only

- **Symptoms**: position did not follow the account across devices and was
  lost on reinstall.
- **Root cause**: positions were stored in `SharedPreferences` under
  `playback_position_<base64(url)>`; the backend endpoints existed but were
  unused by this app.
- **Affected files**: `lib/screens/video_player_screen.dart`,
  `lib/screens/film_screen.dart`, `lib/screens/films_full_screen.dart`,
  `lib/services/api/films_api.dart`.
- **Status**: **FIXED** — server is now the single source of truth; all local
  read/write of playback positions was removed.

---

### 13. Leaving the player with the back button never saved the position

- **Symptoms**: watching for any length of time and then pressing back lost
  everything since the last manual pause. The server kept the older value, so
  "Ko'rishni davom ettirish" resumed from the wrong place.
- **Root cause**: `dispose()` set `_isDisposed = true` **before** calling
  `_savePlaybackPosition()`, and that method's first guard was
  `if (!mounted || … || _isDisposed) return;`. The write therefore always
  bailed out on the exit path. A second defect sat behind it: the save is
  async while `dispose()` is synchronous, and `safeDispose` immediately paused
  and disposed the controller, so even with the guard fixed the position read
  could lose the race.
- **Affected files**: `lib/screens/video_player_screen.dart`.
- **Confirmed by**: device log on exit —
  `Playback position saqlanmadi: controller yoki state mavjud emas` — plus a
  direct `/v2/films/latest-viewed` query showing `second.time` frozen at the
  pause-time value (2734) after 30 more seconds of playback.
- **Status**: **FIXED** — the exit write no longer checks `mounted` /
  `_isDisposed` (it is deliberately independent of the widget), and the
  position is captured from the controller **before** teardown, falling back
  to the last value seen in a `progress` event.
- **Verified on device**: back after pause → 51 s on the server; back **without**
  pause → 78 s, written at the moment of the back press.

### 14. Position was only ever written on pause

- **Symptoms**: watching an hour without touching the controls and then losing
  the app (kill, crash, battery) discarded the whole session.
- **Root cause**: the only two write sites were the `pause` event and the
  (broken) `dispose` path. Nothing wrote while playback was simply running.
- **Affected files**: `lib/screens/video_player_screen.dart`.
- **Status**: **FIXED** — `BetterPlayerEventType.progress` now feeds
  `_lastKnownPosition` and a 30-second throttle (`_syncInterval`) pushes the
  position to the server during playback. Repeated identical seconds are
  skipped, so a paused player does not re-post the same value.
- **Verified on device**: writes at 28 s, 51 s, 1212 s, 1243 s, 1273 s … at a
  steady 30-second spacing.

### 15. Continue-watching lists were not refreshed after the player closed

- **Symptoms**: after watching, both the home row and `LatestViewedScreen`
  still showed the old time and the old order until a manual pull-to-refresh
  or an app restart. This made the position look unsaved even when it was.
- **Root cause**: `index_screen` fetches latest-viewed once (plus its
  5-minute `CacheService` entry) and `latestviewed_screen` only refetches from
  its `RefreshIndicator`; neither reacted to the player being popped.
- **Affected files**: `lib/screens/index_screen.dart`,
  `lib/screens/latestviewed_screen.dart`.
- **Status**: **FIXED** — `IndexScreenProvider.reloadLatestViewed()` refetches
  and rewrites the cache, and both card widgets await the player before
  triggering it (`LatestViewedCard.onReturn`).

### 16. The refresh could outrun the exit write

- **Symptoms**: after the fix for 15, the list occasionally showed the value
  from the last 30-second sync instead of the exit value (46:02 instead of
  46:09).
- **Root cause**: `Navigator.push`'s future completes when the route is
  **popped**, but the player's `dispose()` — and therefore the exit write —
  runs only after the exit animation, so the refresh was issued first.
- **Affected files**: `lib/screens/video_player_screen.dart`,
  `lib/utils/video_launcher.dart`.
- **Status**: **FIXED** — `VideoPlayerScreen.pendingPositionFlush` exposes the
  in-flight write and `VideoLauncher._awaitPositionFlush()` waits for it to
  appear (up to 800 ms) and then completes before the caller reloads.
- **Verified on device**: the home card now shows 47:08 immediately after a
  back press that wrote 2828 s.

### 17. Every playback session leaked ~155 MB of Java heap (the crash)

- **Symptoms**: the app dies while a video is playing, more often the longer
  the session goes on. Device crash records show
  `java.lang.OutOfMemoryError: Failed to allocate … target footprint
  536870912, growth limit 536870912` and, as a second face of the same
  failure, `[FATAL:flutter/shell/platform/android/platform_view_android_jni_impl.cc(1485)]
  Check failed: fml::jni::CheckException(env).`
- **Root cause**: the player is created with `autoDispose: false`
  ("safeDispose orqali boshqaramiz"), and `safeDispose` called
  `controller.dispose()` **without** `forceDispose`. In `better_player`:

  ```dart
  Future<void> dispose({bool forceDispose = false}) async {
    if (!betterPlayerConfiguration.autoDispose && !forceDispose) {
      return;
    }
  ```

  so the call was a no-op and the underlying ExoPlayer was never released.
- **Affected files**: `lib/utils/video_helpers.dart`,
  `lib/screens/video_player_screen.dart:342` (the `autoDispose: false` that
  makes the flag necessary).
- **Confirmed by**: measuring `dumpsys meminfo` across three play → back
  cycles, **before** the fix: 14 MB → 169 MB → 330 MB → 481 MB of Java heap
  (`largeHeap="true"` gives 512 MB, so the fourth session dies).
- **Status**: **FIXED** — `controller.dispose(forceDispose: true)`.
- **Verified**: four cycles after the fix: 179 MB → 174 MB → 17 MB (after a
  GC) → 135 MB. Bounded, no monotonic growth.

### 18. A first session could end without any position write ("00:00")

- **Symptoms**: as reported above — first session of a new film shows `00:00`,
  the second session saves correctly.
- **Root cause**: two things combined.
  1. `_maybeSyncPosition` stamped `_lastSyncAt` **before** knowing whether the
     write would actually happen. The very first `progress` event arrives at a
     position of ~0-1 s, which `_savePlaybackPosition` drops (`<= 5 s`), but
     the timestamp was already taken — so the next possible write was 30 s
     later. A new film therefore had a 30-second window in which **nothing**
     was ever sent.
  2. Inside that window the process could die (Bug 17) or the user could leave
     while the exit write itself was skipped, leaving the server row with no
     `second` record. The UI renders a missing record as `00:00` and resumes
     from zero — which is exactly what was reported as "the server saves
     00:00".
- **Why the second session always worked**: playback starts at
  `startAt = resumeSeconds`, so the *first* `progress` event is already past
  the 5-second threshold and `_lastSyncAt` is still null — the position is
  written within about a second of pressing play, long before Back is pressed.
  The asymmetry was never in the Back handler.
- **A third, latent trap in the same area**: `dispose()` resolved the position
  as `videoPlayerController?.value.position ?? _lastKnownPosition`.
  `value.position` is a **non-nullable** `Duration`, so the `??` could never
  fall back; had the controller already been reset to zero, the good value
  collected from `progress` events would have been ignored.
- **Affected files**: `lib/screens/video_player_screen.dart`.
- **Status**: **FIXED** — the throttle is only consumed when the position is
  actually worth saving, and `dispose()` now takes the **larger** of
  `value.position` and `_lastKnownPosition`.
- **Verified on device**: a brand-new film (Catalog → FilmScreen → play →
  Back at ~20 s, never paused) wrote `10s` during playback and `23s` on exit;
  the server returned `second.time=23`.

---

## Fixes Implemented

### Download subsystem

| File | Change | Why | Tested |
| --- | --- | --- | --- |
| `lib/services/download_manager.dart` (**new**) | Process-wide singleton queue: sequential execution, cancel/retry/remove, `SharedPreferences` persistence (`download_tasks`, newest 100), `QueuePause` (network / wifi), connectivity listener + 15 s retry timer, `enqueueAll`, `wifiOnly`, `pauseRequested` | Downloads must survive navigation and app restarts; a queue is needed for seasons | Yes — device |
| `lib/services/download_service.dart` | `HttpStatusException`; ordered HLS parser (per-segment keys, `#EXT-X-MAP`, `#EXT-X-BYTERANGE`); resume via `.part` + `_ResumeState`; disk pre-check via native `getFreeBytes`; adaptive segment concurrency; tail-segment 404 tolerance; `preferredQualityLabel` + `_pickVariant`; `okhttp/4.9.2` User-Agent on all requests; `_DownloadProfile` timing instrumentation | Correctness, resumability, and diagnosing throughput | Yes — device |
| `lib/screens/download_screen.dart` | Rewritten: quality picker + live queue view; `DownloadScreen.queue()` named constructor; Wi-Fi-only switch; per-task actions | Screen no longer owns the transfer | Yes — device |
| `lib/screens/films_full_screen.dart` | Season/whole-series batch download; long-press multi-select with checkmarks, AppBar count and `PopScope`; `_collectEpisodes` walks all pages | Downloading a series was ~3 taps per episode | Yes — device |
| `lib/screens/profile_screen.dart` | "Yuklab olishlar" entry opening `DownloadScreen.queue()` | The queue was otherwise unreachable after navigation reset | Yes — device |
| `android/.../MainActivity.kt` | `getFreeBytes` (StatFs `availableBytes`); `.m4s` → `video/mp4` in `mimeTypeFor` | Pre-flight disk check; correct MIME for un-remuxed fMP4 | Yes — builds + used |
| `android/app/build.gradle.kts` | `applicationIdSuffix = ".debug"`, `versionNameSuffix = "-debug"`; `isCoreLibraryDesugaringEnabled` + `desugar_jdk_libs:2.1.4` | Side-by-side debug install; `ota_update` requires desugaring | Yes |

### UI / status bar

| File | Change | Why | Tested |
| --- | --- | --- | --- |
| `android/app/src/main/res/values{,-night,-v31,-night-v31}/styles.xml` | `NormalTheme`: `windowDrawsSystemBarBackgrounds=true`, transparent `statusBarColor`, `windowLayoutInDisplayCutoutMode=shortEdges` | Let the app draw behind the status bar | Yes — device |
| `lib/screens/film_screen.dart` | Removed dead `AppBar.flexibleSpace` gradient; added a top scrim inside the poster `Stack` (`padding.top + kToolbarHeight`, black 0.65→0.25→transparent) | Keep status-bar icons and the back arrow readable over bright posters | Yes — device |

### Ported from `tplaytv`

| File | Change | Why | Tested |
| --- | --- | --- | --- |
| `lib/services/api/films_api.dart` + `lib/services/api_service.dart` | Added `getEpisodeDetails`, `getWatchedSeconds`, `updateWatchProgress`, `getActorFilms`; changed latest-viewed `sort` to `-updated_at` | Server-side resume, actors, correct recency order | Partially — resume yes, actors yes |
| `lib/screens/video_player_screen.dart` | Server-only position: writes via `updateWatchProgress`, seeks to `widget.startAt`; all `SharedPreferences`/`playback_position_*` code removed | Cross-device resume, single source of truth | Yes — device (`Pozitsiya tiklandi: 1221 sekund`) |
| `lib/screens/actor_films_screen.dart` (**new**) | Paginated grid of an actor's films | `actors.files` was already fetched and discarded | Yes — device (endpoint returns data) |
| `lib/screens/film_screen.dart` | Cast strip (director + actors), taps open `ActorFilmsScreen`; `_CastTile` widget | New feature, no extra request | Yes — device |
| `lib/services/error_handler.dart` (**new**) | `ApiErrorHandler` / `ErrorInfo` / `ErrorType`; maps exceptions to Uzbek user messages; wired into `actor_films_screen`, `films_full_screen`, `categories_screen` | Stop each screen printing raw `$e` | Compiles; not exercised per-branch |
| `lib/services/cache_service.dart` (**new**) | 5-minute JSON cache for banners / recommended / genres / latest-viewed | Cold start showed empty sections | Compiles; cache path not explicitly verified on device |
| `lib/screens/index_screen.dart` | `_primeFromCache()` before network; cache writes on success | Faster first paint | Partially |
| `lib/services/update_service.dart` (**new**) + `pubspec.yaml` | GitHub-Releases OTA with ABI-specific APK selection; called from `MainScreen.initState` | App is distributed outside Play | Only the failure path (no network → logged and ignored) |

### Continue watching

| File | Change | Why | Tested |
| --- | --- | --- | --- |
| `lib/utils/latest_viewed.dart` (**new**) | `latestViewedFilmId`, `latestViewedEpisodeId`, `latestViewedSeconds`, `latestViewedDuration`, `latestViewedProgress`, `formatWatchedTime` | The same misreading of the payload existed in two screens | Yes — device |
| `lib/utils/video_launcher.dart` (**new**) | `VideoLauncher.playFromLatestViewed` — fetches episode details, asks "Davom ettirish / Boshidan", pushes the player | Cards should resume, not open a film page | Yes — index card verified end to end |
| `lib/screens/index_screen.dart` | Card `onTap` → `VideoLauncher`; `onLongPress` → `FilmScreen`; progress bar colour yellow → `themeProvider.accentColor` | Requested behaviour + colour parity | Yes — device |
| `lib/screens/latestviewed_screen.dart` | Same tap/long-press split; correct film id and progress | Bug 8 / 9 | Yes — device |

### Watch-position writes (2026-08-13)

| File | Change | Why | Tested |
| --- | --- | --- | --- |
| `lib/screens/video_player_screen.dart` | Exit write no longer gated on `mounted`/`_isDisposed`; position captured before teardown with a `progress`-fed `_lastKnownPosition` fallback; 30 s periodic sync (`_syncInterval`) with a duplicate-seconds guard; `static pendingPositionFlush` exposing the in-flight exit write | Bugs 13, 14, 16 | Yes — device, both exit paths |
| `lib/utils/video_launcher.dart` | `_awaitPositionFlush()` after `Navigator.push` — waits up to 800 ms for the exit write to start, then for it to finish | Bug 16 | Yes — device |
| `lib/screens/index_screen.dart` | `IndexScreenProvider.latestViewedFields` (shared constant) and `reloadLatestViewed()`; the card awaits the player, then reloads | Bug 15 | Yes — device |
| `lib/screens/latestviewed_screen.dart` | `LatestViewedCard.onReturn` wired to the screen's `_refresh` (superseded in part 3 by `RouteAware`) | Bug 15 | Yes — device |

### OTA updates (2026-08-15)

| File | Change | Why | Tested |
| --- | --- | --- | --- |
| `lib/services/update_service.dart` | Rewritten: correct repository, `fetchLatest()` returning a sealed `UpdateCheckOutcome` (`UpdateAvailable` / `UpdateUpToDate` / `UpdateCheckFailed`), `AppVersion` comparison, defensive APK picker, themed dialog with release notes and download progress, per-status Uzbek error messages, `checkOnStartup()` and `checkManually()` | The old version queried a non-existent repo, was silent on every failure and had no manual entry point | Yes — device, see the table below |
| `lib/screens/profile_screen.dart` | "Yangilanishni tekshirish" tile calling `UpdateService.checkManually(context)` | Requirement: Profile → check for updates | Yes — device |
| `lib/main.dart` | `MainScreen.initState` now calls `checkOnStartup` (renamed from `checkUpdate`) | The name now says which of the two entry points it is | Yes — device |
| `android/app/src/main/AndroidManifest.xml` | Explicit `REQUEST_INSTALL_PACKAGES` | Already merged in from the plugin; declaring it makes the install flow visible in the manifest | Yes — builds and installs |

**How a release is detected.** `GET
https://api.github.com/repos/d4rk73rr0r/rplay-releases/releases/latest`.
That endpoint already excludes drafts and pre-releases, so an unfinished
release cannot reach users. `tag_name` carries the version and `body` the
release notes, of which the dialog shows the first ~160 px, scrollable.

**Version comparison.** `AppVersion.parse` pulls the first
`digits(.digits)*` run out of the string plus an optional `+build`, so
`v1.2.3`, `1.2.3`, `1.2.3+7` and `1.0.1-debug` all parse. Comparison is
component-by-component with a build-number tiebreaker, never string
comparison (`1.10.0` must beat `1.9.0`). An update is offered only when
`latest > current`; equal or older answers "already up to date", and
unparseable versions on either side surface as an error instead of a silent
skip.

**APK selection.** All `.apk` assets are collected, then: an asset whose name
contains one of the device's `supportedAbis` wins, otherwise one containing
`universal`, otherwise one with no ABI marker at all, otherwise the first
APK. This covers both a single universal APK and a per-ABI split without
knowing which convention the repository will use.

**Download and install.** `OtaUpdate().execute(url, destinationFilename:
'riyaplay_update.apk')` downloads with progress events and hands the file to
the system installer through the plugin's `FileProvider`. The dialog cannot
be dismissed while a download is running (`PopScope(canPop: !_isWorking)`),
and every `OtaStatus` maps to an Uzbek message with a "Qayta urinish" button:
permission refused, download error, checksum error, install error, cancelled,
already running, internal error.

**Error handling.** `fetchLatest()` never throws. `SocketException` →
"Internetga ulanib bo'lmadi", timeout → "GitHub javob bermadi", 404 → "Reliz
topilmadi", 403 with `x-ratelimit-remaining: 0` → rate-limit message, any
other status → "GitHub xatosi (code)", malformed JSON → "Reliz ma'lumotini
o'qib bo'lmadi", no APK asset → "Relizda APK fayli topilmadi". The startup
check logs and swallows all of them; the manual check shows them.

**"Keyinroq" behaviour.** `_declinedThisSession` blocks further *automatic*
prompts for the rest of the process lifetime. The manual check ignores the
flag, and `_dialogOpen` prevents two dialogs at once.

### Player lifetime and first-session writes (2026-08-13, part 4)

| File | Change | Why | Tested |
| --- | --- | --- | --- |
| `lib/utils/video_helpers.dart` | `controller.dispose(forceDispose: true)` in `safeDispose` | Bug 17 — without the flag `better_player` returns immediately and the ExoPlayer is never released | Yes — heap measured over four cycles |
| `lib/screens/video_player_screen.dart` | `_maybeSyncPosition` returns before touching `_lastSyncAt` when the position is below `_minSavedSeconds`; the 5-second threshold is now the named constant `_minSavedSeconds`; `dispose()` takes `max(value.position, _lastKnownPosition)` | Bug 18 — the first 30 s of a new film produced no write at all, and the exit path could ignore the only good value it had | Yes — device, first and second session |

### Ported from `tplaytv` (2026-08-13, part 3)

| File | Change | Why | Tested |
| --- | --- | --- | --- |
| `lib/main.dart` | Global `routeObserver` (`RouteObserver<PageRoute>`) registered in `MaterialApp.navigatorObservers` | One refresh hook that covers every way the player can be opened | Yes — device |
| `lib/screens/index_screen.dart` | `RouteAware`: `didPopNext` waits for `VideoLauncher.awaitPositionFlush()` and then `reloadLatestViewed()`; the per-card reload was removed as redundant | Home row was stale after playback started from `FilmScreen` / `FilmsFullScreen` | Yes — device: card updated to 32:56 after playing from the episode list, two routes deep |
| `lib/screens/latestviewed_screen.dart` | Same `RouteAware` treatment; `onReturn` plumbing removed | Same reason, one mechanism instead of two | Yes — device |
| `lib/screens/video_player_screen.dart` | `finished` writes the full duration once, disables the wakelock and pops (guarded by `_finishHandled`, `Navigator.canPop`); `_writingSeconds` blocks concurrent duplicate writes | Without it a finished film resumed at "1:29:50" forever; the event fires several times, which first showed up as three identical writes and a `Bad state: No element` from a double pop | Yes — device: single write of 4005 s, no exception, and the entry left the continue-watching list |
| `lib/services/api/films_api.dart`, `lib/services/api_service.dart` | `getFirstEpisode(filmId)` — `/v1/series?filter[film_id]=…&per-page=1&include=track` | `film.lastSeries` is missing from some payloads, and then the "Ko'rishni boshlash" button did nothing at all | Compiles; **fallback path not reproduced on device** — every film tested carried `lastSeries` |
| `lib/screens/film_screen.dart` | `_playSingleFilm()` uses that fallback; `_playVideo` now only validates the URL and delegates; dead `_formatDuration` removed | Bug: a film without `lastSeries` was unplayable | Yes — device (`lastSeries` path) |
| `lib/screens/films_full_screen.dart` | Same delegation; dead `_formatDuration` removed | ~150 duplicated lines that could drift apart | Yes — device |
| `lib/utils/video_launcher.dart` | `playWithChooser()` — server position, "Davom ettirish?" dialog, "Pleerni tanlang" (internal / external / download), shared `_push` with the flush wait; `awaitPositionFlush()` made public | The resume+chooser flow existed twice; only one copy would ever get fixed | Yes — device, both screens |

---

## Tests Performed

There is **no automated test suite** in this project. All verification was
manual, on a physical device, plus static analysis.

### Commands

- `flutter analyze lib` — final result: **5 issues**, all pre-existing
  `library_private_types_in_public_api` infos. No errors, no warnings.
- `flutter build apk --debug` — succeeds.
- `adb install -r build/app/outputs/flutter-apk/app-debug.apk` — succeeds.
- `adb logcat`, `adb shell input tap/swipe`, `adb shell screencap` — used
  throughout for driving and observing the app.
- `adb shell content query --uri content://media/external/video/media ...` —
  used to read finished files' `duration`, `_size`, `mime_type`.
- `ffmpeg -v error -i <file> -f null -` — full decode of two finished
  downloads.
- `curl` against `https://finalapi.riyaplay.uz` using the device's auth token
  — used to inspect raw API payloads (`latest-viewed`, `films/actor/{id}`,
  `films/{id}`).

### Results

**Downloads (device):**

| Check | Result |
| --- | --- |
| Quality picker (720p/480p/360p) | OK |
| Queue: 1 running, others "Navbatda" | OK |
| Notification `Yuklab olinmoqda... 47% (navbatda yana 2 ta)` | OK |
| Back out mid-download | Continues to completion |
| Screen off during download | Foreground service survives |
| Resume after network loss | 126/268 → resumed from 126 |
| Resume after `am force-stop` mid-download | `.part` 33 MB retained, resumed |
| Auto-resume when network returns | Recovered via the 15 s timer |
| Wi-Fi-only ON while on mobile data | Running transfer paused, `.part` kept, auto-resumed on Wi-Fi |
| Season batch (9 episodes collected, 2 skipped as already downloaded) | OK |
| Multi-select 3, 4, 6, 9 | "4 ta epizod tanlandi", 2 queued, 2 skipped |
| Leftover `.part` files after success | None |

**File integrity:** MediaStore `duration` matched the catalogue exactly for
every finished download — 27:06, 55:29, 58:08, 47:45, 46:47*, 50:44, 49:22,
47:45. Two files were pulled and fully decoded with
`ffmpeg -f null -`: **zero errors**. Episode 4 downloaded twice on separate
occasions produced **byte-identical** files (286,810,489 bytes).

> \* The 46:47 figure for 5-qism was **superseded on 2026-08-13**: a clean
> re-download at 720p is 436,429,687 bytes, `ffprobe` duration 2821.46 s
> (= 47:01, exactly the catalogue value), and a full decode reports zero
> errors. The old file was a stale artifact.

**OTA update (device, 2026-08-15).** The real repository has no releases, so
the "update available" and "up to date" paths were exercised by temporarily
pointing the two repository constants at public repositories with real
releases, then reverting and rebuilding. Every row below was observed on the
device:

| Test | How | Result |
| --- | --- | --- |
| Startup check, no release published | real repo | Silent; log `Yangilanishni tekshirish muvaffaqiyatsiz: Reliz topilmadi`, app unaffected |
| Manual check, no release published | real repo | Snackbar "Reliz topilmadi" |
| Update available | temporary repo `RikkaApps/Shizuku` (tag `v13.6.0`) | Dialog "Yangi versiya mavjud", "Versiya 13.6.0 · 2.5 MB", scrollable release notes, "Keyinroq" / "Yangilash" |
| Update now → download | same | Progress 9% → 15% → 96% → done; buttons hidden while downloading |
| Install step | same | The system installer was handed the APK (focus left the app and the app restarted afterwards). Nothing was installed: the device already had that exact version (`firstInstallTime=2026-01-09`), so the installer had nothing to do |
| Already up to date | temporary repo `Ashinch/ReadYou` (tag `0.10.x` < `1.0.1`) | Snackbar "Ilova eng so'nggi versiyada (1.0.1-debug)" — note the `-debug` suffix parsed correctly |
| No internet | `adb shell svc data disable` | Log `Yangilanishni tekshirish muvaffaqiyatsiz: Internetga ulanib bo'lmadi`, no crash |
| GitHub rate limit (403) | observed from the workstation while inspecting the API | Handled by a dedicated branch; **not** reproduced on the device |

**Player memory (device, 2026-08-13, part 4).** `dumpsys meminfo`, Java heap,
sampled after each play → Back cycle of ~25 s:

| Cycle | Before the fix | After the fix |
| --- | --- | --- |
| app start | 14 MB | 13 MB |
| 1 | 169 MB | 179 MB |
| 2 | 330 MB | 174 MB |
| 3 | 481 MB | 17 MB (after GC) |
| 4 | — (OOM territory) | 135 MB |

**First/second session writes (device, part 4):**

| Scenario | Log | Server |
| --- | --- | --- |
| Brand-new film, Catalog → FilmScreen → play → Back at ~20 s, never paused | `10s` (in-playback) then `23s` (exit) | `second.time=23` |
| Same film re-opened from the row, play → Back | write within ~1 s of pressing play, then the exit write | matches |
| Four consecutive play → Back cycles | a write in every cycle (32, 62, 90, 121 s) | matches |

**Watch position (device, 2026-08-13, package `uz.mrlg.riyaplay.debug`):**

| Scenario | Log | Server (`second.time`) |
| --- | --- | --- |
| New film from `FilmScreen`, watch ~50 s, **pause**, then back | `Pozitsiya serverga yozildi: 28s` → `51s` | 51 |
| Same film, resume, watch ~20 s, back **without pausing** | `Pozitsiya serverga yozildi: 78s` at the back press | 78 |
| Continue-watching card, watch ~75 s, back without pausing | 1212 → 1243 → 1273 (30 s apart) → 1278 on exit | 1278 |
| Home card, watch ~20 s, back | 2828 on exit | 2828, and the card immediately read 47:08 |

The second row is the decisive one: the previous periodic sync was more than
30 s old but its value (51) equalled the resume point, so the duplicate guard
suppressed it — the 78 s write can only have come from the exit path.

**Continue watching (device):** progress bars now proportional and pink;
tapping an index card shows the resume dialog and playback resumed at
`Pozitsiya tiklandi: 1221 sekund` (= 20:21, matching the card).
`latestviewed_screen` navigation to the correct film was verified; its **tap →
direct playback** path was **not** verified after the last change.

**Download throughput measurement (incomplete):** on mobile data, with the
timing instrumentation:

| Concurrency | Network throughput | Wall clock |
| --- | --- | --- |
| 10 | 5.55 MB/s | 44.9 s / 241.8 MB |
| 24 | 7.23 MB/s | 34.7 s / 241.8 MB |
| 48 | app restarted — unstable | — |
| 24 (after the fix, 2026-08-13) | 9.44 MB/s network / 9.11 MB/s effective | 49.2 s / 448.0 MB |

The 2026-08-13 row is a different episode on a different day, so it is not
directly comparable with the two above — it is evidence that 24 is **stable**,
not a fourth data point on the curve. In that run app-side work was 4 % of wall
time (write 2 %, persist 2 %, decrypt 0 % — the stream is unencrypted).

App-side processing (decrypt + disk + persistence) was only **3%** of wall
time; this stream is unencrypted so decryption cost was zero. The measurement
was **stopped before a raw single-stream baseline was captured**.

### Not executed

- No unit/widget/integration tests exist; none were added.
- fMP4 (`#EXT-X-MAP`), rotating AES keys and `#EXT-X-BYTERANGE` paths were
  never exercised — this provider serves single-key MPEG-TS only.
- The disk-space pre-check never triggered (device had ample free space).
- `CacheService` cold-start behaviour was not explicitly measured.
- **OTA, not executed against the real repository**: it has no releases yet,
  so the genuine "update available → download → install" path for a RiyaPlay
  APK has never run. A publish-and-retest is the first remaining-work item.
- **OTA, install confirmation dialog**: the system installer received the APK
  but nothing could be installed (the test APK's exact version was already on
  the device), so "user accepts the install" and "user cancels the install"
  were not separately observed.
- **OTA, corrupted download**: no checksum is passed today, so
  `CHECKSUM_ERROR` cannot occur; the branch exists but is unreachable.

---

## Remaining Bugs

### Critical

None known.

### High

None known. (The former concurrency inconsistency is Bug 0 above — fixed and
verified on device.)

### Medium

2. **Actor-screen posters do not render in debug builds.** Reported by the
   user as a pre-existing debug-only behaviour (release renders fine). The
   API payload was verified correct (4 films, each with `files` and
   `thumbnails`, and both the thumbnail and full-size URLs return HTTP 200).
   **Root cause UNKNOWN / NEEDS VERIFICATION.**

3. ~~`latestviewed_screen` tap → direct playback is unverified on device.~~
   **VERIFIED on device (2026-08-13).** Tapping "Farishtalar shahri" showed
   "43:11 dan davom ettirishni xohlaysizmi?", and "Davom ettirish" started the
   correct film with `Pozitsiya tiklandi: 2591 sekund` (= 43:11).

4. ~~5-qism duration discrepancy (~14 s).~~ **RESOLVED (2026-08-13).** The
   file was deleted and re-downloaded cleanly at 720p: 436,429,687 bytes,
   `ffprobe` duration **2821.46 s = 47:01**, exactly the catalogue value. A
   full `ffmpeg -v error -i … -f null -` decode reported **zero errors**. The
   earlier 46:47 file was a stale artifact, not a systematic gap.

### Low

5. **Film detail screen still shows only the first 20 episodes.** The user
   explicitly confirmed this is intentional (preview strip); the full list
   lives in `FilmsFullScreen`. Listed only so it is not "rediscovered".

6. **`removeFromLatestViewed` sends `second['film_id']`** — i.e. an episode
   id — to `/v2/user/last-viewed/{id}`. The TV app does the same and deletion
   works, so this is presumably what the endpoint expects. Left untouched.

---

## Remaining Work

| Task | Reason | Files | Priority | Status | Next step |
| --- | --- | --- | --- | --- | --- |
| ~~Resolve the concurrency constants~~ | Values were self-contradictory | `lib/services/download_service.dart` | High | **DONE** | Both set to 24; verified on device at 9.11 MB/s effective, no restart |
| Finish the throughput comparison | No single-connection baseline was ever captured | `lib/services/download_service.dart` | Low | **Closed deliberately** | Not pursued: the sustained value is now settled (24), and a baseline run costs another ~450 MB of mobile data for a number that would not change the decision. Reopen only if the CDN or the concurrency value changes |
| ~~Remove or gate `_DownloadProfile` instrumentation~~ | Debug scaffolding in production code | `lib/services/download_service.dart` | Medium | **DONE** | `profile.report()` now guarded by `kDebugMode`, so release builds neither format nor log it. The collection itself (stopwatches) is left in place — it is a few microseconds per batch |
| ~~Verify `latestviewed_screen` tap on device~~ | Last unexercised continue-watching path | `lib/screens/latestviewed_screen.dart` | Medium | **DONE** | Resume dialog and playback both confirmed (2591 s) |
| ~~Set the real OTA repository~~ | Placeholder repo name from the port | `lib/services/update_service.dart` | Medium | **DONE (2026-08-15)** | Now `d4rk73rr0r/rplay-releases`, with manual check, error messages and version comparison |
| Publish the first release and re-test end to end | The repository is empty, so the real "update available" path has never run against it; the install step was only observed with a third-party APK that was already installed | — | High | Not started | Build a release APK, publish it as `v1.0.2` (or higher) with the APK attached, then run both the startup and the manual check on a device carrying `1.0.1` |
| Decide the release asset naming | The picker guesses (ABI name → `universal` → no-marker → first APK) because there was nothing to inspect | `lib/services/update_service.dart` | Medium | Not started | Pick one convention (e.g. `riyaplay-<version>-arm64-v8a.apk` / `-universal.apk`) and keep it stable |
| Consider a checksum | `ota_update` supports `sha256checksum`, which would catch a truncated or tampered download | `lib/services/update_service.dart` | Low | Not started | Publish the APK's SHA-256 in the release body or as a second asset and pass it to `execute` |
| ~~Re-check 5-qism duration~~ | Possible missing tail content | — | Low | **DONE** | Clean re-download is exactly 47:01 and decodes without errors |
| Investigate debug-mode poster rendering | Affects development experience | `lib/widgets/poster_card.dart`, `lib/utils/image_cache_manager.dart` | Low | Not started | Compare `CachedNetworkImage` behaviour between debug and release |
| ~~Route `film_screen` / `films_full_screen` playback through `VideoLauncher`~~ | Duplicated `_playVideo`, no flush wait, no refresh | `lib/screens/film_screen.dart`, `lib/screens/films_full_screen.dart`, `lib/utils/video_launcher.dart` | Medium | **DONE** | Both delegate to `VideoLauncher.playWithChooser`; verified on device |
| Verify the `getFirstEpisode` fallback | The new branch only runs for a film whose payload has no `lastSeries`, which no tested film had | `lib/services/api/films_api.dart`, `lib/screens/film_screen.dart` | Low | Not started | Find such a film in the catalogue (or stub the field out in a debug build) and confirm the button plays instead of doing nothing |
| Re-test the reported scenario on a **release** build | The user's release install (`uz.mrlg.riyaplay`, versionCode 2002, installed 18:21) predates the part-4 fixes; every part-4 measurement was made on `uz.mrlg.riyaplay.debug` | — | High | Not started | `flutter build apk --release`, install, repeat: new film → play → Back without pausing, and four play/Back cycles while watching `dumpsys meminfo` |
| Re-check TV channels after the disposal change | `tv_channels_screen` pushes the same player for live streams; the disposal path changed for it too, and it was not re-exercised end to end | `lib/screens/tv_channels_screen.dart` | Medium | Not started | Open a channel, watch, leave, repeat twice and check the heap |
| Sessions shorter than 6 s are still not saved | `_minSavedSeconds = 5` is deliberate (an accidental open should not fill the row), but it does mean a very short first session leaves a `00:00` card | `lib/screens/video_player_screen.dart` | Low | By design | Revisit only if users complain about the empty card, not about the position |
| Backport to `tplaytv` | That project writes the position only on exit/`WillPop`/`finished`, and its progress bars use the non-existent `film.playback_time` so they always read full | `tplaytv/lib/screens/video_player_screen.dart`, `tplaytv/lib/widgets/index/index_sections.dart`, `tplaytv/lib/screens/latestviewed_screen.dart` | Medium | Not started | Copy the 30 s periodic sync + pause write, and switch the denominator to the item's `duration` |

---

## Recommended Improvements

### Recommended but NOT implemented

- **Continue-watching could open the episode directly from the film page
  too.** `latestViewedEpisodeId()` exists and is used by `VideoLauncher`, but
  other entry points still route through `FilmScreen`.
- **Deduplicate `_playVideo`.** `film_screen.dart` and
  `films_full_screen.dart` contain near-identical copies (URL validation,
  resume dialog, player choice). `lib/utils/video_launcher.dart` is the
  natural home; the TV project already did this.
- **Wire `ApiErrorHandler` into the remaining screens.** Only three screens
  use it; `catalog_screen.dart` and others still interpolate raw `$e`.

### Optional

- A "download whole series" shortcut from the film page (currently only from
  the episode list).
- An in-app library of finished downloads (files land in
  `/sdcard/Movies/RiyaPlay/`; the queue screen lists tasks, not files).

### Future refactoring

- `index_screen.dart` is very large and mixes provider, screen and card
  widgets.
- `film_screen.dart` likewise; the cast strip and episode strip could be
  extracted.

### Performance

- Segment concurrency tuning (see Remaining Work).
- `CacheService` currently only covers the home screen; catalog/genre lists
  could use it.

### Code quality

- No tests exist at all. Even a few unit tests around
  `lib/utils/latest_viewed.dart` and the HLS parser would be high-value: both
  are pure logic and both had real bugs.

### Security / reliability

- The persisted `download_tasks` JSON contains signed stream URLs including
  their tokens. It lives in app-private storage, so this is not an
  exposure, but tokens expire (~6 h), which is why "Davom ettirish" on an old
  failed task can fail; re-queueing from the film page works because the
  resume key ignores the query string.

---

## Important Discoveries

1. **`sendRequest` never throws.** Non-200 and network errors both return a
   map with `success: false`. Callers must check the payload shape.
2. **`second.film_id` is an episode id**, not a film id — the sibling `model`
   field says `common\models\Series`.
3. **`film.playback_time` does not exist** in the latest-viewed payload. Use
   the item's own `duration` (seconds).
4. **The `files` object shape differs per endpoint.** `/v2/films/actor/{id}`
   with a minimal `include` returns only `domain`/`folder`/`file`/`ext` with
   no `link`/`linkAbsolute`/`thumbnails`; with the full include list
   (`files,paid,tags,likesCount,genres,holder.logo`) all of them appear. Also
   note `domain` says `cdn.bektv.uz` while the working URL is
   `cdn.riyaplay.uz`.
5. **Android theme gates edge-to-edge.** `extendBodyBehindAppBar` and
   `SystemUiMode.edgeToEdge` are both insufficient if `NormalTheme` lacks
   `windowDrawsSystemBarBackgrounds`. Once the theme allows it, the Dart-side
   mode call is unnecessary.
6. **`ota_update` requires core library desugaring**, otherwise the Gradle
   configure phase fails with
   `Dependency ':ota_update' requires core library desugaring to be enabled`.
7. **`connectivity_plus` only reports connection *type* changes.** Walking out
   of Wi-Fi range and back emits **no** event (the type never stopped being
   `wifi`), which is why the queue needs its own periodic retry timer. Device
   logs confirmed recovery came from `(taymer)`, never from
   `(ulanish hodisasi)`, during a real outage.
8. **Stream tokens last ~6 hours** (two Unix timestamps embedded in the URL).
9. **MediaStore cannot be written with plain file I/O** on Android 10+, and
   raw path writes to a *pending* entry fail too — bytes must go through the
   resolver's `OutputStream`.
10. **Peak disk usage during a download is ~2× the final file**, not 3×: the
    `.part` + remuxed MP4 coexist, then the temp file + its MediaStore copy
    coexist, but those two peaks do not overlap.

---

## Files Changed

Modified:

- `lib/main.dart` — `DownloadManager.instance.restore()` before `runApp`; OTA check in `MainScreen.initState`; 2026-08-13: global `routeObserver`.
- `lib/screens/film_screen.dart` — cast strip + `_CastTile`, `ActorFilmsScreen` navigation, `episodeId` plumbing, server-only resume, status-bar scrim, dead `flexibleSpace` removed.
- `lib/screens/films_full_screen.dart` — batch/season download, multi-select mode, `PopScope`, `episodeId` plumbing, server-only resume, `ApiErrorHandler`.
- `lib/screens/index_screen.dart` — `_primeFromCache`, cache writes, continue-watching progress/colour fix, `VideoLauncher` tap.
- `lib/screens/latestviewed_screen.dart` — correct film id, progress helper, tap → playback, long-press → film page.
- `lib/screens/video_player_screen.dart` — server-only watch position, real `startAt` field; 2026-08-13: working exit write, 30 s periodic sync, `pendingPositionFlush`.
- `lib/utils/video_launcher.dart` — 2026-08-13: waits for the exit write before the caller reloads its list.
- `lib/utils/video_helpers.dart` — 2026-08-13: `safeDispose` now passes `forceDispose: true` (Bug 17).
- `lib/screens/download_screen.dart` — rewritten as quality picker + queue view.
- `lib/screens/profile_screen.dart` — "Yuklab olishlar" entry.
- `lib/screens/genres_films_screen.dart` — `FilmCard` image fallback now tries `linkAbsolute`.
- `lib/screens/categories_screen.dart` — `ApiErrorHandler` messages.
- `lib/services/api_service.dart` — facade methods for the new film APIs.
- `lib/services/api/films_api.dart` — `getEpisodeDetails`, `getWatchedSeconds`, `updateWatchProgress`, `getActorFilms`; latest-viewed `sort=-updated_at`.
- `lib/services/download_service.dart` — see Fixes Implemented; plus, on
  2026-08-13, `_maxSegmentConcurrency = 24` with
  `_initialSegmentConcurrency = _maxSegmentConcurrency`, and
  `profile.report()` guarded by `kDebugMode` (`package:flutter/foundation.dart`
  import added).
- `pubspec.yaml` — added `ota_update: ^7.1.0`.
- `android/app/build.gradle.kts` — debug suffix, core library desugaring.
- `android/app/src/main/kotlin/uz/mrlg/riyaplay/MainActivity.kt` — `getFreeBytes`, `.m4s` MIME.
- `android/app/src/main/res/values/styles.xml`, `values-night/`, `values-v31/`, `values-night-v31/` — edge-to-edge theme flags.

New:

- `lib/services/download_manager.dart` — the download queue.
- `lib/services/error_handler.dart` — `ApiErrorHandler`.
- `lib/services/cache_service.dart` — short-lived home cache.
- `lib/services/update_service.dart` — GitHub OTA; rewritten 2026-08-15 against `d4rk73rr0r/rplay-releases` (manual check, `AppVersion` comparison, user-visible errors).
- `lib/screens/actor_films_screen.dart` — films by actor.
- `lib/utils/latest_viewed.dart` — latest-viewed payload helpers.
- `lib/utils/video_launcher.dart` — resume-aware player launcher.
- `RIYAPLAY_STATUS.md` — this document.

> Note on Git: before this checkpoint the repository had a single commit
> (`8bdc166 first commit`) containing an older React-Native-era tree, so most
> of the current Flutter sources were **untracked** and ~230 stale
> `android/app/src/main/res/drawable-*` PNGs plus the `windows/` runner showed
> as deleted. That was pre-existing repository state, not something this
> session caused. The checkpoint commit records all of it (286 files).
>
> `android/app/local.properties` is deliberately **left untracked** — it holds
> a machine-specific `flutter.sdk` path. `android/key.properties` (signing
> passwords) is covered by `android/.gitignore` and was never staged.
>
> Git identity was not configured in this environment; it was set
> **repository-locally** to `MRLG <d4rk73rr0r@gmail.com>`, matching the
> existing history. No global Git config was modified and nothing was pushed.

---

## Do Not Repeat

- **Do not re-investigate the 404 on `Kalmar o'yini 3-qism / segment244.ts`.**
  Reproduced on a completely fresh download; it is a source-side defect and is
  already mitigated by the tail-skip rule.
- **Do not try to "fix" the progress bar by looking for `playback_time`.** The
  field is absent from the payload; `duration` is the correct denominator.
- **Do not use `second['film_id']` as a film id.** It is the episode id.
- **Do not add `SystemUiMode.edgeToEdge` calls to `FilmScreen`.** This was
  tried and then removed — the theme change alone is sufficient, and toggling
  the mode per screen is unnecessary churn.
- **Do not chase `AppBar.flexibleSpace` rendering.** It was already broken
  before this session; the scrim now lives in the poster `Stack` and works. A
  solid-red test proved the replacement renders.
- **Do not raise segment concurrency to 48 expecting a win.** It measured
  worse per connection and coincided with an app restart; 24 gave 7.23 MB/s vs
  10 giving 5.55 MB/s. 24 is now the single sustained value
  (`_initialSegmentConcurrency = _maxSegmentConcurrency`) and was re-verified
  stable at 9.11 MB/s effective over 448 MB.
- **Do not re-open the 5-qism duration question.** A clean re-download is
  exactly 47:01 (2821.46 s) and decodes without errors.
- **Do not re-test the `latestviewed_screen` tap path.** Verified end to end on
  device: dialog → "Davom ettirish" → `Pozitsiya tiklandi: 2591 sekund`.
- **Do not chase a single-connection throughput baseline.** It was dropped on
  purpose — see Remaining Work.
- **Do not look for a local playback-position fallback.** It was deliberately
  removed; the server is the single source of truth.
- **Do not re-add `mounted` / `_isDisposed` guards to
  `_savePlaybackPosition`.** That guard is exactly what killed the exit write
  (Bug 13). The write must survive the widget it was started from.
- **Do not "simplify" `VideoLauncher._awaitPositionFlush` into a plain
  `await pendingPositionFlush`.** The player's `dispose()` runs *after*
  `Navigator.push` returns, so at that instant the field is still null — the
  short polling loop is the point (Bug 16).
- **`updateWatchProgress` posts to `/v2/films/second/{episodeId}` with
  `{"second": n}`** and the endpoint answers either a bare `true` or a map.
  Both are treated as success; this was re-verified against the live API.
- **Do not re-compare the API layer with `tplaytv`.** Endpoints, includes,
  sort order and the `_t` cache buster are already identical; the differences
  are all on the UI side and are listed in the part-3 table.
- **Do not port `film.playback_time` progress maths from `tplaytv`.** The
  field does not exist in the payload — that is riya_play's Bug 9, still
  unfixed on the TV side.
- **`BetterPlayerEventType.finished` fires more than once.** It must be
  guarded (`_finishHandled`), and the pop needs `Navigator.canPop` — the
  unguarded version produced three identical writes and
  `Bad state: No element` from `NavigatorState.pop`.
- **The server drops an entry from `latest-viewed` once the position equals
  the full duration.** That is why a finished film disappears from
  "Ko'rishni davom ettirish" — expected, not a bug.
- **The app never sends `0` as a position.** A `00:00` card means the
  latest-viewed row exists with **no** `second` record — the server creates
  the row when the episode/stream is requested. Check `second.time` in the
  API before assuming a bad write.
- **Do not call `controller.dispose()` without `forceDispose: true`.** With
  `autoDispose: false` it is a silent no-op and leaks the whole ExoPlayer
  (Bug 17). This is the crash.
- **Do not "optimise" `_maybeSyncPosition` by stamping `_lastSyncAt` first.**
  That is exactly what created the 30-second dead window at the start of a
  new film (Bug 18).
- **`network_service.dart` and `performance_monitor.dart` in `tplaytv` are
  dead code** — they are referenced nowhere in that project. Do not port them.
- **`registerQr` / `qr_screen` from `tplaytv` are the TV side of the pairing
  flow** (they *generate* the QR). `riya_play` is the phone side and already
  scans via `mobile_scanner` + `checkQR`. They are complementary, not
  duplicates.

---

## Next Recommended Step

**Publish the first GitHub release, which also settles the part-4 rebuild.**
Build a release APK, bump `version:` in `pubspec.yaml` above `1.0.1`, publish
it on `d4rk73rr0r/rplay-releases` with the APK attached, and keep the asset
name stable from then on. That single step both gets the fixed build onto the
reporter's device and gives the OTA feature something real to find; until a
release exists, every update check correctly answers "Reliz topilmadi".

Afterwards, verify on a device still carrying the older build: the startup
dialog appears, "Keyinroq" silences it for that session, the manual check in
Profile finds the same release, and "Yangilash" downloads and opens the
installer.

**Also still open: build and install a release APK and repeat the part-4
reproduction on it.**
Everything in part 4 was measured on `uz.mrlg.riyaplay.debug`; the release
install on the test device (`uz.mrlg.riyaplay`, versionCode 2002, last updated
2026-08-13 18:21) still carries the leaking `safeDispose`, so the reporter will
keep seeing both the crash and the `00:00` card until it is rebuilt:

```
flutter build apk --release
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

Then: a new film from Catalog → play → Back without pausing (expect a write
during playback and one on exit, and `second.time` on the server), followed by
four play → Back cycles while watching `dumpsys meminfo` (expect a bounded
Java heap, no OOM).

The remaining open items are all Medium/Low and independent: the release asset
naming convention, an optional SHA-256 for the download, the unexercised
`getFirstEpisode` fallback, the debug-only actor-poster rendering, wiring
`ApiErrorHandler` into the screens that still interpolate raw `$e`, TV-channel
playback after the disposal change, and the `tplaytv` backport (periodic sync
+ `duration` denominator).
