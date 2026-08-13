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

`flutter analyze lib` reports **5 issues, all pre-existing
`library_private_types_in_public_api` infos** in
`latestviewed_screen.dart`, `profile_screen.dart` and two `profile/` screens.
That is the clean baseline — compare against it, do not expect zero output.

Debug APK builds and installs successfully. Device used for testing:
**Samsung Galaxy A55 (SM-A556E), Android 16 / API 36**, package
`uz.mrlg.riyaplay.debug`.

---

## Bugs Found

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
| `lib/screens/latestviewed_screen.dart` | Same tap/long-press split; correct film id and progress | Bug 8 / 9 | Compiles; **tap NOT verified on device** |

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

> \* The 46:47 file (5-qism) is ~14 s shorter than the catalogue's 47:01. This
> was **not** re-verified with a clean re-download, so it is **NEEDS
> VERIFICATION** whether that is a source metadata discrepancy or a real gap.

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

App-side processing (decrypt + disk + persistence) was only **3%** of wall
time; this stream is unencrypted so decryption cost was zero. The measurement
was **stopped before a raw single-stream baseline was captured**.

### Not executed

- No unit/widget/integration tests exist; none were added.
- fMP4 (`#EXT-X-MAP`), rotating AES keys and `#EXT-X-BYTERANGE` paths were
  never exercised — this provider serves single-key MPEG-TS only.
- The disk-space pre-check never triggered (device had ample free space).
- OTA update was only observed failing gracefully with no network.
- `CacheService` cold-start behaviour was not explicitly measured.

---

## Remaining Bugs

### Critical

None known.

### High

1. **`_initialSegmentConcurrency = 48` vs `_maxSegmentConcurrency = 16`**
   (`lib/services/download_service.dart:317-321`). The initial value exceeds
   the maximum, so only the **first** batch uses 48 connections and every
   later batch is clamped to 16. A 48-wide batch previously coincided with an
   app restart during testing. This is an inconsistent configuration that
   should be resolved deliberately.

### Medium

2. **Actor-screen posters do not render in debug builds.** Reported by the
   user as a pre-existing debug-only behaviour (release renders fine). The
   API payload was verified correct (4 films, each with `files` and
   `thumbnails`, and both the thumbnail and full-size URLs return HTTP 200).
   **Root cause UNKNOWN / NEEDS VERIFICATION.**

3. **`latestviewed_screen` tap → direct playback is unverified on device.**
   The code compiles and mirrors the index screen path, which does work.

4. **5-qism duration discrepancy (~14 s).** See the note above.

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
| Resolve the concurrency constants | Current values are self-contradictory | `lib/services/download_service.dart` | High | Not started | Decide a single sustained value (16 was stable; 48 was not) and set both constants coherently |
| Finish the throughput comparison | Started, interrupted; no raw baseline captured | `lib/services/download_service.dart` | Medium | In progress | Capture a single-connection baseline against the same CDN, then compare with the 10/24 numbers already collected |
| Remove or gate `_DownloadProfile` instrumentation | It is debug scaffolding left in production code | `lib/services/download_service.dart` | Medium | Not started | Either delete it or guard it behind `kDebugMode` once the measurement is finished |
| Verify `latestviewed_screen` tap on device | Only path of the continue-watching change not exercised | `lib/screens/latestviewed_screen.dart` | Medium | Not started | Open the screen, tap a card, confirm the resume dialog and playback |
| Set the real OTA repository | `repoName = "riyaplay-releases"` is a placeholder chosen during the port | `lib/services/update_service.dart` | Medium | Not started | Confirm the actual GitHub releases repo, or remove the OTA feature if the app ships via Play |
| Re-check 5-qism duration | Possible missing tail content | — | Low | Not started | Delete the file and re-download cleanly, compare `duration` |
| Investigate debug-mode poster rendering | Affects development experience | `lib/widgets/poster_card.dart`, `lib/utils/image_cache_manager.dart` | Low | Not started | Compare `CachedNetworkImage` behaviour between debug and release |

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

