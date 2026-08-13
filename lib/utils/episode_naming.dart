/// Builds the name a downloaded episode is saved under.
///
/// The player shows short labels like "3-qism", but using that as the file
/// name meant every series wrote to the same `3-qism.mp4` and silently
/// overwrote whatever was downloaded before. Qualifying it with the series
/// title and season keeps each episode distinct on disk:
/// `Kalmar o'yini (1-fasl, 3-qism)`.
String buildEpisodeDownloadTitle({
  required String seriesName,
  required int seasonNumber,
  required int episodeIndex,
  String? episodeName,
}) {
  final label =
      (episodeName != null && episodeName.trim().isNotEmpty)
          ? episodeName.trim()
          : '${episodeIndex + 1}-qism';
  return '$seriesName ($seasonNumber-fasl, $label)';
}
