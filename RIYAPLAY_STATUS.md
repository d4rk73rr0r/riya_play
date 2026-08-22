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
- New-content notifications are three files in `lib/services/`
  (`notification_service.dart`, `new_content_service.dart`,
  `new_content_scheduler.dart`) plus `lib/utils/notification_router.dart`. The
  poller compares `publish_time` against one `SharedPreferences` key and runs
  both on a 5-minute `Timer` and on an `AndroidAlarmManager` alarm, so it keeps
  working after the process is killed.
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

### Session of 2026-08-22, part 3 — OnTV added as the third source

The owner supplied a Python playlist generator (`m3u8.py`) that pulls
`https://api.ontv.uz/api/v2/channels` with a hard-coded account bearer and
writes an `.m3u` out of `url_1080 / url_720 / url_480`. That endpoint became
the third TV source.

#### What the API gives, and what it costs

One request returns everything the tab needs:

```
GET https://api.ontv.uz/api/v2/channels
      ?append=promotion&include=file,categories&per_page=100&_f=json&_l=uz
```

- **84 channels, `last_page: 1`** — no paging loop, unlike the BizTV code this
  replaces.
- Each row carries `url_1080` / `url_720` / `url_480` directly, so **there is no
  per-channel stream call at all** — the cheapest of the three sources.
- `file.url` is a ready CDN link (`https://cdn.ontv.uz/…webp`); every channel
  has one (0 without).
- `include=categories` returns the channel categories inline. There are only
  **two** with `type: 3` — `Bepul kanallar` (6) and `Pullik kanallar` (78).
  `/api/v2/categories` also exists but is the *film* catalogue's: 36 rows, only
  those two of them about channels. It is not called.

Two facts that shape the caching:

- **The bearer is what makes the list useful.** Without `Authorization` the
  endpoint still answers 200 with all 84 rows, but only **one** of them has a
  stream URL; the rest come back null. Measured 2026-08-22 (201,716 bytes with
  the token against 154,605 without).
- **The stream URLs expire.** They are signed
  (`token=<hash>-<hash>-1787412727-1787391127`, the pair being issue and
  expiry) — about **six hours**. So the list is held in memory for 30 minutes
  (`_onTvChannelsTtl`) and **never written to disk**; `_fetchChannels` skips the
  screen's `dataCacheManager` for OnTV exactly as it does for OqTV.

The bearer is a JWT with `exp: 1806132793` — **late March 2027**. When the list
comes back stream-less after that date, the token is the first thing to check.

The streams live on `https://fl.biztv.media/…` — the same CDN the removed BizTV
source used, but reachable through a different API and over HTTPS, so the
cleartext exception added for OqTV is not involved.

#### Changes

| File | Change |
| --- | --- |
| `lib/services/tv_api_service.dart` | `OnTV` added to `baseUrls`, `onTvHeaders` with the account bearer, `_onTvChannelsRaw` (30-minute memory cache), `_onTvChannel` mapping, category extraction from the channels themselves, and the `OnTV` branch of `getStreamUrl` (a lookup, with one forced refetch if the id is missing) |
| `lib/screens/tv_channels_screen.dart` | `_fetchChannels` now skips the disk cache for `OnTV` as well as `OqTV` |
| `CLAUDE.md` | the TV paragraph now covers three providers |
| `pubspec.yaml` | `1.0.9+10` → `1.0.10+11` |

#### Verified on device (debug build, SM-A556E)

| Check | Result |
| --- | --- |
| Source dropdown | **PASS** — `OqTV`, `OnTV`, `SpecUZ` |
| OnTV "Barchasi" | **PASS** — "Kanallar soni: 84 ta", logos rendered |
| OnTV categories | **PASS** — tabs `Pullik kanallar` / `Bepul kanallar`; the free tab shows exactly 6, matching the API |
| OnTV playback | **PASS** — `Setanta Sports 1` played live at 1080p |
| logcat during the run | **0** `E/flutter`, 0 `ExoPlaybackException` |
| `flutter analyze lib` | 5 pre-existing infos, the unchanged baseline |

#### Verified on a **release** build, then published

The two defects of v1.0.8 both hid in release-only transforms, so the release
APK was installed over the device's `1.0.9 / 2010` before publishing anything:

| Check | Result |
| --- | --- |
| Launch | **PASS** — no splash freeze, catalogue home reached with the owner's session intact |
| OnTV playback | **PASS** — `Setanta Sports 1` live |
| OqTV playback | **PASS** — `Al Jazeera HD` live, i.e. `network_security_config.xml` survived the resource shrinker |
| logcat | 0 `CleartextNotPermitted`, 0 `ExoPlaybackException` |

`v1.0.10` was then published to `d4rk73rr0r/rplay-releases` (2026-08-22
10:06 UTC) as **Latest**, all three split APKs `uploaded`
(`1011 / 2011 / 4011`, `versionName 1.0.10` confirmed with `aapt dump badging`),
and the arm64 asset's `digest` equals the local `sha256sum`
(`4136267330c1…`). Source commits `b7b7ac4..96c6783` are pushed to
`d4rk73rr0r/riya_play`.

### Session of 2026-08-22, part 2 — OqTV replaces SalomTV and BizTV

The owner asked for the two legacy TV sources to go and for **OqTV** to take
their place. The provider's own PHP client was supplied as the reference
(`kinom_helper.php`, `tvchannels.php`, `watch.php`), so the protocol was read
off working code rather than guessed, then re-verified request by request with
`curl` before any Dart was written.

#### What OqTV actually requires

Two hosts and four calls before a stream URL exists:

| Step | Call | Gives |
| --- | --- | --- |
| 1 | `POST https://api.oq.uz/token/base/` with `{"serial_number": …}` | anonymous `access` (a JWT bearer) |
| 2 | `POST https://api.oq.uz/api/v1/kinom/auth/token/` with `Authorization: Bearer …` | `access_token` (catalogue) + `user_id` |
| 3 | `POST /v2/users/self/devices?access_token=…` on `uzbeeline.platform24.tv` | device `id` |
| 4 | `POST /v2/auth/device?access_token=…`, **form-encoded** `device_id` | `access_token` (stream) |

Facts that cost a request each to establish, all measured on 2026-08-22:

- **The catalogue token cannot fetch a stream.** `/v2/channels/{id}/stream`
  answers `401 authentication_failed` ("Некорректные учетные данные") with it;
  only the device token from step 4 works. Categories, by contrast, need only
  the step-2 token.
- **Step 4's body must be `application/x-www-form-urlencoded`.** That is what
  the reference client sends, and it is the one call in the chain that is not
  JSON.
- **Device registration is not idempotent.** Registering twice with the *same*
  serial returned two different ids (`0cde2e7f-…` and `4119e2f9-…`), so every
  app start would otherwise add a row to the provider's account. The serial,
  the device id and the stream token are therefore persisted in
  `SharedPreferences` as `oqtv_serial` / `oqtv_device_id` / `oqtv_stream_token`.
- **One request carries the whole tab.**
  `/v2/users/self/channels/categories` returns 275 KB: 13 categories, each with
  its channels inline, 98 unique channels in total, every one with a `cover`.
  There is no per-category call to make.
- **The provider localises by `Accept-Language`.** With `uz` the category names
  come back Uzbek already ("Bolajonlarga", "Ma'rifat", "Musiqiy"); the Russian→
  Uzbek map in the service is only a fallback for when they do not.
- **`Все каналы` (id 2) is dropped.** It duplicates every other category and the
  screen already has its own "Barchasi" tab.
- The stream response carries both `hls_mbr` (multi-bitrate master) and `hls`;
  the app prefers `hls_mbr`. The URL embeds the device token and expires, so it
  is fetched fresh on every tap and never cached.

#### Changes

| File | Change |
| --- | --- |
| `lib/services/tv_api_service.dart` | `SalomTV` and `BizTV` removed with all their branches (`fetchAll` paging, `bizTvHeaders`); OqTV added — token chain, persisted device, cached category payload, `getStreamUrl` |
| `lib/screens/tv_channels_screen.dart` | default source now `TVApiService.baseUrls.keys.first` (OqTV); the SalomTV/BizTV special cases in `_fetchChannels`, `_playChannel` and the grid's `onTap` are gone — every source now resolves its URL through `getStreamUrl(source:, channelId:)` |
| `CLAUDE.md` | the "three providers" paragraph rewritten for the two that remain, with the OqTV chain documented |

`getStreamUrl` is new and is the only place a channel id becomes a URL. The
screen no longer needs to know that one source hands out URLs in the list and
another needs a second request.

#### Verified on device

The app's auth gate makes the TV tab unreachable without a real login, so the
service was exercised through a **temporary entry point**
(`lib/oqtv_check_main.dart`, built with `flutter build apk --debug -t …`,
installed as `uz.mrlg.riyaplay.debug`, deleted afterwards). It ran the real
`TVApiService` code on the phone:

```
OQTV-CHECK kategoriyalar: 12         (Все каналы chiqarib tashlangan)
OQTV-CHECK barcha kanallar: 98
OQTV-CHECK birinchi: {id: 2712, title_uz: Al Jazeera HD, image: http://media…png}
OQTV-CHECK kategoriya Bepul: 22 ta
OQTV-CHECK rasmsiz kanallar: 0
OQTV-CHECK strim (2712): http://37.110.212.133:80/mbrjwt/…/index.m3u8
OQTV-CHECK m3u8 kodi: 200, 426 bayt
OQTV-CHECK ikkinchi strim: true       (saqlangan qurilma tokeni qayta ishlatildi)
OQTV-CHECK SpecUZ kategoriyalari: 7
OQTV-CHECK SpecUZ kanallari: 143
OQTV-CHECK SpecUZ strim: https://st1.uzdigital.tv/Kinopremera/index.m3u8?token=…
```

The category names came back Uzbek, the second stream call reused the stored
device token instead of registering again, and SpecUZ — untouched by the
change — still answers through the new `getStreamUrl` path.

`flutter analyze lib`: the 5 pre-existing infos, the unchanged baseline.

#### The defect the service test could not see: cleartext HTTP

With the code working at the service level, the first real tap in the UI still
failed:

```
E ExoPlayerImplInternal: Caused by: com.google.android.exoplayer2.upstream.HttpDataSource$CleartextNotPermittedException:
                         Cleartext HTTP traffic not permitted.
E ExoPlayerImplInternal: Caused by: java.io.IOException: Cleartext HTTP traffic to 37.110.212.134 not permitted
```

OqTV hands out **`http://<ip>:80/...`** playlists and those hosts have no TLS at
all (an `https://` attempt to the same host returns nothing —
`curl` exit code 000). Under `targetSdk = 34` Android blocks cleartext by
default, so ExoPlayer refused the stream before the first byte.

The Dart side never saw this, which is why the service check passed: Dart's
`HttpClient` has its own stack and ignores Android's network security policy.
Only the native players (ExoPlayer/OkHttp) enforce it.

Fixed with `android/app/src/main/res/xml/network_security_config.xml`
(`base-config cleartextTrafficPermitted="true"`), referenced from
`<application android:networkSecurityConfig>`. The permission has to be general:
the stream host is a bare IP that changes per session (37.110.212.133,
37.110.212.134, 95.214.208.236 were all seen within one hour), so no domain
allowlist would hold. Everything else the app talks to is HTTPS regardless.

#### Verified in the UI (debug build, SM-A556E)

Reaching the TV tab needs a real login, so the owner signed in on
`uz.mrlg.riyaplay.debug` and the tab was driven from there:

| Check | Result |
| --- | --- |
| Source dropdown | **PASS** — only `OqTV` and `SpecUZ`; OqTV is the default |
| OqTV "Barchasi" | **PASS** — "Kanallar soni: 98 ta", logos rendered |
| OqTV category tab | **PASS** — "Bolajonlarga" shows exactly 6 (matches the API) |
| OqTV playback | **PASS** — `Al Jazeera HD` played live, fullscreen, no `E/flutter` |
| Source switch → SpecUZ | **PASS** — 143 channels, Uzbek category names |
| SpecUZ playback | **PASS** — `Кинопремьера` played through the new `getStreamUrl` |
| Cleartext errors after the fix | **0** in logcat across both playbacks |
### Session of 2026-08-22 — the release-build verification sweep

Nothing was broken at the start of this session: the working tree was clean at
`b7b7ac4`, `pubspec.yaml` was `1.0.9+10`, and the device carried the shipped
release install `uz.mrlg.riyaplay` `versionName=1.0.9 versionCode=2010`. What
was open were the rows that debug builds could not answer, so this session is a
verification pass rather than a bug hunt. Four of them are now closed.

#### 1. The alarm and its background isolate, on a release build

The debug run of 2026-08-19 could not prove that AOT resolves the top-level
`newContentAlarmCallback`; that is exactly the failure mode that killed the
first implementation. Measured on the release install:

```
13:29:44.923 I/ActivityManager: Killing 3444:uz.mrlg.riyaplay/u0a1278 (adj 850): kill background
13:29:45.086 I/ActivityManager: Start proc 8860:uz.mrlg.riyaplay/u0a1278 for broadcast
                                {uz.mrlg.riyaplay/…androidalarmmanager.AlarmBroadcastReceiver}
13:29:45.186 I/FlutterBackgroundExecutor: Starting AlarmService...
13:29:45.318 I/AlarmService: AlarmService started!
```

No `E DartVM … must be annotated`, no `Fatal: failed to find callback`. The
pending alarm was already due when the process was killed, so the broadcast
started a *fresh* process — the killed-process path, on release.

Proving the Dart side actually ran needed an indirect signal, because
`appLogger` is `Level.nothing` in release and the package is not debuggable, so
neither its logs nor its `SharedPreferences` can be read. Network accounting
answered it: `dumpsys netstats detail`, summed over the `uid=11278 … tag=0x0`
buckets, moved **`rb` 673,908,083 → 673,940,781 (+32,698 B)** and
**`tb` 11,254,512 → 11,256,352 (+1,840 B)** across the alarm window, with no UI
on screen and no other component of that uid alive. That is the poller's
HTTPS fetch of `/v2/films/search` (~168 KB of JSON, ~32 KB gzipped), which runs
*after* `NotificationService.init()` — so the plugin initialised in the
background isolate too.

The process then exited on its own, and the alarm stayed armed:
`origWhen=2026-08-22 13:33:25.602 window=+3m45s0ms repeatInterval=300000`.
The channel is live in the release install as well:
`NotificationChannel{mId='riyaplay_new_content', mName=Yangi kontent, mImportance=4}`.

#### 2. `ic_notification` survives the shipped release build

Checked directly in the published `v1.0.9` arm64 APK rather than by inference:

