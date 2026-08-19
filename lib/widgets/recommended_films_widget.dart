import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:riya_play/utils/grid_density.dart';
import 'package:riya_play/utils/image_cache_manager.dart';
import 'package:riya_play/utils/app_logger.dart';

class RecommendedFilmsWidget extends StatelessWidget {
  final List<dynamic> films;
  final bool isLoading;
  final bool isDark;
  final String? error;
  final Function(dynamic) onTap;
  final VoidCallback onMoreTap;

  const RecommendedFilmsWidget({
    super.key,
    required this.films,
    required this.isLoading,
    required this.isDark,
    this.error,
    required this.onTap,
    required this.onMoreTap,
  });

  @override
  Widget build(BuildContext context) {
    // Ekran kengligini olish
    final screenWidth = MediaQuery.of(context).size.width;
    // Padding (16 + 16) va margin (12) ni hisobga olamiz
    const horizontalPadding = 16.0 * 2; // Ikki tarafdan padding
    const itemMargin = 12.0; // Kartalar orasidagi bo'shliq
    // Ekranga nechta muqova sig'ishi Profil bo'limidagi sozlamadan keladi.
    final columns = Provider.of<GridDensityProvider>(context).columns;
    // Har bir kartaning kengligi: (ekran kengligi - padding - oraliqlar) / N
    final itemWidth =
        (screenWidth - horizontalPadding - itemMargin * (columns - 1)) /
        columns;
    // Balandlikni responsiv qilish uchun 3:2 nisbatidan foydalanamiz
    final itemHeight = itemWidth * 1.5;
    // Umumiy bo'lim balandligi: rasm balandligi + matnlar + bo'shliqlar
    final sectionHeight = itemHeight + 48; // Qo‘shimcha joy uchun +8

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Sizga tavsiya qilamiz",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.grey[800],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: onMoreTap,
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: sectionHeight,
            child:
                isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : error != null
                    ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            // `error` allaqachon `ApiErrorHandler` bergan
                            // foydalanuvchi matni — oldiga "Xato:" qo'shish
                            // shart emas.
                            error!,
                            style: const TextStyle(
                              fontSize: 16,
                              color: Colors.grey,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton(
                            onPressed: onMoreTap,
                            child: const Text('Qayta urinish'),
                          ),
                        ],
                      ),
                    )
                    : films.isEmpty
                    ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            "Tavsiya etilgan filmlar topilmadi",
                            style: TextStyle(fontSize: 16, color: Colors.grey),
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton(
                            onPressed: onMoreTap,
                            child: const Text('Qayta urinish'),
                          ),
                        ],
                      ),
                    )
                    : ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: films.length,
                      itemExtent: itemWidth + itemMargin,
                      itemBuilder: (context, index) {
                        final film = films[index];
                        final files = film['files'] as List<dynamic>? ?? [];
                        final imageUrl =
                            files.isNotEmpty
                                ? (files[0]['thumbnails'] != null &&
                                        files[0]['thumbnails']['small'] !=
                                            null &&
                                        files[0]['thumbnails']['small']['src'] !=
                                            null
                                    ? files[0]['thumbnails']['small']['src']
                                    : files[0]['link'] ??
                                        'https://placehold.co/320x180')
                                : 'https://placehold.co/320x180';
                        final year = film['year']?.toString() ?? '';
                        final genres = film['genres'] ?? [];
                        final genreName =
                            genres.isNotEmpty ? genres[0]['name_uz'] ?? '' : '';

                        return GestureDetector(
                          onTap: () => onTap(film),
                          child: Container(
                            margin: const EdgeInsets.only(right: 12),
                            width: itemWidth,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  height: itemHeight,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    image: DecorationImage(
                                      image: CachedNetworkImageProvider(
                                        imageUrl,
                                        cacheManager: filmImagesCacheManager,
                                        errorListener: (error) {
                                          appLogger.d(
                                            'RecommendedFilms rasm yuklash xatosi: $error',
                                          );
                                        },
                                      ),
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        film['name_uz'] ?? 'Noma’lum',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        year.isNotEmpty && genreName.isNotEmpty
                                            ? "$year · $genreName"
                                            : year.isNotEmpty
                                            ? year
                                            : genreName,
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey,
                                        ),
                                      ),
                                      const SizedBox(
                                        height: 8,
                                      ), // Bu yerda joylashtirildi
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }
}
