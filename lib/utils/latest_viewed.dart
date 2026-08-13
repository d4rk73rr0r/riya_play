/// Helpers for `/v2/films/latest-viewed` items.
///
/// The payload is easy to misread, and both "Ko'rishni davom ettirish"
/// screens did:
///
/// * the item's own `duration` is the episode length in **seconds**; the
///   code divided by `film.playback_time * 60`, and `playback_time` isn't in
///   the response at all — so the fallback of 1 turned every position past a
///   minute into a full progress bar;
/// * `second.film_id` is **not** a film id. Its sibling `model` says
///   `common\models\Series` and its value equals the item's own `id`, i.e.
///   it is the episode id. The real film id is the item's top-level
///   `film_id` (and `film.id`).
library;

/// Episode id of the entry — what the watch-progress endpoints key on.
int? latestViewedEpisodeId(dynamic item) {
  final id = item['id'] ?? item['second']?['film_id'];
  return id is int ? id : int.tryParse(id?.toString() ?? '');
}

/// Film id of the entry, for opening the film page.
int latestViewedFilmId(dynamic item) {
  final id = item['film']?['id'] ?? item['film_id'];
  if (id is int) return id;
  return int.tryParse(id?.toString() ?? '') ?? 0;
}

/// Seconds already watched.
int latestViewedSeconds(dynamic item) {
  final time = item['second']?['time'];
  return time is int ? time : int.tryParse(time?.toString() ?? '') ?? 0;
}

/// Total length of the entry in seconds, or null when unknown.
int? latestViewedDuration(dynamic item) {
  final duration = item['duration'];
  final seconds =
      duration is int ? duration : int.tryParse(duration?.toString() ?? '');
  if (seconds != null && seconds > 0) return seconds;

  // Ba'zi yozuvlarda epizod davomiyligi yo'q — film darajasidagi
  // `playback_time` daqiqada beriladi.
  final playbackMinutes = item['film']?['playback_time'];
  final minutes =
      playbackMinutes is int
          ? playbackMinutes
          : int.tryParse(playbackMinutes?.toString() ?? '');
  if (minutes != null && minutes > 0) return minutes * 60;

  return null;
}

/// Fraction watched, 0..1. Returns 0 when the length is unknown, so the bar
/// reads "not started" rather than the old "finished".
double latestViewedProgress(dynamic item) {
  final total = latestViewedDuration(item);
  if (total == null || total <= 0) return 0;
  return (latestViewedSeconds(item) / total).clamp(0.0, 1.0);
}

/// `MM:SS`, or `H:MM:SS` past an hour — episodes here run well over 60
/// minutes, and the old two-field format printed those as "78:12".
String formatWatchedTime(int seconds) {
  final duration = Duration(seconds: seconds);
  String two(int n) => n.toString().padLeft(2, '0');
  final minutes = two(duration.inMinutes.remainder(60));
  final secs = two(duration.inSeconds.remainder(60));
  return duration.inHours > 0
      ? '${duration.inHours}:$minutes:$secs'
      : '$minutes:$secs';
}