```
aapt2 dump resources app-arm64-v8a-release.apk
  resource 0x7f0800c7 drawable/ic_notification
    () (file) res/vO.xml type=XML
```

`res/vO.xml` is 668 bytes and decodes to a real `<vector>` with
`fillColor=#ffffffff` — not the empty stub the resource shrinker leaves behind.
`res/raw/keep.xml` is doing its job in the build that actually shipped.

#### 3. A notification really posts on a release build

The detection rule cannot be provoked on a non-debuggable install (the baseline
pref is unreachable and the catalogue's newest `publish_time` was ~19.5 h old
and already seen), so the test was made possible by a **temporary patch**, kept
only for the duration of the test:

- `checkOnce()` rewound `new_content_last_publish_time` to `1787147328` once,
  guarded by a throwaway `_force_new_content_test` flag.
- `flutter build apk --release --split-per-abi --target-platform android-arm64`
  (112.9 s, 45.3 MB, sha1 `7202321547b939011b080defc70c1f71ec9cbe96`).
- `adb install -r` over the release install — same key, same
  `versionCode 2010`, so the owner's session and data survived.

Result, on the release build: **three** notifications, one per film published
after that instant.

| Notification | id | Icon |
| --- | --- | --- |
| `Yangi kontent mavjud` / `Pavana (2026) · Film · Melodrama, Dramma` | 17562 | `Icon(typ=RESOURCE pkg=uz.mrlg.riyaplay id=0x7f0800c7)` |
| `Yangi kontent mavjud` / `O'gay ona (1973) · Film · Dramma` | 17571 | same |
| `Yangi kontent mavjud` / `Adolat Tarozusi (2008) · Serial · Detektiv, Dramma` | 17569 | same |

`0x7f0800c7` is exactly the `drawable/ic_notification` id from the `aapt2` dump
above. All three carried their own poster as the large icon and were grouped
under `groupKey=uz.mrlg.riyaplay.NEW_CONTENT` with an autogroup summary
("Riya Play", count 3) — confirmed on screen, not only in `dumpsys`.

Both tap paths were then exercised on release:

- **App running** — tapping `O'gay ona` pushed `FilmScreen` for
  *O'gay ona (1973)*; the tapped notification auto-cancelled, the other two
  stayed.
- **Process killed** (`am kill`, confirmed gone from `ps`) — tapping `Pavana`
  cold-started the app straight onto `FilmScreen` for *Pavana (2026)*.

Afterwards the shipped APK was reinstalled from a backup taken before the test
(sha1 `40c6d00815f54b98c40a3b9f0dde711bba5f1799`, equal to the recorded
`app-arm64-v8a-release.apk.sha1`), the source patch was reverted, and
`flutter analyze` returned to the 5-info baseline. One harmless leftover: the
release install's `SharedPreferences` still holds `_force_new_content_test`,
a key no shipped code reads.

#### 4. The alarm survives a real reboot

`adb reboot`, then nothing else — the app was never opened.

```
13:45:46.543 I/ActivityManager: Start proc 11762:uz.mrlg.riyaplay/u0a1278 for broadcast
                                {uz.mrlg.riyaplay/…androidalarmmanager.RebootBroadcastReceiver}
13:45:46.644 I/AlarmService: Rescheduling after boot!
```

`dumpsys alarm` showed the alarm back at `13:45:46.736` with the **same**
`origWhen=2026-08-22 13:47:21.527`, `window=+3m45s0ms`, `repeatInterval=300000`
— `rescheduleOnReboot: true` preserves the schedule rather than restarting it.
Device uptime at that check was 114.9 s. The phone was not locked at boot; on a
locked FBE device `BOOT_COMPLETED` waits for the first unlock, so the
reschedule would be delayed until then.

The rescheduled alarm then fired on its own: `Starting AlarmService...` and
`AlarmService started!` at **13:50:31** (pid 16709) against an `origWhen` of
13:47:21.527 — 3m10s late, inside the `+3m45s` window the platform attaches to
an inexact repeat. The app was never opened between the reboot and that fire,
so the post-reboot path is verified end to end, not merely registered.

#### 5. Memory over navigation cycles (the half the audit never covered)

Release `1.0.9`, four Home → Katalog → `FilmScreen` → Back cycles with no
playback, `dumpsys meminfo` after each:

| Cycle | Java Heap (KB) | TOTAL PSS (KB) |
| --- | --- | --- |
| 1 | 10,352 | 488,394 |
| 2 | 20,364 | 513,012 |
| 3 | 16,856 | 503,100 |
| 4 | 17,464 | 509,717 |

Bounded and non-monotonic — the same shape the player cycles produced on
2026-08-17. Nothing to chase here.

### Session of 2026-08-19 — new-content notifications

A feature request, not a bug hunt: notify the user when the catalogue gets new
content, headline **"Yangi kontent mavjud"**, a one-line summary of the title
underneath, and a tap that opens that film's page. Polling interval requested:
5 minutes.

#### How "new" is decided

The source is the catalogue search endpoint the request named:

```
GET /v2/films/search?include=files,paid,tags,genres,holder.logo
                    &_l=uz&_f=json&t=<epoch ms>&sort=-updated_at&page=1
```

Verified against the live server before writing any code:

- It answers **without an `Authorization` header** (HTTP 200, ~168 KB, 20 rows,
  `_meta.totalCount` 5181). The poller therefore does not read `auth_token`,
  which matters because it also runs from a background isolate.
- **`sort=-updated_at` is not `sort=-publish_time`.** In the sample response
  `Ulfatlar Tailandda` sat third with `publish_time` 1737620268 but
  `updated_at` 1787121181 — an old film that had just been edited. So the
  newest *publication* is not necessarily row 1, and the whole page has to be
  scanned rather than only its head.
- `type` is a bare integer here (it is an object only on
  `/v2/films/{id}?include=type`). Confirmed by fetching three films:
  **1 = Serial, 2 = Film, 5 = Multfilm.** Anything else is simply omitted from
  the notification text.

The rule is one number in `SharedPreferences`, `new_content_last_publish_time`:
every row with `status == 1` and `publish_time > lastSeen` is new, and the
maximum `publish_time` on the page is stored afterwards. **The first run stores
the baseline and notifies nothing** — otherwise installing the app would fire a
burst of notifications for a catalogue the user has never seen. At most five
notifications are posted per check; rows beyond that are still marked as seen,
because a 20-film batch import must not produce 20 notifications.

#### Scheduling: a timer *and* an alarm

| Path | Runs when | Where |
| --- | --- | --- |
| `Timer.periodic(5 min)` | the app process is alive | main isolate |
| `AndroidAlarmManager.periodic(5 min)` | always, including after the process is killed | its own background isolate |

Both call the same `NewContentService.checkOnce()`, which never throws — neither
caller has a screen to report an error on.

The alarm is deliberately **inexact** (`exact: false`). An exact alarm needs
`SCHEDULE_EXACT_ALARM`, which Android 14 denies by default and which would have
to be begged for in a separate system screen. The price is jitter, and it was
measured rather than assumed: the alarm registered at **13:52:35** fired at
**14:01:20** — the 5-minute period plus the `window=+3m45s` the platform
attaches to an inexact repeat, plus app-standby deferral. `repeatInterval=300000`
and `type=RTC_WAKEUP` are visible in `dumpsys alarm`. Under Doze the gap will be
larger still. Closing that gap needs a server push (FCM); there is no
client-side way around it.

#### The defect that only appears on a real device

`@pragma('vm:entry-point')` on a **static method is not enough.** The first
build registered `NewContentScheduler.alarmCallback` and the alarm fired
correctly, but the isolate died immediately:

```
E DartVM  : ERROR: To access 'package:riya_play/services/new_content_scheduler.dart::NewContentScheduler' from native code, it must be annotated.
```

The VM needs the *enclosing class* annotated too. The callback is now a
top-level function, `newContentAlarmCallback`, and the file records why. This
is invisible to `flutter analyze` and to any foreground test — only the
process-killed path exercises it.

Two smaller things the device settled as well:

- **Register the alarm before asking for the notification permission.**
  `requestNotificationsPermission()` opens the Android 13+ system dialog and the
  `await` does not return until the user answers it. With the original ordering
  a user who swiped the dialog away would never have had an alarm scheduled at
  all. Observed on the first run: the app sat on
  `GrantPermissionsActivity` and `new_content_last_publish_time` was never
  written.
- **The launcher icon cannot be the notification icon.** Android 5+ keeps only
  the alpha channel of a small notification icon, so `@mipmap/launcher_icon`
  renders as a white block. `res/drawable/ic_notification.xml` is a flat white
  vector silhouette.

#### Opening the film from the notification

There is no `BuildContext` when a notification is tapped, and often no process
either, so `lib/utils/notification_router.dart` owns a `GlobalKey<NavigatorState>`
(`appNavigatorKey`, now passed to `MaterialApp.navigatorKey`) and a one-slot
queue:

- **App alive** — the plugin calls `onDidReceiveNotificationResponse`, the
  payload (the film id as text) is parsed and the route is pushed at once.
- **App killed** — the tap launches the app;
  `NotificationService.pendingLaunchFilmId()` reads
  `getNotificationAppLaunchDetails()` in `main()` **before `runApp`**, and the id
  waits until `MainScreen`'s first frame calls `markNavigatorReady()`.

Tying the flush to `MainScreen` rather than to the navigator is deliberate: an
unauthenticated user gets `AuthScreen`, and `FilmScreen` cannot load without a
token, so nothing is pushed on top of the login screen. `markNavigatorGone()`
drops any queued id when `MainScreen` is disposed.

#### Files

| File | Change |
| --- | --- |
| `lib/services/notification_service.dart` | **new** — plugin setup, channel `riyaplay_new_content`, permission request, launch-payload read, `showNewContent` (poster fetched as `largeIcon`, failure is silent) |
| `lib/services/new_content_service.dart` | **new** — the `publish_time` comparison, the notification text, the prefs keys |
| `lib/services/new_content_scheduler.dart` | **new** — timer + alarm, `newContentAlarmCallback`, `isEnabled` / `setEnabled` / `stop` |
| `lib/utils/notification_router.dart` | **new** — `appNavigatorKey` and the tap → `FilmScreen` route |
| `lib/services/api/films_api.dart` | `getLatestPublished()`; forwarded by `api_service.dart` |
| `lib/main.dart` | init before `runApp`, `navigatorKey`, `markNavigatorReady()` and `_startNewContentWatch()` in `MainScreen`'s post-frame callback |
| `lib/screens/profile_screen.dart` | "Yangi kontent bildirishnomasi" row (Yoqilgan / O'chirilgan), and `NewContentScheduler.stop()` on logout |
| `lib/screens/error_pages.dart` | `NewContentScheduler.stop()` on its logout path too |
| `android/app/src/main/AndroidManifest.xml` | `RECEIVE_BOOT_COMPLETED`, plus the plugin's `AlarmService` / `AlarmBroadcastReceiver` / `RebootBroadcastReceiver` — the plugin does **not** declare them itself |
| `android/app/src/main/res/drawable/ic_notification.xml` | **new** — status-bar silhouette |
| `android/settings.gradle.kts` | AGP `8.11.1` → `8.12.1`, the minimum `android_alarm_manager_plus` 5.x accepts |
| `pubspec.yaml` | `flutter_local_notifications ^22.3.0`, `android_alarm_manager_plus ^5.1.1` (`timezone` comes in transitively) |

#### Tests performed (debug build, SM-A556E, Android 16)

| Test | Result |
| --- | --- |
| First launch after install | **PASS.** No notification; `new_content_last_publish_time` written as `1787123287`, the page's real maximum |
| Rewind the pref to `1787114000`, relaunch | **PASS.** Exactly four notifications, one per film published after that instant, each "Yangi kontent mavjud" over e.g. `Karantindagi qiz (2026) · Film · Triller, Dramma`, with its poster as the large icon and grouped under one "Riya Play" header |
| Tap with the process **killed** (`am kill`, confirmed gone from `ps`) | **PASS.** Cold start landed directly on `FilmScreen` for `Karantindagi qiz` (id 17549) |
| Tap with the app **running** | **PASS.** `Qirolning xos soxchisi` (id 17547) opened; the tapped notification auto-cancelled, the others stayed |
| Background alarm with the process killed | **PASS.** `AlarmService started!` at 14:01:22, `Yangi kontent: 4 ta, 4 ta bildirishnoma`, and the pref advanced `1787110000 → 1787123287` without the app ever being opened |
| Profil toggle → "O'chirilgan" | **PASS.** `new_content_notifications_enabled=false` and no live `riyaplay.debug` alarm left in `dumpsys alarm` |
| Profil toggle → "Yoqilgan" | **PASS.** Alarm back, `origWhen=14:11:05 repeatInterval=300000` |
| Merged manifest | **PASS.** All three plugin components and `RECEIVE_BOOT_COMPLETED` present in `processDebugMainManifest/AndroidManifest.xml` |
| `flutter analyze lib` | 5 pre-existing infos, the unchanged baseline |

Not tested *at the time*: behaviour after a real reboot, Doze-deferred timing
overnight, and the whole feature on a release build. The reboot and the
release build were both covered on **2026-08-22** and passed — see that
session. Doze timing is still unmeasured.

### Session of 2026-08-19, part 2 — the bottom-inset sweep

The open item at the top of "Next Recommended Step": `FilmScreen` and
`FilmsFullScreen` were fixed on 2026-08-17, but the other pushed routes had
never been checked. Every one of them was read and then scrolled to its end on
the device.

Four had the defect. The recipe is the one part 7 used for the catalog grid —
the space goes **inside** the scrollable, so content still passes behind the
navigation bar while the last row stays reachable:

| File | Change |
| --- | --- |
| `lib/screens/actor_films_screen.dart` | trailing `SliverToBoxAdapter` spacer of `viewPadding.bottom` |
| `lib/screens/genres_films_screen.dart` | same |
| `lib/screens/genres_screen.dart` | same |
| `lib/screens/download_screen.dart` | body `Padding` bottom `AppSpacing.lg` → `AppSpacing.lg + viewPadding.bottom` |

`download_screen` is the deliberate exception to "inside the scrollable": it has
an opaque scaffold background and an `AppBar`, so there is nothing to see
through the navigation bar and letting a task card slide under it buys nothing.

Five screens already handled it and were left alone — **the sweep is not a
licence to add padding everywhere**:

| Screen | Why nothing was changed |
| --- | --- |
| `recommended_films_screen`, `categories_screen`, `profile/devices_screen`, `profile/profile_details_screen` | wrapped in `SafeArea`, whose default `bottom: true` already reserves the inset |
| `latestviewed_screen`, `profile/history_screen`, `favorites_screen` | already pad with `MediaQuery.viewPadding.bottom` |
| `profile/activate_tv_screen` | a full-screen camera `Stack`; nothing is anchored to the bottom |
| `tv_channels_screen` | a **tab**, not covered by part 7, so it was checked anyway — the last row of the "Ilmiy" category ends well clear of the glass menu |

#### Verified on device (debug build)

| Screen | Last item at the end of the scroll |
| --- | --- |
| Janrlar (`genres_screen`) | "Реальное ТВ" card fully visible above the navigation bar |
| Janr → Klassik (`genres_films_screen`) | the "Barcha filmlar ko'rsatildi" footer fully visible |
| Aktyor → So Xyon-u (`actor_films_screen`) | "Mening ismim Ro Gi…" card with its year line, clear of the bar |
| Yuklab olish, 10 tasks (`download_screen`) | "Qotillar do'koni (1-fasl, 1-qism)" with its "Bekor qilish" button, clear |
| TV → Ilmiy (`tv_channels_screen`) | "Renessans_TV" / "Hayot TV" clear of the glass menu — unchanged, as expected |

**How the download queue was filled without spending any mobile data**: turn
"Faqat Wi-Fi orqali" **on** while the device is on 4G, then queue a whole series
(`Qotillar do'koni`, "Barcha fasllar (2 ta)", 240p). All ten tasks sit at
"Wi-Fi kutilmoqda" and not a byte is transferred. Cleanup afterwards is
"Bekor qilish" on each card — cancelled counts as `isFinished`, so "Tozalash"
then removes them — and the toggle goes back off. Worth reusing for any
queue-rendering question.

`flutter analyze lib`: 5 pre-existing infos, the unchanged baseline.

### Session of 2026-08-20 — grid density everywhere, and two scanner defects

Three reported defects, all reproduced and fixed.

#### 1. The 2x2 / 3x3 setting reached only three surfaces

Deliberate when the setting shipped — the request had named the home rows,
Katalog and Sevimlilar — but every other poster grid hard-coded
`crossAxisCount: 2`, so Tavsiya etilganlar, a genre's inner page (Jangari and
the rest), Premyeralar, Doramalar and the other category pages ignored the
choice entirely.

