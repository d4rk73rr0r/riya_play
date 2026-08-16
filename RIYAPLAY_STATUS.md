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

### Session of 2026-08-16, part 2 — the install-permission flow, end to end

The four install-flow scenarios that the previous session left unfinished were
run on the physical device against a debug build that actually contains the
part-1 fixes. The debug APK that was on the device (built 02:45) predated
commit `c700676` (11:26), so it was rebuilt and reinstalled first — measuring
the old package would have proved nothing.

| # | Scenario | Result |
| --- | --- | --- |
| 1a | `appops … deny` → "Yangilanishni tekshirish" → "Yangilash" | **PASS.** No download starts. The dialog explains the missing permission and the primary button becomes "Ruxsat berish" |
| 1b | "Ruxsat berish" | **PASS.** `com.android.settings/.Settings$ManageAppExternalSourcesActivity` opens for this package |
| 2 | Return from Settings **without** enabling | **PASS.** Red message "Ruxsat hali berilmagan…", button still "Ruxsat berish", no crash, no download |
| 1c | Enable the switch, then Back | **PASS.** `didChangeAppLifecycleState` re-checks, the download starts by itself (observed at 68 %), and the installer intent is fired at 100 % |
| 3 | `appops … allow` from the start → "Yangilash" | **PASS.** Download, then `com.google.android.packageinstaller/…PackageInstallerActivity` on top with "Обновить приложение?" — no detour |
| 4 | Restore the switch | Left at **`allow`**, which is what it was at the start of the session (it was `allow` before test 1a set it to `deny`). Not reset to `default` |

The install intent itself is fine. On the first run the system showed
`com.android.internal.app.ResolverActivity` instead of the installer, because
this device has a second handler for `ACTION_INSTALL_PACKAGE`
(`com.nh.aex/.InstallApk`, "APKExtractor"). That is a device-local chooser, not
an app defect; on the next run the installer opened directly.

**Two real defects surfaced while running the tests, both now fixed** (commit
`d82a8f5`):

1. **The dialog could not be dismissed after cancelling the installer.**
   `ota_update` emits `INSTALLING` when the installer intent is fired and then
   emits **nothing at all** — a user who taps "Отмена" produces no event. The
   dialog therefore kept `_isWorking == true` forever, which meant `PopScope`
   refused Back **and** both action buttons were hidden by
   `if (!_isWorking)`. Tapping outside does nothing either
   (`barrierDismissible: false`). The only escape was force-stopping the app.
   Verified stuck on device, then verified fixed: `INSTALLING` now clears
   `_isWorking`, sets `_installerLaunched`, and renders a single "Yopish"
   button; Back works again. A retry button is deliberately **not** offered —
   it would re-download 45 MB for an APK already on disk.
2. **Release notes rendered their own markup.** The dialog showed
   `<p>OTA yuklanish rate-limit fix qilindi.</p>`, tags included. Two separate
   causes: the API path passed `data['body']` through verbatim, and the atom
   path stripped tags *before* unescaping, so `&lt;p&gt;` turned into a visible
   `<p>` afterwards. Both now share `_plainText`, which unescapes first and
   strips afterwards. Verified clean on device.

**A stale claim in this document was disproved.** The published `v1.0.3`
arm64 asset was downloaded and inspected directly:

```
aapt dump badging app-arm64-v8a-release.apk
package: name='uz.mrlg.riyaplay' versionCode='2004' versionName='1.0.3'
```

So the release APK **is** correctly versioned, despite `v1.0.2` and `v1.0.3`
both being 47,297,998 bytes. The device's release install agrees
(`versionName=1.0.3, versionCode=2004`, updated 2026-08-16 02:56). The
"Republish with a correctly versioned APK" item is therefore **closed**, and
the earlier note that both releases report `1.0.1 / 2002` was wrong.

### Session of 2026-08-16, part 5 — glass bottom bar and a hidden navigation bar

Two requests: make the bottom menu look like "liquid glass", and make the
Android navigation bar transparent and hidden, summoned when needed.

**Apple's Liquid Glass material does not exist on Android**, so the effect is
assembled by hand in `lib/widgets/glass_bottom_bar.dart`: a floating rounded
panel with a translucent white gradient, a bright hairline border, and an
optional real `BackdropFilter` blur. `Scaffold(extendBody: true)` is required
— without content behind it there is nothing to show through and the panel
collapses into a flat colour.

**The real blur is implemented but switched off**, by measurement, with the
user's agreement. On the SM-A556E at 120 Hz, sitting idle on the home tab:

| Variant | raster p50 | raster p90 | janky frames / 3 s |
| --- | --- | --- | --- |
| no `BackdropFilter` | 3.6–4.3 ms | 4.7–6.3 ms | **0** |
| `BackdropFilter` σ=18 | 6.5–8.2 ms | 8.3–8.8 ms | 4–29 |
| `BackdropFilter` σ=10 | 8.4–8.6 ms | 8.9–9.1 ms | 47–59 |

