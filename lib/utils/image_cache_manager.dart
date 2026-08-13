import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Single on-disk cache for all film/channel poster and thumbnail images.
///
/// Previously each screen created its own [CacheManager] with a different
/// cache key, so the same poster URL got downloaded and stored again under
/// a separate bucket depending on which screen first displayed it (catalog,
/// favorites, latest-viewed, history, recommended... each kept its own
/// copy). Sharing one instance means a poster is fetched from disk once no
/// matter where it's shown, and total disk usage is capped in one place.
final filmImagesCacheManager = CacheManager(
  Config(
    'filmImagesCache',
    stalePeriod: const Duration(days: 7),
    maxNrOfCacheObjects: 300,
  ),
);
