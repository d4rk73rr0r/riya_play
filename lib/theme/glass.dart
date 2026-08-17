import 'package:flutter/material.dart';

/// "Suyuq shisha" yuzasining umumiy qiymatlari.
///
/// Pastki menyu ham, dialoglar ham shu yerdan oziqlanadi — ikkalasi bir xil
/// quyuqlikda ko'rinishi kerak. Android'da Apple'ning Liquid Glass materiali
/// yo'q, shuning uchun effekt quyuq yarim shaffof qatlam va qirradagi yorug'
/// chiziqdan yig'iladi.
///
/// Qatlam **quyuq**, och emas: yuza ortida yorqin poster turishi mumkin va oq
/// matn/ikonkalar och qatlamda butunlay yo'qolib ketardi. Qurilmada o'lchangan
/// (oq poster ustida): oq 0.14 → ko'rinmaydi, qora 0.38 → `#ABABAB` hamon
/// och, qora 0.70 → `#5C5C5C` va har qanday fonda o'qiladi.
class GlassSurface {
  GlassSurface._();

  /// Yuqori chetdagi qatlam quyuqligi.
  static const Color scrimTop = Color(0xB3000000); // 0.70

  /// Pastki chetdagi qatlam quyuqligi — yengil gradient uchun.
  static const Color scrimBottom = Color(0x94000000); // 0.58

  /// Qirradagi yorug' chiziq.
  static const Color edge = Color(0x2EFFFFFF); // 0.18

  static const double edgeWidth = 0.8;
  static const double radius = 28.0;

  static const LinearGradient gradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [scrimTop, scrimBottom],
  );

  static BorderRadius get borderRadius => BorderRadius.circular(radius);

  static Border get border => Border.all(color: edge, width: edgeWidth);

  /// Dialoglar uchun shakl: bir xil radius va qirra.
  static RoundedRectangleBorder get dialogShape => RoundedRectangleBorder(
    borderRadius: borderRadius,
    side: const BorderSide(color: edge, width: edgeWidth),
  );

  /// Pastdan chiqadigan oynalar uchun: yuqori ikki burchak yumaloq.
  static const BorderRadius sheetBorderRadius = BorderRadius.vertical(
    top: Radius.circular(radius),
  );

  static Border get sheetBorder => Border.all(color: edge, width: edgeWidth);

  /// `showModalBottomSheet` fonini shaffof qiladi, shunda oynaning o'zi
  /// chizgan shisha yuza ko'rinadi.
  static const BottomSheetThemeData bottomSheetTheme = BottomSheetThemeData(
    backgroundColor: Colors.transparent,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
  );

  /// Butun ilova dialoglariga qo'llanadigan mavzu.
  ///
  /// `AlertDialog` fonni bitta rang bilan chizadi, gradient qabul qilmaydi —
  /// shuning uchun bu yerda gradientning yuqori chekkasi ishlatiladi.
  static DialogThemeData get dialogTheme => DialogThemeData(
    backgroundColor: scrimTop,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    shape: dialogShape,
    titleTextStyle: const TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w600,
      color: Colors.white,
    ),
    contentTextStyle: const TextStyle(fontSize: 14, color: Colors.white),
  );
}