Five files now read `GridDensityProvider.columns`, exactly as Katalog does:

| File | Surface |
| --- | --- |
| `lib/screens/recommended_films_screen.dart` | Tavsiya etilganlar |
| `lib/screens/genres_films_screen.dart` | a genre's films (Jangari, Dramma, …) |
| `lib/screens/categories_screen.dart` | Premyeralar, Doramalar, Xorij kino tarjimalar, every category |
| `lib/screens/actor_films_screen.dart` | an actor's films |
| `lib/screens/profile/history_screen.dart` | Ko'rishlar tarixi |

The picker's own subtitle said "Bosh sahifa, Katalog va Sevimlilar uchun",
which is now false; it reads "Muqovali barcha ro'yxatlar uchun".

#### 2. The camera error stayed on screen after the permission was granted

`MobileScanner` was built on the very first frame, racing the permission
request: the camera failed with a permission error, `errorBuilder` drew
"Kamera xatosi: …", and nothing ever restarted the scanner once the user
granted the permission. Re-entering the screen looked fine only because the
permission was already granted by then.

The scanner is now gated on `_permissionChecked`, which
`_requestCameraPermission` sets after a granted answer, and a spinner fills the
gap. The same flag gates the scan frame and the torch button, so they cannot
float over an empty screen.

#### 3. The torch icon never changed

`controller.torchEnabled` in `mobile_scanner` 6.0.10 is a **`final`
constructor field** — the initial value, not live state. `toggleTorch()` does
not touch it, so the icon read `flash_off` with the torch lit. The live value
is `controller.value.torchState`; the button is now a
`ValueListenableBuilder<MobileScannerState>` over the controller (which is a
`ValueNotifier`), and the manual `setState` after `toggleTorch()` is gone. The
icon is grey when off and yellow when on.

#### Verified on device (debug build, SM-A556E)

| Test | Result |
| --- | --- |
| Profil → 3x3, then a category page (Xorij kino tarjimalar) | **PASS.** Three columns |
| Genre inner page (Jangari) | **PASS.** Three columns |
| Tavsiya etilganlar | **PASS.** Three columns |
| Camera permission revoked (`pm revoke … CAMERA`), first entry | **PASS.** Spinner, then the system dialog; **no** error text |
| Granting the permission | **PASS.** The preview starts at once, without leaving the screen |
| Torch on | **PASS.** Yellow `flash_on`, scene visibly lit |
| Torch off | **PASS.** Grey `flash_off` |

`flutter analyze lib`: 5 pre-existing infos, the unchanged baseline.

### Session of 2026-08-19, part 5 — v1.0.8 froze on the splash screen

Reported after the release went out: the published v1.0.8 never got past the
splash. Reproduced immediately on a release build installed from this tree, and
it is the first defect in this project that **only** a release APK can show.

#### The cause

`res/drawable/ic_notification.xml` is named nowhere except a Dart string, the
one passed to `AndroidInitializationSettings`. The release build runs
`isShrinkResources = true`, the resource shrinker sees no Java, Kotlin or XML
reference, and removes it. `flutter_local_notifications` then fails:

```
E flutter : Unhandled Exception: PlatformException(invalid_icon,
            The resource ic_notification could not be found. …)
E flutter : #3  NotificationService.init (…/notification_service.dart:43)
E flutter : #4  main (…/main.dart:65)
```

`NotificationService.init` is **awaited in `main()` before `runApp`**, so the
unhandled exception meant the first frame was never drawn and
`FlutterNativeSplash.remove()` — which lives in `_RiyaPlayAppState` — never ran.
The native splash therefore stayed up forever. `SurfaceFlinger` was still
compositing `Splash Screen uz.mrlg.riyaplay` a full minute after launch.

Debug builds do not shrink resources, which is why every test in parts 1–4
passed. This is the same shape as the `assert`-only poster bug from part 3: a
release-mode-only transform, invisible to `flutter analyze` and to any debug run.

#### The fix — two halves

| File | Change |
| --- | --- |
| `android/app/src/main/res/raw/keep.xml` | **new** — `tools:keep="@drawable/ic_notification"` pins the drawable through the shrinker |
| `lib/main.dart` | the whole notification block is wrapped, so no plugin failure on that path can hold the splash again |

The guard matters more than the pin. Anything awaited before `runApp` that
throws bricks the app completely, and a missing notification channel is a far
smaller loss than a blank screen — the catalogue, player and downloads do not
depend on it.

#### A second defect, found while verifying the first

With the splash gone, the app landed on `ServerErrorPage` reading
"Kutilmagan xatolik yuz berdi" with no way forward. The release install's
`auth_token` (restored onto a fresh install by Android auto-backup) was stale
and the API answered **401** — but the user could not tell, and the page's
`Chiqish` button only appears for 401/403.

Eight API methods were turning a `success: false` map into
`throw Exception(response['error'])`, which discards `statusCode`. They now
throw `ApiErrorHandler.fromResponse`, and `index_screen._fetchData` passes the
recovered status to `setGlobalError` instead of a hardcoded `null`.

Diagnosing it needed instrumentation: `appLogger` is `Level.nothing` under
`kReleaseMode`, so a temporary `debugPrint` was added, read
(`DIAG throw So'ngi ko'rilganlar…: Exception: Xatolik: 401`) and removed.

#### Verified on device (release build, arm64, SM-A556E)

| Test | Result |
| --- | --- |
| Cold start | **PASS.** Login screen in ~7 s, **zero** `E/flutter` lines |
| Splash | **PASS.** Removed on the first frame; no lingering `Splash Screen` layer |
| `ic_notification` in the APK | **PASS.** Present in the shrunk resource table |
| Stale session | **PASS.** "Xato kodi: 401" with `Chiqish`, which recovers to the login screen |

**Not verified: the catalogue home itself.** Reaching it needs a valid session,
and logging in requires the owner's phone number and SMS code.

#### Republished without a version bump, at the owner's instruction

`v1.0.8` keeps `1.0.8+9` → `1009 / 2009 / 4009`; all three assets were replaced
with `gh release upload --clobber` at 15:03 UTC. The arm64 asset's digest went
`88fcbd50…55a9` → `1caf6985…6c6b`, matching the local `sha256sum`.

**Consequence to remember: a device already carrying the broken v1.0.8 will not
be offered this build.** The OTA check compares versions, and the version did
not change. Those installs need a manual reinstall, or a `v1.0.9` bump.

### Session of 2026-08-19, part 4 — the six remaining Medium/Low items

Every open item on the Medium/Low list except the release-build repeats was
closed in one pass. Five needed code, two needed the device, and one overturned
a claim this document had carried since 2026-08-13.

#### 1. Segment concurrency at 48 — measured at last

Raised from 24 by the owner's decision on 2026-08-16 and never re-measured. Run
on the same device, on **mobile data (4G+)** at the owner's explicit choice
(Wi-Fi was off), downloading the same reference episode used before:
`Kalmar o'yini (1-fasl, 5-qism)` at 720p.

```
Yuklash profili: jami 41.0s, 448.0 MB
  tarmoq  39.2s (96%) -> 11.44 MB/s
  deshifr 0.0s (0%)
  yozish  1.1s (3%)
  saqlash 0.7s (2%)
  haqiqiy tezlik 10.94 MB/s
```

| Concurrency | Effective | Network-only | Stability |
| --- | --- | --- | --- |
| 10 | 5.55 MB/s | — | — |
| 24 | 9.11 MB/s | — | no restart |
| **48** | **10.94 MB/s** | 11.44 MB/s | **no restart** — same pid (29594) before, during and after |

The 2026-08-13 restart that made 48 suspect did **not** reproduce: the process
survived the whole transfer, and `Stop FGS timeout` on `DownloadService` at the
end is the normal service teardown. The written file is **436,429,687 bytes** —
byte-for-byte the size of the clean 2026-08-13 download of the same episode, so
nothing was lost at the higher concurrency. 48 stays.

Caveat worth keeping: on 4G+ the network leg is 96 % of wall time, so this
measures a mobile link as much as the CDN. It does not follow that 96 would be
better; it follows that 48 is not worse than 24 and does not destabilise the app.

**Test artefact left on the device**: `/sdcard/Movies/RiyaPlay/Kalmar o'yini
(1-fasl, 5-qism) (1).mp4`, a 436 MB duplicate of the file already there.

#### 2. `getFirstEpisode` fallback — exercised by ablation

The branch only runs for a film whose payload has no usable `lastSeries.track`,
and **no such film exists in the catalogue**: 170 films were probed directly
(the 20 most recently updated plus the 150 oldest by `publish_time`) and every
one came back with a populated `lastSeries` and a non-empty `track`.

