import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:riya_play/theme/glass.dart';

/// Pastki menyu uchun "suyuq shisha" qatlami.
///
/// Android'da Apple'ning haqiqiy Liquid Glass materiali yo'q, shuning uchun
/// effekt qatlamlardan yig'iladi: yarim shaffof gradient shishaning o'z
/// qalinligini, yuqori chetdagi yorug' chiziq esa qirraga tushgan yorug'likni
/// beradi. Ixtiyoriy [blur] ustiga haqiqiy xiralashtirish qo'shadi.
///
/// Ortida kontent bo'lishi uchun `Scaffold(extendBody: true)` shart, aks holda
/// panel ostida chizadigan narsa qolmaydi va u oddiy tekis rangga aylanadi.
class GlassBottomBar extends StatelessWidget {
  const GlassBottomBar({
    super.key,
    required this.child,
    this.blur = false,
    this.blurSigma = 18.0,
    this.borderRadius = 28.0,
    this.margin = const EdgeInsets.fromLTRB(12, 0, 12, 10),
  });

  final Widget child;

  /// Haqiqiy `BackdropFilter` xiralashtirishi.
  ///
  /// **Ataylab o'chirilgan.** Qurilmada o'lchandi (SM-A556E, 120 Hz, profil
  /// build, bosh sahifa bo'sh turganda):
  ///
  /// | Variant | raster p50 | raster p90 | jank / 3 s |
  /// | --- | --- | --- | --- |
  /// | blur yo'q | 3.6–4.3 ms | 4.7–6.3 ms | 0 |
  /// | `BackdropFilter` σ=18 | 6.5–8.2 ms | 8.3–8.8 ms | 4–29 |
  /// | `BackdropFilter` σ=10 | 8.4–8.6 ms | 8.9–9.1 ms | 47–59 |
  ///
  /// 120 Hz byudjeti 8.3 ms. [blurSigma] ni kamaytirish yordam bermadi —
  /// narx radiusda emas, `BackdropFilter` ning har kadrda orqa fonni qayta
  /// o'qishida. Bu bosh sahifaning bo'sh turganda ham ~120 fps da qayta
  /// chizilishi bilan birga kelib, byudjetdan chiqaradi. Skroll paytida blur
  /// muammo emas (jank 0–6).
  ///
  /// Ya'ni: bosh sahifaning bo'sh turgandagi qayta chizilishi tuzatilsa, buni
  /// `true` qilish mumkin. Undan oldin emas.
  final bool blur;

  final double blurSigma;
  final double borderRadius;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);

    // Qatlam qiymatlari [GlassSurface] da — dialoglar ham o'shandan oladi,
    // shunda ikkalasi bir xil quyuqlikda qoladi.
    final surface = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: GlassSurface.gradient,
        border: GlassSurface.border,
      ),
      child: child,
    );

    return Padding(
      padding: margin,
      child: ClipRRect(
        borderRadius: radius,
        child:
            blur
                ? BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: blurSigma,
                    sigmaY: blurSigma,
                  ),
                  child: surface,
                )
                : surface,
      ),
    );
  }
}