The 120 Hz budget is 8.3 ms. Lowering the sigma did **not** help — the cost is
`BackdropFilter` itself re-reading the backdrop every frame, not the blur
radius. It compounds with the unresolved "home tab redraws at ~120 fps while
idle" finding from part 4: the blur is paid ~120 times a second for a screen
that is not changing. During scrolling the blur is fine (0–6 janky frames).

So `GlassBottomBar.blur` defaults to `false` and carries the table above in
its doc comment. **Fix the idle redraw first, then flip it to `true`** — the
two are the same problem.

**System navigation bar.** `lib/utils/system_ui.dart` is now the single place
that touches `SystemChrome`:

- `AppSystemUi.apply()` — `SystemUiMode.manual` with only
  `SystemUiOverlay.top`, i.e. the status bar stays (the home and film screens
  are designed to draw under it) and the navigation bar is hidden.
- A `setSystemUIChangeCallback` re-hides the bar 3 s after the user swipes it
  into view, so it stays summonable without becoming permanent. Verified on
  device: swipe up reveals the three-button bar and the glass menu slides
  above it; 5 s later both are back to the hidden state.
- `AppSystemUi.applyFullscreen()` — `immersiveSticky`, for the player.
- `VideoPlayerScreen.dispose()` now restores through `AppSystemUi.apply()`.
  It previously restored `SystemUiOverlay.values`, which would have brought
  the navigation bar back permanently after every playback.
- All four `styles.xml` variants gained a transparent `navigationBarColor`.
  `systemNavigationBarContrastEnforced: false` is set in the overlay style —
  without it Android 10+ paints its own scrim behind a transparent bar.

**Verified on device**: menu renders and switches tabs, the indicator tracks
the selected tab, swipe-to-reveal and auto-re-hide both work, playback resumes
and the position still saves (01:53 → 02:23, card moves to the front), and the
navigation bar stays hidden after leaving the player.

**Watch out**: `extendBody: true` means content now scrolls *under* the menu.
The Profile list and the catalog grid were checked and both still reach their
last item, but any screen with a finite scrollable and no bottom padding could
hide its last row behind the glass.

### Session of 2026-08-16, part 4 — performance audit

Audit date: **2026-08-16**. Everything below was measured on a real device in
**profile** mode; no conclusion here comes from a debug build or from reading
code alone.

#### Testing environment

| | |
| --- | --- |
| Flutter | 3.44.9 stable (revision `6b182d2c75`) |
| Dart | 3.12.2, DevTools 2.57.0 |
| Device | Samsung SM-A556E (Galaxy A55), Android 16, SDK 36, 1080×2340 @ 120 Hz |
| Network | mobile data (4G/4G+) throughout |
| Build mode | `flutter build apk --profile`, Impeller/Vulkan |
| Package | `uz.mrlg.riyaplay.debug` (see below) |

**Profile builds now install as `.debug`.** `build.gradle.kts` gained a
`profile` build type with `applicationIdSuffix = ".debug"` and the debug
signing config. Without it a profile build installs as `uz.mrlg.riyaplay`,
which would replace the user's release install and fail with
`INSTALL_FAILED_UPDATE_INCOMPATIBLE` (different signing key). Sharing the debug
package also means profiling starts from an already logged-in session, which
the authenticated flows need.

#### How the numbers were taken

- **Startup**: `flutter run --profile --trace-startup`, reading
  `build/start_up_info.json` (`timeToFirstFrame` etc.). 3–4 runs per
  configuration.
- **Flow timings**: temporary `debugPrint` markers on one `Stopwatch` started
  at Dart `main`, read back with `adb logcat -s flutter`. All of this
  instrumentation was **removed** before committing.
- **Frames**: a temporary `SchedulerBinding.addTimingsCallback` probe
  aggregating build/raster percentiles every 3 s. Also removed.
- `adb shell dumpsys gfxinfo` is **useless here** — it reports
  `Total frames rendered: 0` because Flutter renders into its own SurfaceView
  and bypasses HWUI. Do not reach for it again.
- `appLogger` output does **not** reach logcat in profile builds (only
  `debugPrint` does), which is why the instrumentation used `debugPrint`.

#### Baseline (before any change)

| Metric | Value | Runs |
| --- | --- | --- |
| `timeToFrameworkInit` | 414–428 ms | 4 |
| `timeToFirstFrame` | 1007–1036 ms | 4 |
| `timeToFirstFrameRasterized` | 1041–1066 ms | 4 |
| Splash removed (Dart clock) | 569–596 ms | 3 |
| `DownloadManager.restore()` | 68–93 ms | 3 |
| Home fully loaded | 4643–5038 ms | 3 |
| Home idle frame build p50 / p90 | 3.5 / 4.0 ms | — |
| Home idle frame raster p50 / p90 | 2.6 / 3.3 ms | — |
| Home scroll build p90 / raster p90 | 2.4 / 2.7 ms, ~0 % jank | — |
| Catalog scroll build p90 / raster p90 | 1.7 / 4.8 ms, 1–2 % jank | — |

