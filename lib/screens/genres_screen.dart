import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:riya_play/services/api_service.dart';
import 'package:riya_play/screens/genres_films_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:riya_play/theme_provider.dart';
import 'package:riya_play/utils/navigation.dart'; // createSlideRoute uchun import
import 'package:riya_play/utils/image_cache_manager.dart';

class GenresScreen extends StatefulWidget {
  const GenresScreen({super.key});

  @override
  State<GenresScreen> createState() => _GenresScreenState();
}

class _GenresScreenState extends State<GenresScreen> {
  List<dynamic> genres = [];
  bool isLoading = true;
  bool hasError = false;

  @override
  void initState() {
    super.initState();
    _fetchGenres();
  }

  Future<void> _fetchGenres() async {
    if (!mounted) return;

    setState(() {
      isLoading = true;
      hasError = false;
    });

    try {
      final response = await ApiService.getGenresPreview();
      if (mounted) {
        setState(() {
          genres = response;
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoading = false;
          hasError = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Janrlar yuklashda xatolik: $e")),
        );
      }
    }
  }

  @override
  void dispose() {
    genres.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Scaffold(
      backgroundColor:
          themeProvider.isDarkMode ? const Color(0xFF111827) : Colors.grey[100],
      appBar: AppBar(
        backgroundColor:
            themeProvider.isDarkMode ? const Color(0xFF1F2937) : Colors.white,
        elevation: 2,
        title: Text(
          'Janrlar',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
          ),
        ),
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios,
            color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body:
          isLoading
              ? const Center(child: CircularProgressIndicator())
              : hasError
              ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "Janrlar yuklashda xatolik yuz berdi",
                      style: TextStyle(
                        fontSize: 16,
                        color:
                            themeProvider.isDarkMode
                                ? Colors.grey[400]
                                : Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _fetchGenres,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).primaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text("Qayta urinish"),
                    ),
                  ],
                ),
              )
              : genres.isEmpty
              ? Center(
                child: Text(
                  "Janrlar topilmadi",
                  style: TextStyle(
                    fontSize: 16,
                    color:
                        themeProvider.isDarkMode
                            ? Colors.grey[400]
                            : Colors.grey[600],
                  ),
                ),
              )
              : CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => GenreCard(genre: genres[index]),
                        childCount: genres.length,
                      ),
                    ),
                  ),
                ],
              ),
    );
  }
}

class GenreCard extends StatelessWidget {
  final dynamic genre;

  const GenreCard({super.key, required this.genre});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final imageUrl =
        genre['photo']?['thumbnails']?['small']?['src'] ??
        genre['photo']?['link'] ??
        'https://placehold.co/600x300';
    final name = genre['name_uz'] ?? 'Noma’lum';

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          createSlideRoute(
            GenresFilmsScreen(genre: genre),
          ), // PageRouteBuilder bilan o‘tish
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.withOpacity(0.2)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              children: [
                CachedNetworkImage(
                  imageUrl: imageUrl,
                  cacheManager: filmImagesCacheManager,
                  width: double.infinity,
                  height: 200,
                  fit: BoxFit.cover,
                  maxWidthDiskCache: 600,
                  maxHeightDiskCache: 300,
                  fadeInDuration: const Duration(milliseconds: 300),
                  placeholder:
                      (context, url) => Container(
                        width: double.infinity,
                        height: 200,
                        color:
                            themeProvider.isDarkMode
                                ? const Color(0xFF374151)
                                : Colors.grey[300],
                      ),
                  errorWidget:
                      (context, url, error) => Container(
                        width: double.infinity,
                        height: 200,
                        color:
                            themeProvider.isDarkMode
                                ? const Color(0xFF374151)
                                : Colors.grey[300],
                        child: const Icon(Icons.broken_image),
                      ),
                ),
                Container(
                  width: double.infinity,
                  height: 200,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.black.withOpacity(0.4),
                        Colors.transparent,
                      ],
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                    ),
                  ),
                ),
                Positioned(
                  bottom: 12,
                  left: 16,
                  child: Text(
                    name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
