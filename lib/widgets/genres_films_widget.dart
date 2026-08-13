import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:riya_play/screens/error_pages.dart';
import 'package:riya_play/main.dart' show MainScreen;

class GenreCard extends StatelessWidget {
  final Map<String, dynamic> genre;
  final VoidCallback onTap;

  const GenreCard({Key? key, required this.genre, required this.onTap})
    : super(key: key);

  @override
  Widget build(BuildContext context) {
    final imageUrl =
        genre['photo'] != null
            ? (genre['photo']['thumbnails'] != null &&
                    genre['photo']['thumbnails']['small'] != null &&
                    genre['photo']['thumbnails']['small']['src'] != null
                ? genre['photo']['thumbnails']['small']['src']
                : genre['photo']['link'] ?? 'https://placehold.co/305x200')
            : 'https://placehold.co/305x200';
    final name = genre['name_uz'] ?? 'No Name';

    return GestureDetector(
      onTap: () async {
        // checkConnectivity() ro'yxat qaytaradi — uni bitta qiymat bilan
        // solishtirish hech qachon rost bo'lmagan, ya'ni oflayn holat
        // umuman aniqlanmay kelgan.
        final connectivityResult = await Connectivity().checkConnectivity();
        if (connectivityResult.every((r) => r == ConnectivityResult.none)) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder:
                  (_) => NetworkErrorPage(
                    onRetry: () async {
                      final retryResult =
                          await Connectivity().checkConnectivity();
                      if (!retryResult.every(
                        (r) => r == ConnectivityResult.none,
                      )) {
                        // Pastki navigatsiya MainScreen'da — IndexScreen'ni
                        // yolg'iz ochsak, tablar yo'qolib qoladi.
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const MainScreen(),
                          ),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Internet aloqasi hali ham yo‘q'),
                          ),
                        );
                      }
                    },
                  ),
            ),
          );
        } else {
          onTap();
        }
      },
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              imageUrl,
              width: 305,
              height: 200,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  width: 305,
                  height: 200,
                  color: Colors.grey[300],
                  child: const Center(
                    child: Text(
                      'Rasmni yuklashda xato',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                );
              },
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return const SizedBox(
                  width: 305,
                  height: 200,
                  child: Center(child: CircularProgressIndicator()),
                );
              },
            ),
          ),
          Container(
            width: 305,
            height: 200,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.6),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 50,
            left: 18,
            child: Text(
              name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
