import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import 'package:riya_play/theme_provider.dart';
import 'package:riya_play/theme/app_dimens.dart';
import 'package:riya_play/utils/grid_density.dart';

/// Shimmering placeholder grid shown while a poster list's first page is
/// still loading, instead of a bare spinner.
class PosterGridSkeleton extends StatelessWidget {
  final int itemCount;

  const PosterGridSkeleton({super.key, this.itemCount = 6});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return GridView.builder(
      padding: const EdgeInsets.all(AppSpacing.lg),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        // Skeleton haqiqiy setka bilan bir xil ustunda chizilishi kerak,
        // aks holda yuklab bo'lgach kartalar sakrab qoladi.
        crossAxisCount: Provider.of<GridDensityProvider>(context).columns,
        crossAxisSpacing: AppSpacing.md,
        mainAxisSpacing: AppSpacing.md,
        childAspectRatio: 0.65,
      ),
      itemCount: itemCount,
      itemBuilder:
          (context, index) => Shimmer.fromColors(
            baseColor:
                themeProvider.isDarkMode
                    ? Colors.grey[800]!
                    : Colors.grey[300]!,
            highlightColor:
                themeProvider.isDarkMode
                    ? Colors.grey[600]!
                    : Colors.grey[100]!,
            period: const Duration(milliseconds: 1000),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.md),
                color: themeProvider.cardColor,
              ),
            ),
          ),
    );
  }
}
