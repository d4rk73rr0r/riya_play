# Riya Play

Riya Play video xizmatining Android mijozi: kinolar va seriallar katalogi, TV kanallar,
sevimlilar, ko'rish tarixi va oflayn yuklab olish.

Flutter 3.44 / Dart 3.12 asosida. `publish_to: 'none'` — ilova pub.dev ga chiqarilmaydi.

## Imkoniyatlar

- **Avtorizatsiya** — telefon raqami va SMS kodi orqali (`sms_autofill` bilan kod
  avtomatik to'ldiriladi). Sessiya `auth_token` sifatida saqlanadi.
- **Katalog** — janrlar, kategoriyalar, tavsiya etilganlar, qidiruv; barcha ro'yxatlar
  cheksiz aylantirish (infinite scroll) bilan.
- **Film va serial sahifasi** — fasllar, qismlar, sifat variantlari.
- **Pleyer** — `better_player` asosida, ekran yorqinligi boshqaruvi va uyquni bloklash
  (`wakelock_plus`); ko'rish pozitsiyasi eslab qolinadi.
- **TV kanallar** — uchta tashqi provayder (SalomTV, SpecUZ, BizTV) orqali.
- **Sevimlilar va tarix** — server bilan sinxron, ro'yxatni tozalash imkoniyati.
- **Profil** — shaxsiy ma'lumotlar, ulangan qurilmalar ro'yxati va ularni uzish,
  QR kod orqali televizorni aktivlashtirish (`mobile_scanner`).
- **Oflayn yuklab olish** — navbat, pauza/davom ettirish, faqat Wi-Fi rejimi, foreground
  service bildirishnomasi. Tugagan video `/sdcard/Movies/RiyaPlay/` ga tushadi va
  Gallereyada ko'rinadi.

## Talablar

| Nima | Versiya |
|---|---|
| Flutter | 3.44+ (Dart SDK `^3.7.2`) |
| JDK | 17 |
| Android compileSdk | 36 |
| Android minSdk | 26 (Android 8.0) |
| Android targetSdk | 34 |

Faqat Android. `ios/` papkasi yo'q — `pubspec.yaml` va konfiguratsiya fayllaridagi iOS
kalitlari ishlatilmaydi.

## Sozlash

```bash
flutter pub get
```

Keyin `android/` ichida ikkita fayl yaratish kerak. Ikkalasi ham `.gitignore` da, ya'ni
repoda yo'q — ularsiz Gradle configure fazasida yiqiladi.

`android/local.properties`:

```properties
flutter.sdk=C:\\path\\to\\flutter
sdk.dir=C:\\path\\to\\Android\\Sdk
```

Qolgan kalitlarni (`flutter.buildMode`, `flutter.versionName`, `flutter.versionCode`)
Flutter o'zi qo'shadi — qo'lda yozish kerak emas.

`android/key.properties` (release imzosi uchun; `build.gradle.kts` bu qiymatlarni
`as String` bilan o'qiydi, shuning uchun debug build uchun ham fayl mavjud bo'lishi kerak):

```properties
keyAlias=<alias>
keyPassword=<parol>
storeFile=<keystore fayl yo'li>
storePassword=<parol>
```

## Ishga tushirish va build

```bash
flutter run
```

```bash
flutter build apk --release
```

```bash
flutter analyze
```

`flutter analyze` hozir 5 ta `info` darajali xabar beradi
(`library_private_types_in_public_api`) — bu mavjud holat, xato yoki warning yo'q.

Loyihada `test/` papkasi va `flutter_test` yo'q.

### Debug alohida ilova sifatida o'rnatiladi

Debug buildda `applicationIdSuffix = ".debug"`, ya'ni paket nomi
`uz.mrlg.riyaplay.debug`. Shu sababli debug va release bir qurilmada yonma-yon turadi va
release ilovadagi sessiya buzilmaydi. `adb` buyruqlarida suffiksli nomni ishlatish kerak:

```bash
adb shell run-as uz.mrlg.riyaplay.debug ls /data/data/uz.mrlg.riyaplay.debug/app_flutter/
```

### Ikonka va splash ekranni qayta generatsiya qilish

Manba rasmlar (`assets/images/riya.png`, `assets/images/launchlogo.png`) o'zgarganda:

```bash
dart run flutter_native_splash:create
```

```bash
dart run flutter_launcher_icons
```

## Loyiha tuzilishi

```
lib/
  main.dart              Ilova qobig'i: avtorizatsiya darvozasi, 5 tabli navigatsiya, tema
  screens/               Ekranlar (katalog, film, pleyer, yuklab olishlar, profil/...)
  services/
    api/                 ApiClient + domen bo'yicha ajratilgan *Api sinflari
    api_service.dart     Yuqoridagilar ustidan fasad
    tv_api_service.dart  TV provayderlari (asosiy API dan mustaqil)
    download_manager.dart  Yuklab olish navbati, holatni saqlash, Wi-Fi gate
    download_service.dart  Transferning o'zi: HLS, AES-128, resume, remux
  utils/                 PaginationController, logger, nomlash, video yordamchilari
  widgets/               Qayta ishlatiladigan kartochka/grid/skeleton widgetlar
  theme/, theme_provider.dart  Rang palitrasi va o'lchamlar
android/app/src/main/kotlin/uz/mrlg/riyaplay/
  MainActivity.kt        MediaStore ga saqlash va servis boshqaruvi (MethodChannel)
  DownloadService.kt     Yuklab olish bildirishnomasi (dataSync foreground service)
packages/flutter_iconly/ Lokal path-paket (pub versiyasidan moslashtirilgan)
```

## Diqqat qilinadigan joylar

- **Faqat qorong'i tema.** `ThemeProvider` — palitra, almashtirgich emas. Light tema
  ilgari status-bar render muammolari sababli olib tashlangan.
- **`ApiClient.sendRequest` istisno tashlamaydi.** Xatolar ham `success: false` bo'lgan map
  ko'rinishida qaytadi, shuning uchun chaqiruvchi javob shaklini tekshirishi kerak.
- **Yuklab olish oqimi:** fayl avval ilova ichki xotirasiga tushadi, so'ng Kotlin tomoni
  uni MediaStore orqali `Movies/RiyaPlay` ga ko'chiradi. Scoped storage sharoitida
  `/sdcard` ga to'g'ridan-to'g'ri yozish ishlamaydi.
- **HLS oqimlari** AES-128 bilan shifrlangan bo'lishi mumkin; kalitlar segment davomida
  almashishi hisobga olingan. `.ts` fayllar `ffmpeg -c copy` bilan `.mp4` ga
  konteyner darajasida o'tkaziladi — qayta kodlash yo'q.
- **`packages/flutter_iconly`** lokal nusxa, `pub upgrade` unga tegmaydi.
  `better_player` esa pub'dan emas, `Lo4D/better-player-ultra` git forkidan olinadi.
- Firebase `pubspec.yaml` da izohga olingan — integratsiya yo'q.

Kod ichidagi izohlar va interfeys matnlari o'zbek tilida. Tahrirlashda shu tilni saqlash
kerak.