So the field was ablated instead: `_playSingleFilm` was patched to read an empty
`lastSeries`, a debug build was installed, and `Karantindagi qiz` was opened.
"Ko'rishni boshlash" produced the player chooser (not "Film uchun video mavjud
emas"), and the internal player played the film. The endpoint behind it answers
correctly on its own too:

```
GET /v1/series?filter[film_id]=17549&per-page=1&include=track   -> 200
{"data":[{"id":195946, ... }]}   + track[0].stream_url
```

The ablation was reverted with `git checkout --` and a clean debug build
reinstalled.

#### 3. `ApiErrorHandler` in the screens that still printed `$e`

Fourteen files. The rule applied: a **user-visible** string never interpolates
the raw exception; `appLogger` calls keep it, because that is where it belongs.

The highest-leverage change is `lib/utils/pagination_controller.dart` — every
infinite-scroll screen renders its `error` field, so one line covers all of
them. `index_screen`'s `_fetchData` is the second funnel: it is the single place
where both `success: false` payloads and thrown exceptions become the provider's
error string, so classification moved in there and the widgets that used to
prefix `"Xato: $error"` now render the message as-is.

`ApiErrorHandler._fromStatus` became public as `fromStatus`, because
`sendRequest` never throws — a caller reading its map has a status code and no
exception to hand to `handle`.

Two sites deliberately do **not** go through the handler: launching an external
player via `AndroidIntent` (`video_launcher`, `tv_channels_screen`) is not an API
failure, and the intent error's `toString()` tells the user nothing, so they
carry a fixed sentence. One site gained an `ErrorInfo` throw instead — the
"stream URL missing" case in `tv_channels_screen`, since `handle` returns an
`ErrorInfo` unchanged and the specific wording survives.

#### 4. SHA-256 for the OTA download

`ota_update`'s `execute` already accepts `sha256checksum`, and
`OtaStatus.CHECKSUM_ERROR` was already handled in `_onEvent` — the checksum was
simply never supplied.

**No second asset is needed.** The GitHub releases API returns the digest on the
asset itself:

```json
"name": "app-arm64-v8a-release.apk",
"digest": "sha256:88fcbd50d9d166d78639d4e2b1d600abf44b7a45cd1898c3cdfad1f3d31055a9"
```

Verified against the local build: `sha256sum` of
`app-arm64-v8a-release.apk` is exactly `88fcbd50…55a9`. `_pickApk` now strips the
`sha256:` prefix into `_ApkAsset.sha256`, `UpdateInfo` carries it, and
`_download()` passes it. The **atom fallback leaves it null** — that path has no
asset list at all — and null means "no verification", which is the previous
behaviour, not a regression.

Not yet exercised at runtime: it needs a release newer than the installed one,
so it will be proved by the next OTA test.

#### 5. TV channels after the disposal change — SpecUZ

Source switched to **SpecUZ** as requested (143 channels), channel
`Кинопремьера`, internal player, ~25 s each, three open → Back cycles:

| Point | Java Heap | Native Heap | TOTAL PSS |
| --- | --- | --- | --- |
| before any playback | 14.5 MB | 97.6 MB | 927 MB |
| after cycle 1 | 31.1 MB | 115.6 MB | 1079 MB |
| after cycle 2 | 30.6 MB | 112.1 MB | 982 MB |
| after cycle 3 | 29.2 MB | 121.1 MB | 1077 MB |
| settled | 31.0 MB | 108.5 MB | 1052 MB |

Bounded — it rises once for the first player and then oscillates. The Bug 17
leak was ~155 MB **per session** and monotonic, so it is not present on the live
path. The app stayed on `MainActivity` throughout.

#### 6. `tplaytv` backport — and a payload claim this document had wrong

Ported into `D:\Android\Projects\tplaytv`:

| File | Change |
| --- | --- |
| `lib/utils/latest_viewed.dart` | **new** — `latestViewedEpisodeId` / `FilmId` / `Seconds` / `Duration` / `Progress` |
| `lib/screens/video_player_screen.dart` | 30 s periodic sync driven off `progress`, a write on `pause`, de-duplication (`_lastSyncedSeconds` / `_writingSeconds`), `_minSavedSeconds = 5`, and a `_finishHandled` guard with `Navigator.canPop` |
| `lib/widgets/index/index_sections.dart`, `lib/screens/latestviewed_screen.dart` | progress from `latestViewedProgress(item)` instead of `film['playback_time'] ?? 1` |
| `lib/services/api_service.dart` + the screen's own `fields` | `duration` added to both `fields` lists |

`flutter analyze lib` in tplaytv: **No issues found**. Not exercised on a TV
device — only the phone was attached.

**The correction.** "Important Discoveries" #3 said `film.playback_time` does
not exist in the latest-viewed payload and that the item's own `duration` must
be used. Measured against the live API on 2026-08-19, **both exist**, and which
one arrives depends on the request:

| Request | `duration` (item, seconds) | `film.playback_time` (minutes) |
| --- | --- | --- |
| no `fields` parameter | **6585** | **110** |
| `fields=` the app's usual list | absent | **110** |
| `fields=duration,…` | **6585** | **110** |

`fields` prunes top-level item keys but not included relations, which is why
`playback_time` survives every variant. Both apps' `fields` lists omitted
`duration`, so riya_play has in fact been running on its `playback_time * 60`
fallback all along — correct, just rounded to the minute. tplaytv's real defect
was never the field choice: it was the `?? 1` fallback, which turns the
denominator into 60 seconds whenever the field is missing and paints a full bar
for any position past a minute.

`duration` is now requested in tplaytv so the exact value is used. riya_play was
left alone here — it is outside what was asked, and its fallback is correct.

### Session of 2026-08-19, part 3 — the debug-only broken posters, explained

The open item at the top of the Medium/Low list, carried since 2026-08-13 with
**root cause UNKNOWN**: in a debug build the Katalog and Sevimlilar grids draw
`Icons.broken_image` instead of the artwork, while the release build renders it.
Re-confirmed on 2026-08-18 in both grid densities, so it was never a
grid-density regression.

**Cause: an `assert` that only exists in debug.** `PosterCard` asks for a
disk-cache resize while handing `CachedNetworkImage` a cache manager that cannot
do one:

```dart
// lib/widgets/poster_card.dart
cacheManager: filmImagesCacheManager,   // a plain CacheManager
maxWidthDiskCache: 300,
maxHeightDiskCache: 400,
```

`cached_network_image-3.4.1/lib/src/image_provider/_image_loader.dart:89`:

```dart
assert(
    cacheManager is ImageCacheManager ||
        (maxWidth == null && maxHeight == null),
    'To resize the image with a CacheManager the '
    'CacheManager needs to be an ImageCacheManager. maxWidth and '
    'maxHeight will be ignored when a normal CacheManager is used.');
```

`filmImagesCacheManager` (`lib/utils/image_cache_manager.dart`) is
`CacheManager(Config(...))`. Only `DefaultCacheManager` carries the mixin
(`class DefaultCacheManager extends CacheManager with ImageCacheManager`).

So in **debug** the assertion throws, the surrounding `on Object catch` turns it
into `yield* Stream.error(...)`, and every tile falls through to
`PosterCard`'s `errorWidget` — the broken-image icon. In **release** asserts are
stripped, the same code takes the `getFileStream` branch, and the image loads.
The resize parameters have therefore **never** done anything in a shipped build.

**Two call sites had it**, not one:

| File | What it asked for |
| --- | --- |
| `lib/widgets/poster_card.dart` | `300 × 400` — used by Katalog, Sevimlilar, `recommended_films_screen`, `genres_films_screen`, `categories_screen`, `profile/history_screen` |
| `lib/screens/genres_screen.dart` | `600 × 300` for the genre cover images — never reported, but the same construct and therefore the same failure |

**Fix: both pairs of parameters removed.** Making `filmImagesCacheManager` an
`ImageCacheManager` was the other option and was rejected: `_resizeImageFile`
writes the resized bytes back as **PNG** while keeping the original extension
(`image_cache_manager.dart:98`), so a ~20 KB JPEG poster would be re-stored as a
few hundred KB, twice over (original + resized), against
`maxNrOfCacheObjects: 300`. Dropping the parameters changes release behaviour by
nothing at all — they were already inert there — and makes debug match it.
`memCacheWidth` is the cheap way to bound decoded size if that is ever wanted;
it uses `ResizeImage` and needs no special cache manager.

**Verified on device** (debug build, SM-A556E, rebuilt and reinstalled):

| Screen | Result |
| --- | --- |
| Katalog grid | **PASS.** Karantindagi qiz, Akal boysunmas, Ulfatlar Tailandda, Qirolning xos soxchisi all render |
| Sevimlilar grid | **PASS.** Olov pazanda, Qashqirlar Makoni, Anakonda, Yomonlik dunyoga ustun bo'lolmas all render |
| Janrlar (`genres_screen`) | **PASS.** Jangari / Dramma / Klassik cover collages all render |

`flutter analyze lib`: 5 pre-existing infos, the unchanged baseline.

### Session of 2026-08-17 — the release-build repeat, and navigation-bar insets

Started from the previous "Next Recommended Step": repeat the watch-position
reproduction on a **release** build. Two things had changed since that step was
written, both verified before doing anything:

- The device's release install was already `versionCode=2005 / versionName=1.0.4`
  (installed 2026-08-17 13:48), i.e. `v1.0.4` was built and installed locally
  after the part-4 work. It predates commit `161d193` (the glass dialogs), so the
  tree was rebuilt anyway rather than trusting the installed binary.
- The three fixes the test exists to exercise are all present in the working
  tree: `video_helpers.dart` `dispose(forceDispose: true)` (Bug 17),
  `_maybeSyncPosition` not stamping `_lastSyncAt` below `_minSavedSeconds`
  (Bug 18), and `_savePlaybackPosition` without `mounted`/`_isDisposed` guards
  (Bug 13).

**Build the arm64 split, not the universal APK.** `flutter build apk --release`
produces `versionCode = 5` (no ABI offset), which is *lower* than the installed
`2005`, so `adb install -r` fails with `INSTALL_FAILED_VERSION_DOWNGRADE`. The
command that works:

```
flutter build apk --release --split-per-abi --target-platform android-arm64
adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

#### Results on `uz.mrlg.riyaplay` (release, 1.0.4 / 2005, built from `161d193`)

| Test | Result |
| --- | --- |
| New film (Catalog → "Haydi", button read "Ko'rishni boshlash", i.e. no prior position) → internal player → ~90 s → **Android Back without pausing** | **PASS.** Back returned to the film page, no crash |
| Continue-watching row after that | **PASS.** "Haydi" appears **first** with **01:29** — the exit write landed with the real position, not `00:00` and not a 30-s-stale value |
| Tap that card | **PASS.** "01:29 dan davom ettirishni xohlaysizmi?" resume dialog, rendered on the glass surface |
| 4 × (resume → ~25 s → Back), Java heap after each | 139 → 140 → 166 → **95 MB**. Bounded; GC reclaims it. The Bug 17 leak was ~155 MB *per session* and would have grown monotonically |
| App state at the end | alive, focus back on `MainActivity` |

**Server truth could not be read for this account.** The release package is not
debuggable, so its `auth_token` is unreachable; the token that *is* readable
(`run-as uz.mrlg.riyaplay.debug`) belongs to a **different account** — its
`/v2/films/latest-viewed` never showed "Haydi" and did not change during the
test. The verification above is therefore through the UI, which is itself
server-rendered: the continue-watching row is built from the API response, so a
card reading `01:29` *is* evidence the write reached the server.

#### `android/app/local.properties` deleted

An untracked `android/app/local.properties` contained a placeholder
`flutter.sdk=C:\path\to\flutter` plus stale `minSdk/targetSdk/compileSdk` lines.
Nothing reads it — `build.gradle.kts` reads `android/local.properties`, one
directory up — so it was pure noise in `git status` and misleading to anyone
opening it. Deleted at the owner's request; `git status` is now clean.

#### Content ran under the system navigation bar on two screens

Reported: on `FilmScreen` and `FilmsFullScreen` the last content sits under the
navigation bar ("Olov pazanda"'s synopsis, and "Kalmar o'yini"'s **"Barcha
qismlar"** button).

Same cause as part 7's home/catalog/profile fix, one level down: the app runs
`SystemUiMode.edgeToEdge`, both screens draw to the bottom of the window, and
neither scrollable reserved the navigation-bar inset.

| File | Change |
| --- | --- |
| `lib/screens/film_screen.dart` | `SingleChildScrollView.padding` bottom = `MediaQuery.viewPadding.bottom` |
| `lib/screens/films_full_screen.dart` | grid padding `EdgeInsets.all(16)` → `fromLTRB(16, 16, 16, 16 + viewPadding.bottom)` |

**A second defect surfaced while verifying it**: the episode strip on
`FilmScreen` rendered `BOTTOM OVERFLOWED BY 8.0 PIXELS` over every card. The
card is 100 px of thumbnail plus title (up to two lines) and duration inside a
fixed **136 px** box. The height is now the single constant
`_episodeCardHeight = 160`, shared by the card, the horizontal `ListView` that
holds it and the skeleton loader (all three were hard-coding 136 separately),
and the text block is wrapped in `Expanded` so a larger system font scale
cannot overflow it either.

**Verified on device** (debug build, so the overflow banner would still be
visible if it were there): "Olov pazanda" scrolls to its last line clear of the
navigation bar; "Kalmar o'yini" shows "Barcha qismlar" clear of it, with the
strip's durations (`55:29`, `58:08`) now visible and **no** overflow banner;
`FilmsFullScreen`'s grid ends with "9-qism 50:58" clear of the bar.

`flutter analyze lib`: 5 pre-existing infos, the unchanged baseline.

### Session of 2026-08-18 — card captions and a 2x2 / 3x3 grid setting

Three requests, all verified on the device (debug build) before committing.

#### 1. Continue-watching cards on the home screen name what they are

`LatestViewedItem` was a bare thumbnail with a time badge — nothing said which
film it belonged to. The card is now a `Column`: 120 px of artwork, then the
title and the year. For a series the episode is appended and **never** clipped:

```
Kalmar o'yini | 1-qism        Klon
2021                          2021
```

The row is a `Row` of `Flexible(title)` + the episode label, so a long series
name ellipsises while `| 3-qism` stays visible. A record counts as an episode
when its own `name_uz` is non-empty and differs from the film's name — the
latest-viewed payload already carries both (`latestViewedFields`).

#### 2 and 3. Poster density is a setting: 2x2 or 3x3

New `lib/utils/grid_density.dart` — `GridDensityProvider`, a `ChangeNotifier`
persisted in `SharedPreferences` under `grid_columns`, allowed values `2` and
`3`. It is loaded in `main()` **before** `runApp`, otherwise the first frame
draws two columns and then jumps to three.

| Surface | What reads it |
| --- | --- |
| Home: "Sizga tavsiya qilamiz", every category row | `itemWidth = (width - padding - gaps) / columns` |
| Katalog grid | `crossAxisCount` |
| Sevimlilar grid | `crossAxisCount` |
| `PosterGridSkeleton` | `crossAxisCount` — otherwise the skeleton and the real grid disagree and the cards jump when loading ends |

The picker lives in Profil ("Muqovalar ko'rinishi", with the current value on
the right) and opens a glass bottom sheet with the two options, each drawn with
a small live grid preview. Switching takes effect immediately — `Provider`
rebuilds every listening screen, no restart.

**Verified on device**: 2x2 → 3x3 put three posters in each home row, the
Katalog and Sevimlilar grids both moved to three columns, and switching back to
2x2 restored two. The continue-watching captions read as above.

**Not caused by this change**: in the debug build the Katalog and Sevimlilar
posters render as broken-image icons in *both* densities. That is the
pre-existing debug-only poster defect already tracked in Remaining Bugs; the
release build renders them.

#### Releases and the GitHub outage

| Tag | Version | versionCode (v7a / arm64 / x86_64) | Published (UTC) | Contents |
| --- | --- | --- | --- | --- |
| `v1.0.5` | `1.0.5+6` | 1006 / 2006 / 4006 | 2026-08-17 13:25 | navigation-bar insets, episode-card overflow |
| `v1.0.6` | `1.0.6+7` | 1007 / 2007 / 4007 | 2026-08-18 06:05 | one-card continue-watching update, release-notes scrollbar |
| `v1.0.7` | `1.0.7+8` | 1008 / 2008 / 4008 | 2026-08-18 08:34 | card captions, 2x2 / 3x3 grid density |
| `v1.0.8` | `1.0.8+9` | 1009 / 2009 / 4009 | 2026-08-19 10:06 | new-content notifications, the bottom-inset sweep, the debug poster fix — **shipped broken**, assets replaced 15:03 the same day |
| `v1.0.9` | `1.0.9+10` | 1010 / 2010 / 4010 | 2026-08-20 07:58 | the splash-freeze fix reaches everyone, grid density everywhere, the two scanner defects, 401 handling, OTA SHA-256 |

`v1.0.6` did not publish on the first two tries: `gh` returned
`HTTP 503: No server is currently available` from
`api.github.com/repos/.../releases`, and even `gh release list` failed. GitHub's
status page showed an incident (API Requests degraded from 14:58 UTC the day
before, ~20 % error rate). Nothing was wrong with the command. Two things to
remember when it happens again:

- **`gh release create` can leave an orphan draft behind.** Two failed attempts
  logged `cleaning up draft failed`, i.e. release objects `371801196` and
  `371801748` were created and could not be removed. A retry must therefore look
  for an existing `v1.0.x` release first (`gh api repos/OWNER/REPO/releases`)
  and finish it with `gh release upload --clobber` +
  `gh release edit --draft=false --latest`, rather than blindly creating another.
- The publishing tool is the GitHub CLI at `C:\Program Files\GitHub CLI\gh.exe`,
  authenticated as `d4rk73rr0r` with `repo` scope. It is **not** on `PATH` in
  this environment's shell; call it by full path.

#### "Ko'rishni davom ettirish" no longer refetches the whole list

Returning from the player used to run `_pagination.refresh()` in
`LatestViewedScreen.didPopNext`, i.e. the whole 20-item page was requested
again and the grid rebuilt from scratch, to reflect a change in **one** entry.

The playback path now updates that entry alone:

- `LatestViewedCard` awaits `VideoLauncher.playFromLatestViewed` (which already
  waits for the exit write), then reads the new position with
  `ApiService.getWatchedSeconds(episodeId)` and writes it into its own item.
- The screen moves that item to the head of the list with the new
  `PaginationController.moveToFront(test)` — the server sorts by `updated_at`,
  so the just-watched entry belongs first, and doing it locally costs no
  request.
- `_skipNextPopRefresh` makes `didPopNext` skip its full refresh for that trip.
  The long-press path (film page) still refreshes fully: a different episode
  may have been watched there, so both the times and the order can change.

Net effect per playback: one `getEpisodeDetails` request instead of a full
page fetch, no spinner, no scroll jump.

**Verified on device**, twice: `Lilining sarguzashtlari` `01:20 → 02:07` with
the scroll position and every other card untouched; then `Klon` `23:24 → 24:11`
moving from 4th place to 1st while the remaining cards kept their relative
order.

#### The update dialog's release notes got a scrollbar and a fade

The notes were always scrollable (`ConstrainedBox(maxHeight: 160)` +
`SingleChildScrollView`), but nothing said so, so a long body read as
truncated. `_ReleaseNotes` now adds `Scrollbar(thumbVisibility: true)` and a
28 px bottom fade that is drawn only while `extentAfter > 4`. Verified on
device against the real `v1.0.5` notes: the bar is visible, and scrolling to
the end removes the fade and shows the last line in full.

#### Version bumped to `1.0.5+6`

`v1.0.4` turned out to be **published already** (to `d4rk73rr0r/rplay-releases`,
2026-08-17 06:28 UTC, all three split APKs) — the Remaining Work row calling it
"not started" was stale. The next release therefore has to clear it, so
`pubspec.yaml` is now `1.0.5+6`: with Flutter's ABI offsets that is
`armeabi-v7a 1006`, `arm64-v8a 2006`, `x86_64 4006`, verified with
`aapt dump badging` on all three built APKs. The device's install is
`1.0.4 / 2005`, so `2006` clears it by one.

The three release APKs happen to have byte counts identical to the published
`v1.0.4` assets (47,380,622 / 57,514,164 / 51,296,132). As established earlier
in this document, **equal asset sizes are not evidence of an identical build** —
`aapt` reports different versions for these.

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

### Session of 2026-08-16, part 8 — every dialog on the same glass surface

The glass recipe moved into `lib/theme/glass.dart` (`GlassSurface`) so the
bottom menu and every dialog read from one place instead of drifting apart:
dark scrim `0.70 → 0.58`, white hairline `0.18` at `0.8` px, radius 28. The
values and the reasoning behind "dark, not light" live in that file's doc
comment; `GlassBottomBar` now consumes them rather than hard-coding its own.

**Dialogs go through the theme**, not per-call-site widgets:
`MaterialApp.theme.dialogTheme = GlassSurface.dialogTheme`. Six sites were
overriding `backgroundColor` / `shape` locally and would have ignored it — the
overrides were removed so the theme wins:

| File | what was removed |
| --- | --- |
| `screens/auth_screen.dart` | `shape` + `backgroundColor: Colors.black` |
| `screens/profile_screen.dart` | `backgroundColor: cardColor` + `shape` |
| `screens/profile/activate_tv_screen.dart` | theme-conditional `backgroundColor` + `shape` |
| `services/update_service.dart` (×2) | `backgroundColor: cardColor` + `shape` |
| `screens/profile/activate_tv_screen.dart` (raw `Dialog`) | opaque `Container` decoration → `GlassSurface` |

Everything else (`video_launcher.dart` ×4, `films_full_screen.dart` ×3,
`tv_channels_screen.dart`) set nothing and picked the theme up for free.

**Bottom sheets were included too.** The five classes are literally named
`LogoutDialog`, `ClearAllDialog` (×3) and `EditProfileDialog`, so they count as
dialogs. `bottomSheetTheme` makes the sheet itself transparent and each widget's
own `Container` now carries `GlassSurface.gradient` / `sheetBorderRadius` /
`sheetBorder`.

Their padding also gained `MediaQuery.viewPadding.bottom`: the sheets start
below the system navigation bar, and with a transparent surface their buttons
sat directly on top of the navigation keys.

**Verified on device**: the "Davom ettirish" resume dialog, the update
"Yangilanish tekshirilmoqda..." dialog, the Profile logout sheet and the
Favourites "Hammasini o'chirmoqchimisiz?" sheet all render as glass with
content visible behind them and buttons clear of the navigation bar. The other
dialogs share the same theme path.

**No blur here either**, for the same reason as the menu (part 7): a
`BackdropFilter` keeps the raster pipeline awake. Dialogs are transient, so the
cost would be bounded — but consistency with the menu is the point, and the
scrim alone already reads as glass.

**Note on `dart format`**: running it across `lib/` reformatted 14 files that
had nothing to do with this change. Those were reverted with
`git checkout --`. Format only the files you touched.

### Session of 2026-08-16, part 7 — blur re-measured, content runs behind the menu

#### Blur re-measurement (the part-5 question, answered)

Re-measured with `GlassBottomBar.blur = true` **after** the part-6 `TickerMode`
fix, on the same device:

| Condition | raster p50 | raster p90 | janky / 3 s | frames / 3 s |
| --- | --- | --- | --- | --- |
| Home idle, blur **off** | 3.5–3.8 ms | 4.7–5.2 ms | 0 | ~360 |
| Home idle, blur **on** | 5.7–8.0 ms | 7.0–8.6 ms | **0–19** | ~350 |
| Home scrolling, blur on | 2.4–5.5 ms | 3.6–6.4 ms | 0 | ~340 |
| **Other tab idle, blur off** | — | — | 0 | **0** |
| **Other tab idle, blur on** | 3.2–4.2 ms | 5.0–5.6 ms | 0 | **~363** |

The last two rows are decisive and were not visible before: **`BackdropFilter`
cancels the part-6 fix outright.** With the blur on, the app renders at ~120 fps
on *every* tab again, including Sevimlilar, because the filter keeps the
pipeline from ever going idle. Verified across five consecutive 3-second
windows on a tab whose own content is static.

So `blur` stays `false`, now for a second and stronger reason than the raster
cost alone.

#### Content now runs behind the menu, down to the navigation bar

**Why it did not before**: `IndexScreenContent`, `CatalogScreen` and
`ProfileScreen` each return their own `Scaffold` with `body: SafeArea(...)`.
The outer `Scaffold` reports the glass menu's height as bottom padding, so
those inner `SafeArea`s reserved exactly that strip — content stopped at the
menu's top edge and the strip below it was flat scaffold colour.

**Change**: `bottom: false` on those three `SafeArea`s, with the same height
moved *inside* the scrollable (`SingleChildScrollView.padding` for Home and
Profile, a trailing `SliverToBoxAdapter` spacer for the Catalog grid) so the
last item is still reachable. Verified by scrolling each of the three to its
end: Home's last row ("Dahshatli Hikoyalar"), Catalog's grid and Profile's
"Chiqish" + version line all clear the menu.

**Legibility follow-up.** With content behind it, the menu lands on bright
posters too, and the original white 14 %/6 % gradient made white icons vanish.
Measured by sampling the rendered pixel under the menu over a white poster:

| Panel fill | pixel under the menu |
| --- | --- |
| white 0.14 → 0.06 | washed out, icons invisible |
| black 0.38 → 0.28 | `#ABABAB` — still too light |
| **black 0.70 → 0.58** | **`#5C5C5C`** — icons read on any background |

The panel is still see-through (posters are clearly visible through it); it is
simply a dark scrim rather than a light one. Icon and label shadows
(`_navGlyphShadows`) were added along the way and kept, though on their own
they were not enough. Chosen by the project owner over enabling the blur.

**Files**: `lib/widgets/glass_bottom_bar.dart` (dark scrim),
`lib/main.dart` (glyph shadows), `lib/screens/index_screen.dart`,
`lib/screens/catalog_screen.dart`, `lib/screens/profile_screen.dart`
(`SafeArea(bottom: false)` + in-scrollable padding).

**Note**: judging this from a downscaled screenshot was misleading — the
0.38 → 0.70 change looked like it had not applied at all. Sampling the actual
pixel settled it. Do the same next time.

#### System navigation bar buttons over bright content

Same problem one level down: content also runs under the navigation bar, so
the system's white buttons landed on bright posters.

**`systemNavigationBarColor` does not work here.** Setting it to a translucent
`0xA3000000` changed nothing — under `SystemUiMode.edgeToEdge` the system
ignores the colour. Verified by sampling the same pixel across builds: with
the colour set, the navigation-bar strip was still `#C5AF58` over a yellow
poster, i.e. untouched.

**`systemNavigationBarContrastEnforced: true` does work.** The system paints
its own translucent scrim behind the bar. Measured on identical content:

| Setting | pixel in the nav-bar strip |
| --- | --- |
| contrast enforced `false` | `#C5AF58` / `#95734D` |
| contrast enforced `true` | `#766935` / `#59452E` |

That is roughly 40 % darker, enough for the white buttons. A third build with
`systemNavigationBarColor` back to `Colors.transparent` produced pixel-identical
output, confirming the flag is doing all the work and the colour is inert — so
the colour stays transparent and the comment records why.

### Session of 2026-08-16, part 6 — the idle 120 fps cause, navigation bar back, selected-only labels

Three requested changes. All measured on the same profile build and device.

#### 1. The idle ~120 fps redraw — cause found and fixed

**Root cause: the banner carousel's progress-ring `AnimationController` never
stops, and `KeepAliveWrapper` keeps it running for tabs that are off-screen.**

`_BannerCarouselState` creates a 6-second `AnimationController` and calls
`forward()`; `onPageChanged` then does `reset()` + `forward()`. Because
`autoPlayInterval` is also 6 s, the controller finishes and is immediately
restarted — it is running permanently. Any active `Ticker` makes
`SchedulerBinding` request a frame every vsync, so the whole app renders at
120 fps for as long as that controller lives.

Two measurements pinned it down:

| Condition | frames / 3 s |
| --- | --- |
| Home tab visible (before) | ~360 |
| **Katalog tab visible, Home off-screen (before)** | **~363** |
| Home tab, controller not started (ablation) | 37–100 |

The second row is the defect: the Home tab is not even visible, yet the app
still renders at full rate, because `MainScreen` wraps every tab in
`KeepAliveWrapper` and nothing disables its tickers.

**Fix**: wrap each `TabBarView` child in `TickerMode(enabled: _selectedIndex ==
index)`. Animations are not removed or slowed — they are paused while their tab
is off-screen and resume on return.

| Condition | frames / 3 s | jank |
| --- | --- | --- |
| Home visible (after) | 350–362 | 0 |
| **Katalog visible, Home off-screen (after)** | **0** | 0 |
| Home again after returning | 350–364 | 0 |

Home itself keeps rendering at 120 fps with **zero janky frames** (build p50
1.0–1.3 ms, raster p50 3.5–3.8 ms against an 8.3 ms budget) — that part was
already healthy and is deliberately unchanged: the ring is a real animation and
should run while it is on screen. What is gone is the ~120 fps burned on a
screen nobody is looking at.

#### 2. The system navigation bar is visible again

**Why it was hidden**: part 5 set `SystemUiMode.manual` with only
`SystemUiOverlay.top`, plus a `setSystemUIChangeCallback` that re-hid the bar
3 s after the user swiped it into view.

**Change**: `AppSystemUi.apply()` now uses `SystemUiMode.edgeToEdge` — both
bars visible and transparent, the app still drawing behind them. The re-hide
callback and its timer are gone. The status bar is unaffected (same overlay
style, same transparent theme colours), and the glass menu sits above the
navigation bar because it is already inside a `SafeArea`.

The player's fullscreen path still uses `applyFullscreen()`
(`immersiveSticky`) while a video is genuinely fullscreen, and
`VideoPlayerScreen.dispose()` restores through `AppSystemUi.apply()`, so
leaving the player brings both bars back.

#### 3. Glass menu: only the selected item shows its label

`BottomNavigationBar` already models exactly this, so no custom widget was
introduced: `showSelectedLabels: true` + `showUnselectedLabels: false`. The
selected section renders icon over label, every other section renders the icon
alone, and switching sections moves the label immediately.

Label size dropped 11 pt → 10 pt at the same time. The glass panel is inset
from the screen edges, so each of the five slots gets ~72 dp; "Bosh sahifa" at
11 pt overflowed its slot and was clipped by the panel's rounded corner.

**Files touched**: `lib/main.dart` (TickerMode, label flags, font size),
`lib/utils/system_ui.dart` (edgeToEdge, re-hide logic removed).

#### Tests performed

| Test | Result |
| --- | --- |
| Home rendering at 120 Hz | 350–364 frames / 3 s, **0 janky frames** |
| Off-screen tab rendering | **0 frames / 3 s** (was ~363) |
| Returning to Home | animation resumes, 350–364 frames / 3 s, 0 jank |
| Navigation bar on Home / Katalog / Profil | visible throughout |
| Navigation bar after leaving the player | visible |
| Selected section shows icon + label | yes (`Bosh sahifa`, `Katalog` both checked) |
| Unselected sections show icon only | yes |
| Rapid switching (15 taps across all five) | no stuck labels, no errors, ended clean |
| Playback resume + position write | 22:57 → 23:16, card moved to the front |
| `flutter analyze` | 5 pre-existing infos, the unchanged baseline |

`GlassBottomBar.blur` is still `false`. It was not re-measured after the
TickerMode fix — the blur cost was measured with the Home tab visible, which
is exactly the case the fix does **not** change.

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

**Release-build sweep (device, SM-A556E, Android 16, `uz.mrlg.riyaplay`
`1.0.9 / 2010`, 2026-08-22):**

| Check | Result |
| --- | --- |
| Alarm fires after `am kill` on release | **PASS** — new process started for the broadcast, `AlarmService started!` 13:29:45.318 |
| AOT resolves `newContentAlarmCallback` | **PASS** — no `DartVM … must be annotated`, no `Fatal: failed to find callback` |
| The poller actually runs in the background isolate | **PASS** — uid traffic +32,698 B rx / +1,840 B tx with no UI |
| Alarm stays armed after the isolate finishes | **PASS** — `origWhen 13:33:25.602 repeatInterval=300000` |
| `ic_notification` present in the shipped APK | **PASS** — `drawable/ic_notification` → `res/vO.xml`, 668 B, real `<vector>` |
| Notifications post on release (forced baseline) | **PASS** — 3 posted, icon `0x7f0800c7`, posters as large icons, grouped |
| Tap with the app running | **PASS** — `FilmScreen` for `O'gay ona (1973)`, tapped one auto-cancelled |
| Tap with the process killed | **PASS** — cold start onto `FilmScreen` for `Pavana (2026)` |
| Shipped APK restored afterwards | **PASS** — sha1 `40c6d008…`, equal to the recorded `.sha1` |
| Alarm survives a real reboot | **PASS** — `Rescheduling after boot!` 13:45:46.644, same `origWhen`, app never opened |
| The rescheduled alarm fires | **PASS** — `AlarmService started!` 13:50:31.974, 3m10s of inexact-window jitter |
| Memory over 4 navigation cycles | **PASS** — Java Heap 10.4 → 20.4 → 16.9 → 17.5 MB, bounded |
| `flutter analyze` after reverting the patch | 5 pre-existing infos, the unchanged baseline |

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

2. ~~**Posters do not render in debug builds.**~~ **RESOLVED (2026-08-19,
   part 3).** `PosterCard` (and `genres_screen`) passed
   `maxWidthDiskCache` / `maxHeightDiskCache` while using
   `filmImagesCacheManager`, a plain `CacheManager`. `cached_network_image`
   asserts that the manager is an `ImageCacheManager` when a resize is
   requested; the assertion throws in debug only, and the error reaches
   `errorWidget`. Both parameter pairs were removed — they were inert in
   release anyway. The API payload was correct all along, which is why
   inspecting it never explained anything.

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
| ~~Publish `v1.0.4`~~ | Built and verified locally, not uploaded | — | Medium | **DONE** | `v1.0.4` was published to `d4rk73rr0r/rplay-releases` on 2026-08-17 06:28 UTC with all three split APKs — the "not started" note above it was stale. Superseded by `v1.0.5` |
| ~~Publish `v1.0.5`~~ | — | `pubspec.yaml` | Medium | **DONE (2026-08-17)** | Published to `d4rk73rr0r/rplay-releases` at 13:25 UTC with all three split APKs (`gh release create`), and the OTA check on the device's `1.0.4 / 2005` install answered "Yangi versiya mavjud — Versiya 1.0.5 · 45.2 MB" |
| ~~Publish `v1.0.6`~~ | Carries the continue-watching single-card update and the release-notes scrollbar | `pubspec.yaml` | Medium | **DONE (2026-08-18)** | `1.0.6+7` → `1006 / 2006 / 4006`, published 06:05 UTC. The first attempts failed with `HTTP 503` during a GitHub-wide incident, not through any fault of the command — see the note in the 2026-08-18 session |
| ~~Publish `v1.0.7`~~ | Carries the card captions and the grid-density setting | `pubspec.yaml` | Medium | **DONE (2026-08-18)** | `1.0.7+8` → `1008 / 2008 / 4008`, published 08:34 UTC, Latest, all three assets `uploaded` |
| ~~Publish `v1.0.8`~~ | Carries the new-content notifications, the bottom-inset sweep and the debug poster fix | `pubspec.yaml` | Medium | **DONE (2026-08-19)** | `1.0.8+9` → `1009 / 2009 / 4009`, verified with `aapt dump badging` on all three APKs, published 10:06 UTC as Latest with every asset `uploaded`. `gh release create` succeeded on the first attempt, no orphan draft |
| The update dialog's release notes look truncated | Long notes stop mid-sentence at the bottom of the box, with no visible scrollbar or fade | `lib/services/update_service.dart` | Low | **Not a defect** | The notes already sit in `ConstrainedBox(maxHeight: 160)` + `SingleChildScrollView` and scroll fine — confirmed by hand on the `v1.0.5` dialog. Only the affordance is missing; add a `Scrollbar` or a bottom fade if it is worth it |
| **Find the idle ~120 fps redraw on the home tab** | Measured, cause not isolated; the ring animation was ruled out | `lib/screens/index_screen.dart` | Medium | Not started | DevTools timeline on a profile build while the home tab sits untouched |
| ~~**Measure memory over navigation cycles**~~ | Not covered by the audit | — | Medium | **DONE for navigation (2026-08-22)** | Four Home → Katalog → FilmScreen → Back cycles on release `1.0.9`: Java Heap 10.4 → 20.4 → 16.9 → 17.5 MB, TOTAL PSS 488 → 513 → 503 → 510 MB — bounded, non-monotonic. The player half was already measured on 2026-08-17. Only TV channels remain unmeasured over *navigation* cycles, and their playback cycles are covered by the 2026-08-19 test |
| ~~**Re-measure segment concurrency at 48**~~ | Raised from 24 by the owner's decision without a new measurement | `lib/services/download_service.dart` | Medium | **DONE (2026-08-19)** | 448 MB in 41.0 s on 4G+: **10.94 MB/s effective**, 11.44 MB/s network-only, against 9.11 MB/s at 24. No app restart, same pid throughout, and the file is byte-identical (436,429,687 B) to the clean 2026-08-13 download. 48 stays |
| **Run the install-flow tests on a release build** | Every part-2 result was measured on `uz.mrlg.riyaplay.debug` | — | Medium | Not started | Same four scenarios against `uz.mrlg.riyaplay` once a newer release exists to offer |
| ~~Decide the release asset naming~~ | — | `lib/services/update_service.dart` | Medium | **Settled** | `app-<abi>-release.apk`, the default `flutter build apk --split-per-abi` output. The atom fallback now depends on this name — renaming assets breaks it, so keep it |
| ~~Consider a checksum~~ | `ota_update` supports `sha256checksum`, which would catch a truncated or tampered download | `lib/services/update_service.dart` | Low | **DONE (2026-08-19)** | No extra asset needed — the releases API returns `"digest": "sha256:<hex>"` per asset, verified equal to the local build's `sha256sum`. `_pickApk` reads it into `_ApkAsset.sha256`, `UpdateInfo` carries it and `_download()` passes it; the atom fallback leaves it null. Runtime proof waits for the next OTA test |
| ~~Re-check 5-qism duration~~ | Possible missing tail content | — | Low | **DONE** | Clean re-download is exactly 47:01 and decodes without errors |
| ~~Investigate debug-mode poster rendering~~ | Affects development experience | `lib/widgets/poster_card.dart`, `lib/screens/genres_screen.dart` | Low | **DONE (2026-08-19)** | `maxWidthDiskCache` / `maxHeightDiskCache` with a non-`ImageCacheManager` cache manager trips a debug-only `assert` inside `cached_network_image`, and the thrown error lands in `errorWidget`. Both parameter pairs removed; Katalog, Sevimlilar and Janrlar all verified rendering on a debug build |
| ~~Route `film_screen` / `films_full_screen` playback through `VideoLauncher`~~ | Duplicated `_playVideo`, no flush wait, no refresh | `lib/screens/film_screen.dart`, `lib/screens/films_full_screen.dart`, `lib/utils/video_launcher.dart` | Medium | **DONE** | Both delegate to `VideoLauncher.playWithChooser`; verified on device |
| ~~Verify the `getFirstEpisode` fallback~~ | The new branch only runs for a film whose payload has no `lastSeries`, which no tested film had | `lib/services/api/films_api.dart`, `lib/screens/film_screen.dart` | Low | **DONE (2026-08-19)** | No such film exists — 170 probed, all had `lastSeries.track`. Verified by ablating the field in a debug build: "Ko'rishni boshlash" on `Karantindagi qiz` reached the chooser and played. Ablation reverted |
| ~~Re-test the reported scenario on a **release** build~~ | Every part-4 measurement was made on `uz.mrlg.riyaplay.debug` | — | High | **DONE (2026-08-17)** | Rebuilt from `161d193` as an arm64 split (the universal APK is `versionCode 5` and cannot be installed over `2005`), installed, and both halves passed: new film → Back without pausing wrote `01:29`, and four play/Back cycles left the Java heap bounded (139 → 140 → 166 → 95 MB) |
| ~~Re-check TV channels after the disposal change~~ | `tv_channels_screen` pushes the same player for live streams; the disposal path changed for it too | `lib/screens/tv_channels_screen.dart` | Medium | **DONE (2026-08-19)** | SpecUZ source, `Кинопремьера`, three open → ~25 s → Back cycles. Java heap 14.5 → 31.1 → 30.6 → 29.2 MB, settling at 31.0. Bounded, no monotonic growth; app stayed on `MainActivity` |
| Sessions shorter than 6 s are still not saved | `_minSavedSeconds = 5` is deliberate (an accidental open should not fill the row), but it does mean a very short first session leaves a `00:00` card | `lib/screens/video_player_screen.dart` | Low | By design | Revisit only if users complain about the empty card, not about the position |
| ~~Notify on new catalogue content~~ | Feature request: "Yangi kontent mavjud", a short summary, tap opens the film | `lib/services/notification_service.dart`, `lib/services/new_content_service.dart`, `lib/services/new_content_scheduler.dart`, `lib/utils/notification_router.dart` | High | **DONE (2026-08-19)** | 5-minute timer while alive + inexact `AndroidAlarmManager.periodic` when killed, both driven by `publish_time`. Verified on device including the process-killed path — see the 2026-08-19 session |
| ~~Test the notification feature on a **release** build~~ | Everything was measured on `uz.mrlg.riyaplay.debug`; release adds AOT, where a wrong `vm:entry-point` annotation fails differently | — | Medium | **DONE (2026-08-22)** | Whole chain verified on `uz.mrlg.riyaplay` `1.0.9 / 2010`: killed process → alarm broadcast → `AlarmService started!` with no `DartVM` error, +32,698 B of uid traffic proving the poller ran, three notifications posted with the real `ic_notification` and their posters, and both tap paths (app running, process killed) reaching the right `FilmScreen`. See the 2026-08-22 session |
| ~~Verify the alarm survives a reboot~~ | `rescheduleOnReboot: true` is set and `AlarmService: Rescheduling after boot!` was logged, but the device was never actually rebooted | `lib/services/new_content_scheduler.dart` | Low | **DONE (2026-08-22)** | Real `adb reboot`, app never opened: `Start proc … for broadcast {RebootBroadcastReceiver}` and `Rescheduling after boot!` at 13:45:46, and `dumpsys alarm` carried the same `origWhen 13:47:21.527 repeatInterval=300000` again |
| Measure the notification gap under Doze | Only the awake-device jitter is measured (5 min → ~8m45s) | — | Low | Not started | Leave the phone untouched overnight and compare the alarm's fire times |
| ~~Sweep the remaining full-screen routes for the bottom inset~~ | Only `FilmScreen` and `FilmsFullScreen` had been fixed | `actor_films_screen`, `genres_films_screen`, `genres_screen`, `download_screen` | Medium | **DONE (2026-08-19)** | Four screens fixed with the part-7 in-scrollable spacer (`download_screen` pads outside, on purpose); five others already reserved the inset via `SafeArea` or an existing `viewPadding.bottom` and were left alone; the TV tab was checked too and needs nothing. All verified by scrolling to the end on the device |
| ~~Backport to `tplaytv`~~ | That project wrote the position only on exit/`WillPop`/`finished`, and its progress bars divided by `film['playback_time'] ?? 1` | `tplaytv/lib/screens/video_player_screen.dart`, `tplaytv/lib/widgets/index/index_sections.dart`, `tplaytv/lib/screens/latestviewed_screen.dart`, `tplaytv/lib/utils/latest_viewed.dart`, `tplaytv/lib/services/api_service.dart` | Medium | **DONE (2026-08-19)** | 30 s periodic sync, a `pause` write, write de-duplication, a `_finishHandled` guard, the shared `latest_viewed.dart` helper and `duration` added to both `fields` lists. `flutter analyze lib`: no issues. **Not exercised on a TV device** — only the phone was attached. The `?? 1`, not the field choice, was the real defect; see the corrected Important Discovery #3 |
| Test the tplaytv backport on a TV device | All of it is static-analysis-clean but unrun | `tplaytv/` | Medium | Not started | Install on the Android TV box, watch ~1 minute, leave, and confirm the position and the progress bar |

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
- ~~**Wire `ApiErrorHandler` into the remaining screens.**~~ **DONE
  (2026-08-19)** — fourteen files, with `pagination_controller` and
  `index_screen._fetchData` as the two funnels that cover most screens.

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
3. **`film.playback_time` and the item's `duration` both exist** in the
   latest-viewed payload — the earlier claim that `playback_time` is absent was
   wrong, and was corrected on 2026-08-19 by measuring the live API. `duration`
   is the item's exact length in **seconds** and only arrives when the request's
   `fields` list names it; `film.playback_time` is the same length rounded to
   **minutes** and survives every `fields` variant, because `fields` prunes
   top-level keys but not included relations. Measured on the same row: 6585 s
   vs 110 min. Prefer `duration`, fall back to `playback_time * 60`, and never
   fall back to a bare `1` — that makes the denominator 60 seconds and paints a
   full bar for anything past a minute.
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
- `lib/screens/film_screen.dart` — cast strip + `_CastTile`, `ActorFilmsScreen` navigation, `episodeId` plumbing, server-only resume, status-bar scrim, dead `flexibleSpace` removed; 2026-08-17: scroll padded by `viewPadding.bottom`, `_episodeCardHeight = 160` shared by card/strip/skeleton, card text in `Expanded`.
- `lib/screens/films_full_screen.dart` — batch/season download, multi-select mode, `PopScope`, `episodeId` plumbing, server-only resume, `ApiErrorHandler`; 2026-08-17: grid padding gained `viewPadding.bottom`.
- `lib/screens/index_screen.dart` — `_primeFromCache`, cache writes, continue-watching progress/colour fix, `VideoLauncher` tap; 2026-08-16 (part 4): `_wasOffline` guard, parallel `Future.wait` home load, `CircleProgressPainter` driven by `repaint:` inside a `RepaintBoundary`.
- `lib/main.dart` — 2026-08-16 (part 4): `initialization()` no longer pads the splash with `Future.delayed`/`Future.doWhile`.
- `android/app/build.gradle.kts` — 2026-08-16 (part 4): `profile` build type installs as `.debug` with the debug signing config.
- `lib/screens/latestviewed_screen.dart` — correct film id, progress helper, tap → playback, long-press → film page; 2026-08-17: the playback path updates one card and moves it to the front instead of refetching the page.
- `lib/utils/pagination_controller.dart` — 2026-08-17: `moveToFront(test)`.
- `lib/utils/grid_density.dart` — **new** 2026-08-18: `GridDensityProvider` (2x2 / 3x3, persisted as `grid_columns`).
- `lib/widgets/recommended_films_widget.dart`, `lib/widgets/poster_grid_skeleton.dart`, `lib/screens/catalog_screen.dart`, `lib/screens/favorites_screen.dart` — 2026-08-18: column count from `GridDensityProvider`.
- `lib/screens/profile_screen.dart` — 2026-08-18: "Muqovalar ko'rinishi" row plus `GridDensityDialog`.
- `lib/main.dart` — 2026-08-18: `GridDensityProvider` loaded before `runApp` and registered in `MultiProvider`.
- `lib/services/update_service.dart` — 2026-08-17: `_ReleaseNotes` (scrollbar + bottom fade).
- `lib/screens/video_player_screen.dart` — server-only watch position, real `startAt` field; 2026-08-13: working exit write, 30 s periodic sync, `pendingPositionFlush`.
- `lib/utils/video_launcher.dart` — 2026-08-13: waits for the exit write before the caller reloads its list.
- `lib/utils/video_helpers.dart` — 2026-08-13: `safeDispose` now passes `forceDispose: true` (Bug 17).
- `lib/screens/download_screen.dart` — rewritten as quality picker + queue view.
- `lib/screens/profile_screen.dart` — "Yuklab olishlar" entry.
- `lib/screens/genres_films_screen.dart` — `FilmCard` image fallback now tries `linkAbsolute`.
- `lib/widgets/poster_card.dart` — 2026-08-19: `maxWidthDiskCache` / `maxHeightDiskCache` removed (debug-only `assert`; see part 3).
- `lib/screens/genres_screen.dart` — 2026-08-19: trailing `SliverToBoxAdapter` inset spacer, and the same two resize parameters removed.
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

- `lib/theme/glass.dart` — `GlassSurface`: the shared glass scrim, hairline, radius, dialog and bottom-sheet themes.
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
> `android/local.properties` is deliberately **left untracked** — it holds
> a machine-specific `flutter.sdk` path. `android/key.properties` (signing
> passwords) is covered by `android/.gitignore` and was never staged.
>
> A second, bogus `android/app/local.properties` (`flutter.sdk=C:\path\to\flutter`)
> sat untracked in the tree until 2026-08-17. Nothing read it — the build reads
> the one in `android/` — and it was deleted.
>
> Git identity was not configured in this environment; it was set
> **repository-locally** to `MRLG <d4rk73rr0r@gmail.com>`, matching the
> existing history. No global Git config was modified and nothing was pushed.

---

## Do Not Repeat

- **Do not drop the `Authorization` header from the OnTV channel request.**
  The endpoint answers 200 without it and still lists all 84 channels, but only
  one of them keeps a stream URL — the rest are null. The failure looks like an
  empty tab, not like an auth error.
- **Do not persist an OnTV channel list.** Its `url_*` links are signed and
  expire in ~6 hours; the service keeps them in memory for 30 minutes and the
  screen deliberately skips its disk cache for that source.
- **Do not call `/api/v2/categories` for OnTV tabs.** That is the film
  catalogue's list (36 rows); the channel categories arrive inline with
  `include=categories` and there are only two of them.
- **Do not try to reach an OqTV stream with the catalogue token.**
  `/v2/channels/{id}/stream` answers `401 authentication_failed` with the
  `api.oq.uz` `access_token`. Only the device token from
  `POST /v2/auth/device` works, and that call's body must be
  `application/x-www-form-urlencoded`.
- **Do not register an OqTV device on every launch.** The endpoint is not
  idempotent — the same serial produced two different ids on 2026-08-22. The
  serial, device id and stream token are kept in `SharedPreferences`
  (`oqtv_serial`, `oqtv_device_id`, `oqtv_stream_token`) and reused.
- **Do not cache an OqTV stream URL.** It embeds the device token and expires;
  it is re-fetched on every tap. The category payload, by contrast, is worth
  caching — one request returns all 13 categories with their channels inline.
- **Do not test a media URL only from Dart.** Dart's `HttpClient` ignores
  Android's network security policy, so an `http://` playlist fetches fine in a
  service-level check and then fails in the player with
  `CleartextNotPermittedException`. That is exactly what happened with OqTV on
  2026-08-22; the fix is `res/xml/network_security_config.xml`. Any new media
  source needs one real playback, not just a 200 from `http.get`.
- **Do not replace that config with a domain allowlist.** OqTV's stream host is
  a bare IP that changes per session (three distinct ones within an hour), so
  there is no stable domain to whitelist.
- **Do not re-verify the new-content notifications on a release build.** Done
  on 2026-08-22 against `uz.mrlg.riyaplay` `1.0.9 / 2010`, end to end: the
  killed-process alarm path, the background isolate under AOT, the posted
  notifications with the real `ic_notification` and their posters, and both tap
  paths. The numbers are in the 2026-08-22 session.
- **Do not try to read or rewrite the release install's `SharedPreferences`.**
  The release package is not debuggable, so `run-as` is refused and
  `new_content_last_publish_time` cannot be rewound from outside. To force a
  notification on release, patch `checkOnce()` to rewind the baseline once
  behind a throwaway flag, rebuild the arm64 split, `adb install -r` over the
  install (same key and `versionCode`, so data survives), then reinstall the
  backed-up shipped APK and revert the patch. **Back the shipped APK up first**
  — `flutter build` overwrites `build/app/outputs/flutter-apk/`.
- **Do not expect `appLogger` to prove a release background isolate ran.** It is
  silent in release. Use `dumpsys netstats detail` instead: sum the
  `uid=<app uid> … tag=0x0` buckets before and after. A check that runs shows
  ~32 KB of `rb` (the gzipped `/v2/films/search` page) with no UI on screen.
  Only sum the `tag=0x0` sections — tagged sections are subsets of them.
- **Do not annotate an alarm callback as a static method.**
  `@pragma('vm:entry-point')` on `NewContentScheduler.alarmCallback` was not
  enough — the VM refused it with `To access '…::NewContentScheduler' from
  native code, it must be annotated`, and the background isolate died on every
  fire. The callback is a top-level function (`newContentAlarmCallback`) for
  that reason. `flutter analyze` cannot see this; only killing the process and
  waiting for the alarm can.
- **Do not "fix" the new-content alarm for firing late.** It is inexact on
  purpose (`exact: false`), so Android attaches a `window=+3m45s` and defers it
  further under app-standby. Measured 2026-08-19: registered 13:52:35, fired
  14:01:20. An exact alarm would need `SCHEDULE_EXACT_ALARM`, denied by default
  on Android 14+; the only real fix is a server push.
- **Do not authenticate `/v2/films/search` in the poller.** It answers HTTP 200
  without an `Authorization` header (verified 2026-08-19), and the poller also
  runs in a background isolate where reading `auth_token` is pure overhead.
- **Do not read only the first row of that endpoint.** It is sorted by
  `updated_at`, not `publish_time` — an old film that was merely edited outranks
  a genuinely new one. The whole page is scanned against
  `new_content_last_publish_time`.
- **Do not use `@mipmap/launcher_icon` as the notification icon.** Android keeps
  only the alpha channel of a small notification icon, so it renders as a white
  block. Use `res/drawable/ic_notification.xml`.
- **Do not `await` the notification permission before scheduling.**
  `requestNotificationsPermission()` blocks on the Android 13+ system dialog; a
  user who ignores it would otherwise never get an alarm registered. `start()`
  runs first, the request second.
- **Do not re-investigate the 404 on `Kalmar o'yini 3-qism / segment244.ts`.**
  Reproduced on a completely fresh download; it is a source-side defect and is
  already mitigated by the tail-skip rule.
- **Do not repeat the claim that `playback_time` is absent from the
  latest-viewed payload.** Disproved on 2026-08-19 against the live API: it is
  present in every request variant (minutes), while the item's exact `duration`
  (seconds) only arrives when `fields` names it. Use `latestViewedProgress`,
  which prefers `duration` and falls back to `playback_time * 60`. What is
  actually forbidden is the old `?? 1` fallback — it makes the denominator 60
  seconds and renders a full bar for any position past a minute.
- **Do not use `second['film_id']` as a film id.** It is the episode id.
- **Do not add `SystemUiMode.edgeToEdge` calls to `FilmScreen`.** This was
  tried and then removed — the theme change alone is sufficient, and toggling
  the mode per screen is unnecessary churn.
- **Do not chase `AppBar.flexibleSpace` rendering.** It was already broken
  before this session; the scrim now lives in the poster `Stack` and works. A
  solid-red test proved the replacement renders.
- **Segment concurrency history — settled.** 10 gave 5.55 MB/s, 24 gave
  9.11 MB/s effective, and **48 was finally measured on 2026-08-19: 10.94 MB/s
  effective (11.44 MB/s network-only), 448 MB in 41 s, with no app restart and a
  byte-identical output file.** The 2026-08-13 restart that made 48 suspect did
  not reproduce; that run predates the Bug 17 `safeDispose` fix. Do not re-run
  this — it costs ~450 MB. `_maxInFlightBytes` (64 MB) is what bounds heap use.
  Note the measurement was on 4G+, where the network leg is 96 % of wall time.
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
- **Do not turn on `GlassBottomBar.blur`.** Measured twice: at two sigmas in
  part 5, and again in part 7 after the `TickerMode` fix. It costs ~2–4 ms of
  raster on the home tab **and** it cancels the off-screen fix entirely — with
  the blur on, every tab renders at ~120 fps again. The numbers are in the
  widget's doc comment.
- **Do not judge a colour/alpha change from a downscaled screenshot.** The
  0.38 → 0.70 scrim change looked like a no-op until the rendered pixel was
  sampled (`#ABABAB` → `#5C5C5C`).
- **Do not set `systemNavigationBarColor` to darken the navigation bar.** Under
  `SystemUiMode.edgeToEdge` the system ignores it — measured, pixel-identical
  with and without. `systemNavigationBarContrastEnforced: true` is what works.
- **Do not hard-code glass colours.** `lib/theme/glass.dart` (`GlassSurface`) is
  the single source for the scrim, the hairline and the radius; the bottom menu,
  the dialog theme and the bottom sheets all read from it.
- **Do not add `backgroundColor` / `shape` to an `AlertDialog`.** The app theme
  supplies the glass surface; a local override silently opts that dialog out.
  Six sites did exactly that and had to be stripped.
- **Do not run `dart format lib/`.** It reformats dozens of untouched files and
  buries the real diff. Format only the files you edited.
- **Do not lower `blurSigma` hoping to make the blur cheap.** σ=10 measured
  *worse* than σ=18. The cost is the backdrop read, not the radius.
- **Do not call `SystemChrome.setEnabledSystemUIMode` from a screen.** Go
  through `AppSystemUi`; the player and the shell used to fight over the
  system bars, which is what `lib/utils/system_ui.dart` exists to prevent.
- **Do not hide the system navigation bar again.** Part 5 hid it; part 6 put it
  back on request. The app default is `SystemUiMode.edgeToEdge` — both bars
  visible and transparent. Only the player's fullscreen path may hide them.
- **Do not re-investigate why the app renders when a tab is off-screen.**
  Found and fixed: the banner ring's `AnimationController` runs permanently and
  `KeepAliveWrapper` kept it ticking for hidden tabs. `TickerMode` in
  `MainScreen`'s `TabBarView` children is the fix; off-screen tabs now measure
  **0 frames / 3 s**.
- **Do not "fix" the Home tab's 120 fps by stopping the ring animation.** It is
  a visible animation on a visible screen and it costs 0 janky frames
  (build p50 ~1.1 ms, raster p50 ~3.6 ms). Measured, not assumed.
- **Do not build a custom widget for selected-only labels.**
  `BottomNavigationBar` does it with `showSelectedLabels` /
  `showUnselectedLabels`.
- **Do not raise the bottom-menu label size above 10 pt.** The glass panel is
  inset, so each slot is ~72 dp and "Bosh sahifa" is clipped at 11 pt.
- **Do not "fix" the update dialog's release notes for being cut off.** They sit
  in a 160 px `ConstrainedBox` with a `SingleChildScrollView` and have always
  scrolled; as of 2026-08-17 they also carry a `Scrollbar` and a bottom fade
  (`_ReleaseNotes`), so nothing about them is broken.
- **Do not look for `gh` on `PATH`.** The GitHub CLI is installed at
  `C:\Program Files\GitHub CLI\gh.exe` (authenticated as `d4rk73rr0r`, `repo`
  scope) but the shell in this environment does not pick it up; call it by full
  path. Releases go to `d4rk73rr0r/rplay-releases`, source to
  `d4rk73rr0r/riya_play`.
- **Do not retry `gh release create` blindly after an HTTP 5xx.** A failed
  create can leave an orphan draft with the same tag, and `gh` may fail to clean
  it up. Look for the existing release first, then `gh release upload
  --clobber` + `gh release edit --draft=false --latest`.
- **Do not hard-code `crossAxisCount: 2` (or `/ 2` for a row's item width)
  again.** The column count is a user setting — `GridDensityProvider.columns`
  in `lib/utils/grid_density.dart`, chosen in Profil as 2x2 / 3x3. **Every**
  poster grid reads it as of 2026-08-20: the home rows, Katalog, Sevimlilar,
  `PosterGridSkeleton`, Tavsiya etilganlar, the genre inner pages, the category
  pages (Premyeralar, Doramalar, …), an actor's films and Ko'rishlar tarixi. A
  hard-coded value makes the skeleton and the grid disagree, and it silently
  opts that screen out of the setting.
- **Do not build `MobileScanner` before the camera permission is granted.** It
  races the request, fails with a permission error, and `errorBuilder` paints
  a message that nothing clears afterwards — the screen looked broken until it
  was re-entered. `_permissionChecked` gates the scanner, the scan frame and
  the torch button.
- **Do not read `controller.torchEnabled` for the torch state.** In
  `mobile_scanner` 6.0.10 it is the `final` constructor argument, so it never
  changes and the icon stays `flash_off` forever. The live value is
  `controller.value.torchState`; the controller is a `ValueNotifier`, so a
  `ValueListenableBuilder` is enough and no `setState` is needed.
- **Do not restore `_pagination.refresh()` in `LatestViewedScreen.didPopNext`
  for the playback path.** Refetching 20 entries to reflect one changed entry is
  exactly what was removed: the card now updates its own position and the screen
  moves it to the front with `PaginationController.moveToFront`. The long-press
  (film page) path still refreshes fully, on purpose.
- **Do not `flutter build apk --release` and expect to install it over the
  device's release build.** Without `--split-per-abi` there is no ABI offset, so
  the APK is `versionCode 5` against the installed `2005` and `adb install -r`
  refuses it. Build `--split-per-abi --target-platform android-arm64`.
- **Do not read `latest-viewed` with the debug package's token to check the
  release app.** They are different accounts — verified 2026-08-17: the film
  watched on the release build never appeared in the debug account's list. The
  release package is not debuggable, so its token cannot be read at all; verify
  through the UI, which renders the server response anyway.
- **Do not re-run the release-build watch-position reproduction.** Done on
  2026-08-17 against `1.0.4 / 2005` built from `161d193`: exit write after Back
  without pausing produced `01:29`, and four play/Back cycles left the Java heap
  bounded (139 → 140 → 166 → 95 MB).
- **Do not re-create `android/app/local.properties`.** It was a placeholder
  (`flutter.sdk=C:\path\to\flutter`) that nothing reads — `build.gradle.kts`
  reads `android/local.properties`, one directory up. Deleted 2026-08-17.
- **Do not hard-code the episode-card height again.** `_episodeCardHeight` in
  `film_screen.dart` is shared by the card, its horizontal `ListView` and the
  skeleton loader; the three separate `136`s were what produced
  `BOTTOM OVERFLOWED BY 8.0 PIXELS`.
- **Any full-screen route needs its own bottom inset.** The app is
  `edgeToEdge`, so a scrollable that ends at the window bottom ends *under* the
  navigation bar. `FilmScreen` and `FilmsFullScreen` were fixed on 2026-08-17
  the same way part 7 fixed home/catalog/profile: pad inside the scrollable with
  `MediaQuery.viewPadding.bottom`.
- **Do not re-measure memory over navigation cycles.** Done on 2026-08-22 on
  release `1.0.9`: four Home → Katalog → FilmScreen → Back cycles left the Java
  heap at 10.4 → 20.4 → 16.9 → 17.5 MB and PSS at 488 → 513 → 503 → 510 MB.
  Bounded and non-monotonic, like the player cycles.
- **Do not re-check that `keep.xml` saved `ic_notification`.** Verified inside
  the shipped `v1.0.9` arm64 APK with
  `aapt2 dump resources`: `drawable/ic_notification` → `res/vO.xml`, 668 bytes,
  a real `<vector>` with `fillColor=#ffffffff`, and the posted notifications
  carry `id=0x7f0800c7`, that same resource. Re-check only after changing the
  shrinker settings or the resource's name.
- **Do not redo the bottom-inset sweep.** Completed 2026-08-19: every pushed
  route plus the TV tab was read and scrolled to its end on the device.
  `actor_films_screen`, `genres_films_screen`, `genres_screen` and
  `download_screen` were fixed; the rest already handle it, either through a
  `SafeArea` (whose default `bottom: true` reserves the inset) or through an
  existing `viewPadding.bottom`. **Do not add padding to those** — doubling it
  leaves a visible gap.
- **Do not pass `maxWidthDiskCache` / `maxHeightDiskCache` to
  `CachedNetworkImage` with `filmImagesCacheManager`.** That manager is a plain
  `CacheManager`, and `cached_network_image` asserts the manager is an
  `ImageCacheManager` whenever a resize is requested. The assert exists only in
  debug, so the result is a poster grid full of `Icons.broken_image` in debug
  and a perfectly normal one in release — which is exactly the "debug-only
  poster" mystery that stood open from 2026-08-13 to 2026-08-19. Use
  `memCacheWidth` if a size cap is wanted; it goes through `ResizeImage` and
  needs no special manager.
- **Do not "fix" it by mixing `ImageCacheManager` into
  `filmImagesCacheManager`.** It would work, but `_resizeImageFile` re-encodes
  to **PNG** while keeping the original extension, so every JPEG poster would be
  stored twice and the resized copy would be an order of magnitude larger. The
  parameters were inert in release, so removing them costs nothing.
- **Do not let anything awaited before `runApp` throw.** `main()` runs
  `DownloadManager.restore()`, `GridDensityProvider.load()` and the notification
  init before the first frame, and `FlutterNativeSplash.remove()` only runs from
  `_RiyaPlayAppState`. An unhandled exception anywhere in that chain leaves the
  native splash on screen forever with no error and no crash — exactly what
  shipped in v1.0.8.
- **Do not assume a Dart-only resource survives the release build.**
  `isShrinkResources = true` deleted `res/drawable/ic_notification.xml` because
  it is named only in a Dart string. `android/app/src/main/res/raw/keep.xml`
  pins it; anything else referenced solely from Dart needs the same treatment.
- **Do not test a release-mode transform with a debug build.** Two defects in
  one day were invisible in debug: the `assert` behind the broken posters
  (part 3) and the resource shrinker behind the splash freeze (part 5). Any
  change touching plugins, resources or startup needs one release run.
- **Do not `throw Exception(response['error'])` on a `sendRequest` failure.**
  It discards `statusCode`, so 401 reaches the user as "Kutilmagan xatolik" and
  `ServerErrorPage` hides the `Chiqish` button that would let them recover. Use
  `ApiErrorHandler.fromResponse`.
- **Do not expect `appLogger` output from a release build.** It is
  `Level.nothing` under `kReleaseMode`. Release-mode diagnosis needs a temporary
  `debugPrint`, which must be removed afterwards.
- **Do not go looking for a film with no `lastSeries`.** 170 were probed on
  2026-08-19 (the 20 most recently updated and the 150 oldest by `publish_time`)
  and every one had a populated `lastSeries.track`. The `getFirstEpisode`
  fallback was verified by ablating the field in a debug build instead, and the
  ablation was reverted. Use that method if the branch ever needs re-testing.
- **Do not add a separate SHA-256 asset to the release.** The GitHub releases
  API already returns `"digest": "sha256:<hex>"` on each asset; `_pickApk` reads
  it. Verified 2026-08-19 that the digest matches the locally built APK exactly.
  The atom fallback has no asset list, so it stays unverified there — by design.
- **Do not put a raw `$e` in a user-visible string.** Every screen goes through
  `ApiErrorHandler`; `lib/utils/pagination_controller.dart` and
  `index_screen._fetchData` are the two funnels that cover most of them.
  `appLogger` calls keep the raw exception on purpose. Two sites are deliberate
  exceptions — an `AndroidIntent` failure is not an API error and carries a
  fixed sentence instead.
- **Do not re-investigate the debug-only poster rendering.** Cause found and
  fixed on 2026-08-19 (part 3), verified on device across Katalog, Sevimlilar
  and Janrlar. It was never about the API payload, `CachedNetworkImage` caching,
  or the grid-density setting.
- **Do not download real content to test the queue UI.** Turn "Faqat Wi-Fi
  orqali" on while the device is on mobile data, then queue a whole series: the
  cards render at "Wi-Fi kutilmoqda" and no bytes move. Cancel each afterwards
  (cancelled counts as `isFinished`, so "Tozalash" clears them) and put the
  toggle back.
- **A chooser instead of the installer is a device quirk.** This device has
  `com.nh.aex/.InstallApk` (APKExtractor) registered for
  `ACTION_INSTALL_PACKAGE`, so Android shows `ResolverActivity` until a
  default is picked. Nothing to fix in the app.

---

## Next Recommended Step

**The TV tab was rebuilt on 2026-08-22** (parts 2 and 3): `SalomTV` and `BizTV`
are gone, `OqTV` is the new default and `OnTV` is the third source. All three
are verified on the device — 98 / 84 / 143 channels, category tabs, and live
playback on each. It shipped as **`v1.0.10`**. Two things follow from it:

- **`network_security_config.xml` now permits cleartext app-wide.** It is
  required by OqTV's `http://` streams and by nothing else. If OqTV ever serves
  HTTPS, tighten it back.
- **OnTV's bearer expires in late March 2027** (`exp: 1806132793`). After that
  its list still loads but arrives without stream URLs.

Because `v1.0.10` is now newer than what any device carries, the two rows that
were waiting for "a release newer than the installed one" are unblocked: the
install flow on a release build, and the OTA SHA-256's first runtime exercise.

**The release-build verification sweep is done** (2026-08-22). The whole
new-content notification chain was exercised on `uz.mrlg.riyaplay` `1.0.9 /
2010` — killed process, alarm broadcast, AOT background isolate, the poller's
network call, three posted notifications with the real `ic_notification` and
their posters, and both tap paths — plus a real reboot (`Rescheduling after
boot!`, the same schedule restored, and the rescheduled alarm firing on its own
at 13:50:31), plus the navigation-cycle memory measurement. Four Remaining Work
rows closed. **Do not redo any of them.**

**Only three device rows are still open**, and none of them is blocking:

- **Doze timing** — leave the phone untouched overnight and compare the alarm's
  fire times. Everything measured so far was on an awake device (5 min →
  ~8m45s awake, and 3m10s of inexact-window jitter after the reboot).
- **The install flow on a release build** — needs a release *newer* than the
  installed `1.0.9 / 2010` to offer, so it waits for the next publish. When one
  ships, run the same four permission scenarios against `uz.mrlg.riyaplay`; the
  OTA SHA-256 check gets its first runtime exercise at the same time.
- **The `tplaytv` backport on an Android TV box** — static-analysis clean but
  never run; this machine has no TV device.

The working tree is clean again: the temporary rewind patch used to force a
release notification was reverted, `flutter analyze` is back to the 5-info
baseline, and the device carries the byte-identical shipped `v1.0.9` APK
(sha1 `40c6d00815f54b98c40a3b9f0dde711bba5f1799`). The only residue is an unread
`_force_new_content_test` key in the release install's `SharedPreferences`.

**The OTA chain is finished.** All four install-permission scenarios pass, both
defects found while running them are fixed and re-verified on device, and the
published APKs turned out to be correctly versioned after all. Nothing in the
update flow is known to be broken.

**Nothing is blocking.** The OTA chain, the performance audit, the glass menu,
the system-bar behaviour and the release-build watch-position repeat are all
settled and measured; see parts 4–8 and the 2026-08-17 section.

**The release-build repeat is done** (2026-08-17): the exit write and the
bounded heap were both confirmed on `uz.mrlg.riyaplay` 1.0.4 / 2005. Do not
redo it.

**New-content notifications landed on 2026-08-19** and are verified on the
device, including the case the whole feature exists for: the process killed, the
alarm firing on its own, four notifications posted, and a tap cold-starting the
app straight onto the film's page. Release-build verification and the reboot
were both done on 2026-08-22 and passed; only Doze timing is still unmeasured.

**The bottom-inset sweep is closed** (2026-08-19, part 2). Four screens were
fixed and five were deliberately left alone because they already reserve the
inset; every one was scrolled to its end on the device. Do not redo it, and do
not add padding to the five.

**The debug-only poster defect is closed** (2026-08-19, part 3). It was a
debug-only `assert` in `cached_network_image`, tripped by
`maxWidthDiskCache` / `maxHeightDiskCache` on a cache manager that is not an
`ImageCacheManager`. Two call sites lost those parameters
(`lib/widgets/poster_card.dart`, `lib/screens/genres_screen.dart`) and all three
affected surfaces were verified on the device. Release behaviour is unchanged,
because the parameters were already being ignored there.

**Three reported UI defects were fixed on 2026-08-20** and shipped as
`v1.0.9`: the 2x2 / 3x3 setting now reaches every poster grid, the TV-activation
screen no longer leaves a camera error on screen after the permission is
granted, and its torch icon tracks the real torch state. All three verified on
the device.

**v1.0.8 shipped broken and was republished on 2026-08-19** — the resource
shrinker deleted `ic_notification`, the notification init threw before
`runApp`, and the app sat on the splash forever. Fixed with `res/raw/keep.xml`
plus a guard around that whole block, verified on a release build, and the
release assets were replaced **without a version bump at the owner's
instruction**. Devices already on the broken v1.0.8 will therefore not be
offered the fix by the OTA check — they need a manual reinstall or a `v1.0.9`.
The catalogue home is still unverified on release, because reaching it needs
the owner's login.

**The Medium/Low list is empty except for the release-build repeats**
(2026-08-19, part 4). Segment concurrency at 48 is measured and stays,
`getFirstEpisode` is verified by ablation, `ApiErrorHandler` covers the screens,
the OTA download carries a SHA-256, TV-channel playback leaves the heap bounded,
and the `tplaytv` backport has landed. One long-standing claim in this document
was overturned along the way — see the corrected Important Discovery #3.

**`v1.0.9` is the Latest release** (`1010 / 2010 / 4010`, published
2026-08-20 07:58 UTC, all three split APKs `uploaded`, the arm64 digest
matching the local `sha256sum`). Because the version did move this time, the
OTA check will offer it to the devices stuck on the broken v1.0.8. Its release
build was launched on the device and reached the **catalogue home screen** —
banners, continue-watching and three-column rows — with zero `E/flutter`
output, which is the confirmation the v1.0.8 republish could not get.

**The working tree is clean and everything is released.** All three 2026-08-19
changes — the new-content notifications, the bottom-inset sweep and the debug
poster fix — were committed as four commits plus a docs commit and pushed to
`main` (`a96ef45..f5d0d83`). `pubspec.yaml` is `1.0.8+9`, and `v1.0.8`
(`1009 / 2009 / 4009`) is the Latest release on `d4rk73rr0r/rplay-releases` with
all three split APKs `uploaded`. The next release needs a bump to `1.0.9+10`
first.

The open list is the Medium/Low set at the end of this document:

- ~~**Sweep the remaining full-screen routes for the same bottom inset.**~~
  **DONE (2026-08-19)** — see part 2 of that session. Four screens were fixed,
  five already handled it, and the TV tab was checked as well.
- ~~**Debug-only poster rendering.**~~ **DONE (2026-08-19)** — see part 3 of
  that session. A debug-only `assert` inside `cached_network_image`, not a
  caching or payload problem.
- ~~Re-measure segment concurrency at 48, the unexercised `getFirstEpisode`
  fallback, `ApiErrorHandler` coverage, TV-channel playback after the disposal
  change, a SHA-256 for the OTA download, and the `tplaytv` backport.~~ **All six
  DONE (2026-08-19)** — see part 4 of that session.
- ~~**What is left is release-build verification and one device this machine
  does not have.**~~ **Mostly DONE (2026-08-22)** — the notification feature is
  now verified on the release build, and the alarm has survived a real reboot.
  Three things still cannot be done here: the install flow on release (needs a
  release newer than the installed `1.0.9 / 2010`, which also gates the OTA
  SHA-256's first runtime exercise), Doze timing, and the `tplaytv` backport on
  an Android TV box.
- ~~Optional: the grid-density setting reached only the home rows, Katalog,
  Sevimlilar and the skeleton.~~ **DONE (2026-08-20)** — the remaining five
  grids read `GridDensityProvider.columns` too.

The idle ~120 fps question is **not** on this list any more — part 6 found and
fixed it (the banner ring's `AnimationController` ticking for off-screen tabs).
Memory over *navigation* cycles (Home → Catalog → FilmScreen, no playback) is
still unmeasured; the player cycles are covered.