#### Prioritized findings

| Priority | Area | Problem | Evidence | Impact | Fix |
| --- | --- | --- | --- | --- | --- |
| **CRITICAL** | Home / network | The entire home data set is fetched **twice** on every cold start | Two complete sets of markers per launch, second starting ~1000 ms after the first, in 3/3 runs | ~18 duplicated HTTP requests per launch (5 sections + one per category) | Only refetch on a real offline→online transition |
| **HIGH** | Home / network | The five home sections are fetched **sequentially** | banners 0.65 s → +1.0 s → +0.7 s → +0.25 s → +1.7 s ≈ 4.3 s | ~2.5 s of avoidable wall time | `Future.wait` over the five independent fetches |
| **HIGH** | Startup | ~600 ms of the first frame is **artificial waiting** | `timeAfterFrameworkInit` 593–615 ms; the code holds the splash for `Future.delayed(500 ms)` plus a `Future.doWhile` that sleeps 100 ms waiting on a flag that is hardcoded `true` | ~0.5 s added to every launch | Hold the splash only for the `SharedPreferences` warm-up |
| **MEDIUM** | Home / rendering | The carousel's 6 s ring indicator rebuilds a widget subtree **every vsync** | Home-tab idle build p50 3.5 ms vs 1.2 ms with the animation disabled | ~2.3 ms of build per frame at ~120 fps, permanently, while the home tab is visible | Drive `CustomPainter` from the controller via `repaint:` and isolate it with a `RepaintBoundary` |
| **LOW** | Home / network | `_checkInternetConnection()` does a DNS lookup of `google.com` before every home load | 30–190 ms measured, 5 s timeout in the worst case | small today, unbounded on a hostile network | Not changed — see "not implemented" |

#### Rejected hypotheses (measured, then dropped)

- **`await DownloadManager.instance.restore()` before `runApp`.** It costs
  68–93 ms, but making it non-blocking changed `timeToFirstFrame` by nothing
  (1006–1028 ms vs 1007–1036 ms). Left as is — the ordering is deliberate.
- **`GoogleFonts.poppinsTextTheme` in the theme.** Bypassing it entirely left
  `timeToFirstFrame` unchanged (1003–1024 ms). Not a startup cost.
- **Scrolling / list rendering.** Home and catalog scroll at build p90 ≤ 2.4 ms
  and raster p90 ≤ 4.8 ms against an 8.3 ms budget, with 0–2 % janky frames.
  There is no rendering bottleneck to fix, so no widget was "optimized"
  speculatively.

#### Optimizations implemented

**1 — Home data was fetched twice per launch**

```
Problem:        every cold start issued the whole home API set twice
Root cause:     `Connectivity().onConnectivityChanged` emits the *current*
                state on subscribe, and the handler treated any non-offline
                event as "connection restored" and refetched
Change:         `_wasOffline` flag; refetch only on offline → online
Before:         two complete marker sets per launch (3/3 runs)
After:          one (3/3 runs)
Improvement:    ~50 % of home HTTP traffic removed
Regression:     offline → online still refetches, because that path sets
                `_wasOffline = true` first
```

**2 — Home sections fetched sequentially**

```
Problem:        home took ~4.3 s to finish loading
Root cause:     five independent `await`s in a row in `_fetchInitialData`
                (the file even carried a TODO saying so)
Change:         one `Future.wait` over all five
Before:         4643–5038 ms to fully loaded (3 runs)
After:          1594–2154 ms, median ~1837 ms (3 runs)
Improvement:    ~62 % faster, ~3.1 s saved
Regression:     error handling unchanged; `notifyAfterUpdates()` still runs
                once after everything settles
```

**3 — Artificial startup delay**

```
Problem:        ~600 ms of the first frame was padding
Root cause:     `initialization()` awaited `Future.delayed(500 ms)` and a
                `Future.doWhile` polling `themeProvider.isInitialized`, which
                is hardcoded `true` and so cost exactly one 100 ms sleep
Change:         hold the splash only for `SharedPreferences.getInstance()`
Before:         splash removed at 569–596 ms; `timeToFirstFrame` 1007–1036 ms
After:          splash removed at 73–88 ms; `timeToFirstFrame` 450–630 ms
Improvement:    ~45 % faster to first frame, ~450 ms saved
Regression:     `_checkAuthToken` reads the same prefs instance immediately
                afterwards, so it is warm; no spinner flash observed
```

**4 — Carousel indicator rebuilt the tree every frame**

```
Problem:        the home tab never idles: ~120 fps with build p50 3.5 ms
Root cause:     a 6 s `AnimationController` fed a `ValueListenableBuilder`
                that rebuilt the indicator widget on every tick, and the
                repaint propagated up because nothing bounded it
Change:         `CircleProgressPainter` takes the `Animation` and passes it to
                `super(repaint:)`; the `CustomPaint` sits in a `RepaintBoundary`
Before:         build p50 3.5 ms, raster p50 2.6 ms
After:          build p50 1.2 ms, raster p50 3.7 ms
Improvement:    ~1.2 ms less work per idle frame (~14 % of the 8.3 ms budget)
Regression:     the ring animates exactly as before
Note:           the `RepaintBoundary` is load-bearing — removing it puts build
                p50 straight back to 3.2–3.6 ms (measured)
```