- `lib/main.dart` — `DownloadManager.instance.restore()` before `runApp`; OTA check in `MainScreen.initState`.
- `lib/screens/film_screen.dart` — cast strip + `_CastTile`, `ActorFilmsScreen` navigation, `episodeId` plumbing, server-only resume, status-bar scrim, dead `flexibleSpace` removed.
- `lib/screens/films_full_screen.dart` — batch/season download, multi-select mode, `PopScope`, `episodeId` plumbing, server-only resume, `ApiErrorHandler`.
- `lib/screens/index_screen.dart` — `_primeFromCache`, cache writes, continue-watching progress/colour fix, `VideoLauncher` tap.
- `lib/screens/latestviewed_screen.dart` — correct film id, progress helper, tap → playback, long-press → film page.
- `lib/screens/video_player_screen.dart` — server-only watch position, real `startAt` field.
- `lib/screens/download_screen.dart` — rewritten as quality picker + queue view.
- `lib/screens/profile_screen.dart` — "Yuklab olishlar" entry.
- `lib/screens/genres_films_screen.dart` — `FilmCard` image fallback now tries `linkAbsolute`.
- `lib/screens/categories_screen.dart` — `ApiErrorHandler` messages.
- `lib/services/api_service.dart` — facade methods for the new film APIs.
- `lib/services/api/films_api.dart` — `getEpisodeDetails`, `getWatchedSeconds`, `updateWatchProgress`, `getActorFilms`; latest-viewed `sort=-updated_at`.
- `lib/services/download_service.dart` — see Fixes Implemented.
- `pubspec.yaml` — added `ota_update: ^7.1.0`.
- `android/app/build.gradle.kts` — debug suffix, core library desugaring.
- `android/app/src/main/kotlin/uz/mrlg/riyaplay/MainActivity.kt` — `getFreeBytes`, `.m4s` MIME.
- `android/app/src/main/res/values/styles.xml`, `values-night/`, `values-v31/`, `values-night-v31/` — edge-to-edge theme flags.

New:

- `lib/services/download_manager.dart` — the download queue.
- `lib/services/error_handler.dart` — `ApiErrorHandler`.
- `lib/services/cache_service.dart` — short-lived home cache.
- `lib/services/update_service.dart` — GitHub OTA.
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
  10 giving 5.55 MB/s.
- **Do not look for a local playback-position fallback.** It was deliberately
  removed; the server is the single source of truth.
- **`network_service.dart` and `performance_monitor.dart` in `tplaytv` are
  dead code** — they are referenced nowhere in that project. Do not port them.
- **`registerQr` / `qr_screen` from `tplaytv` are the TV side of the pairing
  flow** (they *generate* the QR). `riya_play` is the phone side and already
  scans via `mobile_scanner` + `checkQR`. They are complementary, not
  duplicates.

---

## Next Recommended Step

**First, resolve the download concurrency configuration in
`lib/services/download_service.dart` (lines ~316-321) before anything else.**

Concretely: open the file and read the four constants
(`_maxInFlightBytes`, `_maxSegmentConcurrency = 16`,
`_minSegmentConcurrency`, `_initialSegmentConcurrency = 48`). The initial
value is larger than the maximum, so only the first batch is 48-wide and every
subsequent batch is clamped to 16 by `_adaptConcurrency`. Decide one coherent
value — the measured data says 24 outperformed 10 (7.23 vs 5.55 MB/s) while 48
was unstable — set `_initialSegmentConcurrency <= _maxSegmentConcurrency`,
rebuild, and re-run one download to confirm stability.

Only after that, either finish the throughput comparison or delete the
`_DownloadProfile` instrumentation, and then verify the one untested UI path:
tapping a card in `latestviewed_screen.dart` should show the
"Davom ettirish / Boshidan" dialog and start playback.