The app still renders ~120 fps while idle on the home tab; the ring animation
was **not** the cause (disabling it left the frame count unchanged). Whatever
keeps the pipeline awake — most likely the `carousel_slider` page view — was
not identified and remains open.

#### Regression tests performed

On the optimized profile build, on device:

- Home renders with banners, continue-watching, recommendations and category
  rows. **PASS**
- Continue-watching card → resume dialog ("22:11 dan davom ettirishni
  xohlaysizmi?") → playback → ~45 s → Back → the card reads **22:57** and moves
  to the front of the row. The exit write, the server sync and the
  `didPopNext` refresh all still work. **PASS**
- Catalog tab loads and scrolls. **PASS**
- Profile screen renders; "Yangilanishni tekshirish" answers "Ilova eng
  so'nggi versiyada (1.0.4-profile)", i.e. `AppVersion` comparison still
  works. **PASS**
- Android Back out of the player returns to Home without a crash. **PASS**
- `flutter analyze`: 5 pre-existing infos, the unchanged baseline.

Not re-tested after the changes: authentication (the session was already
live), TV channels, favourites, downloads, and the full OTA download+install
chain.

#### Recommended but NOT implemented

- **Drop the `google.com` DNS probe in `_checkInternetConnection()`.** It adds
  30–190 ms before every home load and can block for 5 s. `sendRequest`
  already never throws and reports failures, so the probe mostly duplicates
  work. Left alone because removing it changes the offline-error UX, which
  needs a product decision.
- **Find what keeps the home tab rendering at ~120 fps while idle.** Measured
  and reproducible; the cause was not isolated. Worth a DevTools timeline
  session.
- **`_processFilms` runs on the UI isolate** for every category response. It
  did not show up as a bottleneck at 10 items per category, but it will if the
  page size grows.
- **`MainScreen` keeps all five tabs alive** via `KeepAliveWrapper`. This is a
  deliberate UX choice; it costs memory but was not measured as a problem.
- **Memory over navigation cycles was NOT measured.** `dumpsys meminfo` cycles
  were not run in this session — treat leak questions as open.

### Session of 2026-08-16, part 3 — versioning, and where `2004` came from

**The `versionCode=2004` mystery is solved: it is Flutter's own ABI offset.**
`flutter build apk --split-per-abi` does not ship `flutter.versionCode`
verbatim — it adds a per-ABI multiplier:

| ABI | offset | with `+N` |
| --- | --- | --- |
| `armeabi-v7a` | 1000 | `1000 + N` |
| `arm64-v8a` | 2000 | `2000 + N` |
| `x86_64` | 4000 | `4000 + N` |

So the published arm64 `v1.0.3` asset reporting `2004` was built from
`version: 1.0.3+4`, and the earlier `2002` from `1.0.1+2`. Nothing was ever
set outside version control, and `android/local.properties` was never the
source — the Flutter tool **rewrites** its `flutter.versionName` /
`flutter.versionCode` lines from `pubspec.yaml` on every build, and
`build.gradle.kts` only reads them back. `pubspec.yaml` is, and always was,
the single source of truth. This was verified by building twice and reading
the result with `aapt dump badging`:

| `pubspec.yaml` | `local.properties` | armeabi-v7a | arm64-v8a | x86_64 |
| --- | --- | --- | --- | --- |
| `1.0.4+2005` | `1.0.4` / `2005` | — | `4005` | — |
| `1.0.4+5` | `1.0.4` / `5` | `1005` | `2005` | `4005` |

**Release version is now `1.0.4+5`.** `+5` is deliberate: the device's release
install is `2004`, and `2000 + 5 = 2005` clears it by exactly one. A large
build number such as `+2005` would work too but inflates to `4005` on arm64
and makes every future bump harder to reason about. The offset rule is now
documented in a comment above `version:` in `pubspec.yaml`.

Built and verified locally with `flutter build apk --release --split-per-abi`.
**Not uploaded** — publishing the release is the owner's call.

### Session of 2026-08-16 — the app died at 100% instead of installing

Reported: the update downloads to 100 %, then the app closes and nothing is
installed. Investigated before changing anything.

**The download itself is fine.** The plugin writes to
`/data/data/<applicationId>/files/ota_update/riyaplay_update.apk`; on the
device that file was **47,297,998 bytes**, byte-for-byte the size the GitHub
asset reports. Nothing is wrong with the transfer or the file.

**What runs at 100 %.** `OtaUpdatePlugin.onDownloadComplete()` →
`executeInstallation()`. The app is not a system app, so
`hasInstallPackagesPermission()` (which checks the privileged
`INSTALL_PACKAGES`) is false, and `usePackageInstaller` was not set, so it
takes `installUsingActionInstallPackage()`:

```java
Uri apkUri = FileProvider.getUriForFile(context, androidProviderAuthority, downloadedFile);
intent = new Intent(Intent.ACTION_INSTALL_PACKAGE);
```

`androidProviderAuthority` defaults to `<applicationId>.ota_update_provider`.

**Root cause.** `ota_update` does **not** declare that provider in its own
manifest — its README asks the host app to declare it, and this app never
did. `FileProvider.getUriForFile` therefore throws
`IllegalArgumentException` on the main thread inside a `handler.post`
lambda, nothing catches it, and an uncaught Java exception crossing JNI kills
the Flutter process — the same
`[FATAL:…platform_view_android_jni_impl.cc(1485)] Check failed:
fml::jni::CheckException(env).` signature already present in the device's
crash records. That is the "app closes at 100 %".

**Second, independent gap.** The plugin never checks
`PackageManager.canRequestPackageInstalls()`. `REQUEST_INSTALL_PACKAGES` in
the manifest is only half of it: since API 26 the user must additionally
allow "Install unknown apps" for this specific app. Nothing asked for it and
nothing reacted to it being off.

**Fix.** Declare what the plugin needs (`OtaUpdateFileProvider` with
`@xml/ota_update_file_paths`, plus `InstallResultReceiver`), and gate the
download behind the install permission: check it **before** downloading —
spending 45 MB of mobile data only to fail at the end is worse — send the
user to `Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES` for this package, re-check
on resume via `WidgetsBindingObserver`, and continue automatically once it is
granted. The APK is deleted on a later start, never while the installer may
still be reading it.

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
  to tolerate that. The release install on the test device reported
  `versionName=1.0.1, versionCode=2002` **at the time**, i.e. release APKs are
  built with a custom build number. (As of 2026-08-16 it reports
  `1.0.3 / 2004`; see the 2026-08-16 part 2 section.)
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

### OTA install flow (2026-08-16)

| File | Change | Why | Tested |
| --- | --- | --- | --- |
| `android/app/src/main/AndroidManifest.xml` | `<provider sk.fourq.otaupdate.OtaUpdateFileProvider>` with authority `${applicationId}.ota_update_provider`, and `<receiver sk.fourq.otaupdate.InstallResultReceiver>` | Without the provider `FileProvider.getUriForFile` throws and the app dies at 100 % | Yes — device, no crash after the change |
| `android/app/src/main/res/xml/ota_update_file_paths.xml` (**new**) | `<files-path name="internal_apk_storage" path="ota_update/"/>` | The exact directory the plugin downloads into | Yes |
| `android/app/.../MainActivity.kt` | `canInstallPackages` (via `PackageManager.canRequestPackageInstalls()`) and `openInstallPermissionSettings` (`Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES` for this package, with fallbacks) on the existing `uz.mrlg.riyaplay/media_store` channel | The permission has to be checked and requested from somewhere; this channel already existed | Yes — device |
| `lib/services/update_service.dart` | Permission checked **before** the download; `_needsPermission` turns the button into "Ruxsat berish"; `WidgetsBindingObserver` re-checks on resume and continues by itself; `PERMISSION_NOT_GRANTED_ERROR` mid-flight also offers the settings route; `_cleanupDownloadedApk()` removes the ~45 MB APK on a later start | Requirement: never assume the permission, never die, always allow a retry | Partially — see the test table |

### OTA updates (2026-08-15)

| File | Change | Why | Tested |
| --- | --- | --- | --- |
| `lib/services/update_service.dart` | Rewritten: correct repository, `fetchLatest()` returning a sealed `UpdateCheckOutcome` (`UpdateAvailable` / `UpdateUpToDate` / `UpdateCheckFailed`), `AppVersion` comparison, defensive APK picker, themed dialog with release notes and download progress, per-status Uzbek error messages, `checkOnStartup()` and `checkManually()` | The old version queried a non-existent repo, was silent on every failure and had no manual entry point | Yes — device, see the table below |
| `lib/screens/profile_screen.dart` | "Yangilanishni tekshirish" tile calling `UpdateService.checkManually(context)` | Requirement: Profile → check for updates | Yes — device |
| `lib/main.dart` | `MainScreen.initState` now calls `checkOnStartup` (renamed from `checkUpdate`) | The name now says which of the two entry points it is | Yes — device |
| `android/app/src/main/AndroidManifest.xml` | Explicit `REQUEST_INSTALL_PACKAGES` | Already merged in from the plugin; declaring it makes the install flow visible in the manifest | Yes — builds and installs |

**Rate limiting (added after the first real release, 2026-08-15).** The
anonymous GitHub API allows 60 requests per hour **per IP**, and mobile
carriers put thousands of subscribers behind one address — the reporter hit
the limit on their second check. Two layers now protect against it:

1. The startup check only queries GitHub if at least `_startupCheckInterval`
   (6 hours) has passed since the last check; the timestamp lives in
   `SharedPreferences` under `ota_last_check_at`. The manual check ignores the
   interval.
2. When the API answers 403 or 429, the service falls back to
   `https://github.com/<user>/<repo>/releases.atom`, which is served like any
   normal page and is **not** rate limited. The feed carries the tag and the
   release notes but no asset list, so the APK URL is rebuilt from the
   `--split-per-abi` convention
   (`releases/download/<tag>/app-<abi>-release.apk`) and confirmed with a HEAD
   request, which also yields the size from `Content-Length`.

**Repeat-prompt guard (added 2026-08-15 after the `v1.0.3` test).** When the
user starts an install, the release tag is stored under `ota_installed_tag`.
The **automatic** check skips a release whose tag equals that value; the
manual check still shows it. This exists because a release APK can carry a
`versionName` that does not match its tag — see the packaging pitfall below —
in which case the app would otherwise offer the same update forever.

**Packaging pitfall — `android/local.properties` overrides `pubspec.yaml`.**
`flutter build` mirrors the version into `android/local.properties` as
`flutter.versionName` / `flutter.versionCode`, and `build.gradle.kts` reads
`flutter.versionCode` / `flutter.versionName` from there. A stale pair in that
(gitignored) file silently overrides `pubspec.yaml` on every later build. That
is why the published `v1.0.2` and `v1.0.3` assets are **byte-identical**
(47,297,998 bytes each) and both report `versionName=1.0.1, versionCode=2002`:
the APK was never actually rebuilt with a new version. Before publishing,
check the value the build really produced:

```
adb shell dumpsys package uz.mrlg.riyaplay | grep -E "versionName|versionCode"
```

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
| GitHub rate limit (403) | observed from the workstation while inspecting the API, and reported from the device after the first real release | Now falls back to the atom feed instead of failing |

**Install flow (device, 2026-08-16).** The install permission was forced with
`adb shell appops set uz.mrlg.riyaplay.debug REQUEST_INSTALL_PACKAGES deny`.

| Test | Result |
| --- | --- |
| 1a. Permission OFF, press "Yangilash" | **PASS** — no download starts; the dialog explains that "Noma'lum ilovalarni o'rnatish" is required and the button becomes "Ruxsat berish". No crash |
| 1b. Press "Ruxsat berish" | **PASS** — `com.android.settings/…Settings$ManageAppExternalSourcesActivity` opens, i.e. the per-app screen, not a generic one |
| 1c. Enable, return, install | **NOT RUN** — the device was disconnected mid-test |
| 2. Permission ON from the start | **NOT RUN** |
| 3. Return from Settings without enabling | **NOT RUN** |
| 4. Failed / incomplete download | **NOT RUN** — the plugin reports `DOWNLOAD_ERROR`, which the dialog already renders, but it was not provoked |

> The device left the USB session before the remaining cases could run. Also
> note: `REQUEST_INSTALL_PACKAGES` for `uz.mrlg.riyaplay.debug` is still on
> `deny` from the test — restore it with
> `adb shell appops set uz.mrlg.riyaplay.debug REQUEST_INSTALL_PACKAGES default`.

**After the first real release (`v1.0.2`, published 2026-08-15 with
`flutter build apk --release --split-per-abi`):**

| Test | Result |
| --- | --- |
| Assets published | `app-arm64-v8a-release.apk` 45.1 MB, `app-armeabi-v7a-release.apk` 54.8 MB, `app-x86_64-release.apk` 48.8 MB |
| Update offered to a `1.0.1-debug` device | Dialog showed the arm64 asset — 45 MB — i.e. the ABI-specific pick is correct |
| Second check minutes later | GitHub API returned 403 (rate limit) → snackbar. This is what prompted the interval + atom fallback |
| Atom fallback, forced on (temporary build) | Startup and manual checks resolved `v1.0.2` from the feed and correctly reported "Ilova eng so'nggi versiyada (1.0.2-debug)" once the device itself carried 1.0.2 |
| Constructed split-APK URLs, HEAD | `arm64-v8a` → 200 / 45.1 MB, `armeabi-v7a` → 200 / 54.8 MB, `x86_64` → 200 / 48.8 MB, `riscv64` → 404 (loop moves on) |
| 6-hour startup interval | Verified: after a check, a fresh app start performed no request and showed nothing; the manual check still worked |

**Against the `v1.0.3` release (2026-08-15, device on `1.0.2-debug`):**

| Test | Result |
| --- | --- |
| Startup check | Dialog "Yangi versiya mavjud", "Versiya 1.0.3 · 45.1 MB", release note "OTA yuklanish rate-limit fix qilindi." |
| "Keyinroq" | Dialog closed, app usable |
| Manual check right after "Keyinroq" | Dialog shown again — the session flag only silences the automatic check |
| "Yangilash" | 45 MB downloaded and handed to the system installer; `PackageInstallerSession: Session installed` and `uz.mrlg.riyaplay` `lastUpdateTime` moved — the full chain works |
| Installed result | Still `versionName=1.0.1, versionCode=2002` — the published APK's own version was never bumped (see the packaging pitfall) |
| Repeat-prompt guard | With `ota_installed_tag=v1.0.3` stored, the startup check logs "Yangilanish so'ralmadi: v1.0.3 allaqachon o'rnatilgan" and shows nothing, while the manual check still offers it |

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
- **OTA, install confirmation dialog**: "user cancels the install" **was**
  observed on 2026-08-16 (part 2) and produced the stuck-dialog bug, now
  fixed. "User accepts the install" was observed on 2026-08-15
  (`PackageInstallerSession: Session installed`) but **not** re-run after the
  part-2 changes — the accept path only closes the app's own dialog by
  replacing the process, so nothing in the fix touches it.
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
| ~~Publish the first release and re-test~~ | — | — | High | **DONE (2026-08-15)** | `v1.0.2` published with three split APKs; a `1.0.1-debug` device was offered the 45 MB arm64 asset |
| ~~Finish the download+install test against the real release~~ | — | — | Medium | **DONE (2026-08-15)** | `v1.0.3` downloaded and installed through the app; `PackageInstallerSession: Session installed` |
| ~~Republish with a correctly versioned APK~~ | — | — | High | **DONE / claim was wrong (2026-08-16)** | `aapt dump badging` on the published `v1.0.3` arm64 asset reports `versionCode=2004 versionName=1.0.3`; the device install agrees. Nothing to republish |
| ~~Find out where `versionCode=2004` comes from~~ | — | `pubspec.yaml` | Medium | **DONE (2026-08-16)** | Flutter's `--split-per-abi` ABI offset (`arm64 = 2000 + N`). `pubspec.yaml` was always the only source; version is now `1.0.4+5` → arm64 `2005` |
| **Publish `v1.0.4`** | Built and verified locally, not uploaded | — | Medium | Not started | Upload `app-<abi>-release.apk` from `build/app/outputs/flutter-apk/` to a `v1.0.4` release, then re-run the OTA check on a device. Note the binaries in that directory now also carry the part-4 performance work |
| **Find the idle ~120 fps redraw on the home tab** | Measured, cause not isolated; the ring animation was ruled out | `lib/screens/index_screen.dart` | Medium | Not started | DevTools timeline on a profile build while the home tab sits untouched |
| **Measure memory over navigation cycles** | Not covered by the audit | — | Medium | Not started | `dumpsys meminfo` across repeated Home → Catalog → FilmScreen → Player → Back cycles |
| **Re-measure segment concurrency at 48** | Raised from 24 by the owner's decision without a new measurement | `lib/services/download_service.dart` | Medium | Not started | Download one ~450 MB episode and compare throughput and stability against the recorded 24 → 9.11 MB/s effective |
| **Run the install-flow tests on a release build** | Every part-2 result was measured on `uz.mrlg.riyaplay.debug` | — | Medium | Not started | Same four scenarios against `uz.mrlg.riyaplay` once a newer release exists to offer |
| ~~Decide the release asset naming~~ | — | `lib/services/update_service.dart` | Medium | **Settled** | `app-<abi>-release.apk`, the default `flutter build apk --split-per-abi` output. The atom fallback now depends on this name — renaming assets breaks it, so keep it |
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
- `lib/screens/index_screen.dart` — `_primeFromCache`, cache writes, continue-watching progress/colour fix, `VideoLauncher` tap; 2026-08-16 (part 4): `_wasOffline` guard, parallel `Future.wait` home load, `CircleProgressPainter` driven by `repaint:` inside a `RepaintBoundary`.
- `lib/main.dart` — 2026-08-16 (part 4): `initialization()` no longer pads the splash with `Future.delayed`/`Future.doWhile`.
- `android/app/build.gradle.kts` — 2026-08-16 (part 4): `profile` build type installs as `.debug` with the debug signing config.
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

- `lib/utils/system_ui.dart` — `AppSystemUi`: the only place that changes system-bar mode.
- `lib/widgets/glass_bottom_bar.dart` — the glass panel behind the bottom menu; `blur` off by measurement.
- `lib/services/download_manager.dart` — the download queue.
- `lib/services/error_handler.dart` — `ApiErrorHandler`.
- `lib/services/cache_service.dart` — short-lived home cache.
- `lib/services/update_service.dart` — GitHub OTA; rewritten 2026-08-15 against `d4rk73rr0r/rplay-releases` (manual check, `AppVersion` comparison, user-visible errors); 2026-08-16: install-permission gating, and (part 2) `_installerLaunched` + shared `_plainText`.
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
- **Segment concurrency history.** 10 gave 5.55 MB/s, 24 gave 7.23 MB/s, and
  the first attempt at 48 was unstable and coincided with an app restart — but
  that run predates the Bug 17 `safeDispose` ExoPlayer leak fix, so the restart
  was not necessarily the concurrency's fault. **As of 2026-08-16 the value is
  48 by the project owner's decision** and has **NOT** been re-measured. If a
  download ever restarts the app again, suspect this constant first;
  `_maxInFlightBytes` (64 MB) is what still bounds heap use.
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
- **Do not re-run the four install-permission scenarios on a debug build.**
  All four passed on 2026-08-16 (part 2); only the release-build repeat is
  still open.
- **Do not assume `ota_update` reports a cancelled installation.** After
  `INSTALLING` the stream is silent forever, whatever the user does in the
  system installer. Any UI state entered at `INSTALLING` must be able to exit
  on its own — this is exactly what produced the undismissable dialog.
- **Do not "restore" `if (!_isWorking)` on both dialog actions.** That guard
  is what hid every button after the installer opened.
- **Do not strip HTML tags before unescaping entities** in the release notes.
  The atom feed delivers them as `&lt;p&gt;`, so stripping first leaves
  visible tags behind. `_plainText` unescapes first on purpose.
- **Do not claim the published releases are mis-versioned.** Verified with
  `aapt dump badging`: `v1.0.3` arm64 is `versionCode=2004 versionName=1.0.3`.
  Equal asset sizes between `v1.0.2` and `v1.0.3` are not evidence of an
  identical build.
- **Do not use `adb shell dumpsys gfxinfo` on this app.** It reports
  `Total frames rendered: 0` — Flutter draws into its own SurfaceView and never
  goes through HWUI. Use `SchedulerBinding.addTimingsCallback` or DevTools.
- **`appLogger` output does not reach logcat in profile builds.** Only
  `debugPrint` does. Any temporary profile-mode instrumentation must use
  `debugPrint`.
- **Do not re-test whether `DownloadManager.restore()` or `GoogleFonts` slow
  down startup.** Both were ablated and measured: neither moves
  `timeToFirstFrame`.
- **Do not "optimize" the list/grid widgets for scroll performance.** Measured
  at build p90 ≤ 2.4 ms and raster p90 ≤ 4.8 ms against an 8.3 ms budget, with
  0–2 % janky frames. There is nothing there.
- **Do not remove the `RepaintBoundary` around the carousel ring.** Without it
  the per-frame build cost goes straight back from 1.2 ms to 3.2–3.6 ms.
- **Do not turn on `GlassBottomBar.blur` "to see if it is fast enough".** It
  was measured at two sigmas; both blow the 120 Hz budget on the home tab. The
  numbers are in the widget's doc comment. Re-measure only after the idle
  redraw is fixed.
- **Do not lower `blurSigma` hoping to make the blur cheap.** σ=10 measured
  *worse* than σ=18. The cost is the backdrop read, not the radius.
- **Do not call `SystemChrome.setEnabledSystemUIMode` from a screen.** Go
  through `AppSystemUi`; the player and the shell used to fight over the
  system bars, which is what `lib/utils/system_ui.dart` exists to prevent.
- **Do not restore `SystemUiOverlay.values` in the player's `dispose`.** That
  brings the Android navigation bar back permanently on top of the glass menu.
- **A chooser instead of the installer is a device quirk.** This device has
  `com.nh.aex/.InstallApk` (APKExtractor) registered for
  `ACTION_INSTALL_PACKAGE`, so Android shows `ResolverActivity` until a
  default is picked. Nothing to fix in the app.

---

## Next Recommended Step

**The OTA chain is finished.** All four install-permission scenarios pass, both
defects found while running them are fixed and re-verified on device, and the
published APKs turned out to be correctly versioned after all. Nothing in the
update flow is known to be broken.

**Find what keeps the home tab rendering at ~120 fps while idle.** This is the
one measured performance question the audit could not answer — and it now
blocks a product decision too: the glass menu's real blur is switched off
because of it (part 5). The carousel's
ring animation was ruled out (disabling it left the frame count unchanged), so
the next suspect is `carousel_slider`'s page view. Attach DevTools to a profile
build, sit on the home tab, and read the timeline:

```bash
flutter run --profile -d RZCX91W8YGP
```

Everything else the audit found is fixed and re-measured; see part 4 above for
the numbers and for the items deliberately left alone.

**Also open: repeat the watch-position reproduction on a release build.**
Everything in part 4 was measured on `uz.mrlg.riyaplay.debug`. The release
install on the test device is now `uz.mrlg.riyaplay`, versionCode 2004, last
updated 2026-08-16 02:56 — whether that build contains the part-4
`safeDispose` fix has **not** been established, so rebuild from the current
tree rather than trusting it:

```
flutter build apk --release
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

Then: a new film from Catalog → play → Back without pausing (expect a write
during playback and one on exit, and `second.time` on the server), followed by
four play → Back cycles while watching `dumpsys meminfo` (expect a bounded
Java heap, no OOM).

The remaining open items are all Medium/Low and independent: where
`versionCode=2004` actually comes from, the install-flow repeat on a release
build, an optional SHA-256 for the download, the unexercised
`getFirstEpisode` fallback, the debug-only actor-poster rendering, wiring
`ApiErrorHandler` into the screens that still interpolate raw `$e`, TV-channel
playback after the disposal change, and the `tplaytv` backport (periodic sync
+ `duration` denominator).
