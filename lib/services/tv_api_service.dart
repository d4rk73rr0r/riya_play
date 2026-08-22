import 'package:riya_play/services/error_handler.dart';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:riya_play/utils/app_logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// TV kanallari uchun uchinchi tomon manbalari.
///
/// Har bir manba butunlay boshqa API: umumiy `api_client.dart` bu yerda
/// ishlatilmaydi. Hozirda ikkitasi qoldi — **OqTV** (asosiy) va **SpecUZ**.
/// Eski `SalomTV` va `BizTV` 2026-08-22 da olib tashlandi.
class TVApiService {
  /// Manba nomi → uning asosiy manzili. Ekrandagi tanlov ro'yxati ham shu
  /// xaritadan quriladi, shuning uchun tartib muhim: birinchisi standart.
  static const Map<String, String> baseUrls = {
    "OqTV": "https://uzbeeline.platform24.tv",
    "OnTV": "https://api.ontv.uz",
    "SpecUZ": "https://api.spec.uzd.udevs.io",
  };

  static const Map<String, String> defaultHeaders = {
    "Accept": "application/json",
    "User-Agent": "okhttp/4.9.2",
    "Content-Type": "application/json",
  };

  static const Map<String, String> specUzHeaders = {
    "User-Agent": "Dart/3.4 (dart:io)",
    "Accept-Encoding": "gzip, deflate, br",
    "key": "false",
    "platform": "7e9217c5-a6b4-490a-9e90-dad564f39361",
    "Connection": "keep-alive",
  };

  // ---------------------------------------------------------------------
  // OnTV
  // ---------------------------------------------------------------------

  /// OnTV hisobining doimiy tokeni.
  ///
  /// Ro'yxatni tokensiz ham olish mumkin, lekin unda 84 ta kanaldan faqat
  /// bittasida strim manzili bo'ladi — qolganlari `null` bo'lib keladi
  /// (2026-08-22 da solishtirilgan). Token JWT bo'lib, `exp` maydoni
  /// `1806132793` — taxminan **2027-yil mart oxiri**. O'shanda ro'yxat
  /// strimsiz qolsa, birinchi tekshiriladigan narsa shu.
  static const String _onTvToken =
      'eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiJ9.eyJhdWQiOiI5IiwianRpIjoiY2UwN2E0MjdiZDMxNTViNzEzM2M0NDNmOTE1YjM0MDc1Mjg3ODE5ZDBkYjc5NmU3YjNkN2ZkMDE1ZGZmNjBmZmFhZDZhM2M1MDU5MzkzNWIiLCJpYXQiOjE3NzQ1OTY3OTMuMzMxMjM0LCJuYmYiOjE3NzQ1OTY3OTMuMzMxMjQxLCJleHAiOjE4MDYxMzI3OTMuMzEyODQ5LCJzdWIiOiIxNjU4MDUiLCJzY29wZXMiOlsiY2xpZW50Il19.hPPMZYnRGLs_7vqZoVxkfeFCZnQ19TGaS-krwYTSaZ0QL9dat4wi0h0sbH_FX2adM4sUAB5MfZu8cTp5JtMsNZ1vSb_NqJmfGYVP92lUrM3ErEh90aJ4glSKrdNdsPbcca8U1fkvCRLvK6XxxlITEvadPogvnkJx-g_fFOyacC9vnL4O411KxihKJVZCKQ2sayvSsF_Bf8Qa9YPY8H1OMHbWciHvwJ25ri-FJyKmRgEJ8e-b8MjTG6MRUgkRPDXRadq227Y4zvkxdS8UhSxhJ5VotSdteB82fiALLUVqFrToQiIQV52Zf5UxGHfFkMOJVJYPq7wlNfngLyJaN23BPbmNNBi8VxX-lB4emstFp05bwBFBe7XvJWlYE_ViGo920fQnEYShaV-KDfTngzauDCLCr4LeLpv3xRy4y1ft46ir8J4YXN7SuPcvnz4PeqoW27MkcJAxCSH5X2SetMdGWWMPBQFpxjyxOyjFcfJgWgPEbaMqkImPUw5E9fJIg6rkINYHaPzkyU7C8WvJZ5FT13ixo2emrVjLQAveR_AOKYXVCFGKZvSOpUIkx6YaKLvlzd0cjB-2FyGA1E1Wyda2GymXwQuOyx9QEYocNGa83cM4FwWpmLk0bhmc4BHK-1scsIOpIVXTFSmXgxbXeyWHKL46kq364Oim-LtDefAn-NM';

  static const Map<String, String> onTvHeaders = {
    "User-Agent":
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:149.0) "
        "Gecko/20100101 Firefox/149.0",
    "Accept": "application/json",
    "Authorization": "Bearer $_onTvToken",
  };

  /// Strim manzillari imzolangan va **taxminan 6 soatdan keyin eskiradi**
  /// (`token=…-1787412727-1787391127` — ikkinchi raqam berilgan vaqt,
  /// birinchisi amal qilish muddati). Shuning uchun ro'yxat diskka
  /// yozilmaydi va xotiradagi nusxa ham shu muddatdan keyin yangilanadi.
  static const Duration _onTvChannelsTtl = Duration(minutes: 30);

  /// Kanallar bitta sahifada sig'adi: `per_page=100`, jami 84 ta
  /// (`last_page: 1`), shuning uchun sahifalash sikli kerak emas.
  static List<dynamic>? _onTvRawChannels;
  static DateTime? _onTvFetchedAt;

  // ---------------------------------------------------------------------
  // OqTV
  // ---------------------------------------------------------------------

  /// Token beruvchi host. Kanallar ro'yxati va strim boshqa hostda
  /// (`baseUrls["OqTV"]`) yotadi.
  static const String _oqAuthBase = "https://api.oq.uz";

  /// OqTV `Dart/3.9 (dart:io)` dan boshqa `User-Agent` ni qabul qilmaydi —
  /// boshqasi bilan token so'rovi 403 qaytaradi.
  static const Map<String, String> oqTvHeaders = {
    "User-Agent": "Dart/3.9 (dart:io)",
    "Accept-Language": "uz",
    "Content-Type": "application/json",
  };

  /// Qurilma yozuvi provayder hisobida saqlanadi, shuning uchun seriya raqami
  /// va olingan qurilma tokeni `SharedPreferences` da qoladi: har ishga
  /// tushishda yangi qurilma ro'yxatdan o'tkazish hisobni ming yozuv bilan
  /// to'ldirib yuboradi (bir xil seriya bilan ham API yangi `id` qaytaradi —
  /// 2026-08-22 da tekshirilgan).
  static const String _prefsOqSerial = 'oqtv_serial';
  static const String _prefsOqDeviceId = 'oqtv_device_id';
  static const String _prefsOqStreamToken = 'oqtv_stream_token';

  /// Kategoriyalar ro'yxatidagi ruscha nomlarning o'zbekcha ko'rinishi.
  ///
  /// Odatda kerak emas: `Accept-Language: uz` sarlavhasi bilan server nomlarni
  /// o'zi o'zbekcha qaytaradi ("Bolajonlarga", "Ma'rifat", "Musiqiy" — qurilmada
  /// 2026-08-22 da tekshirilgan). Bu xarita sarlavha e'tiborga olinmagan holat
  /// uchun zaxira; ro'yxatda bo'lmagan nom o'z holicha ko'rsatiladi.
  static const Map<String, String> _oqCategoryNames = {
    'Бесплатные': 'Bepul',
    'Прочие': 'Boshqalar',
    'Познавательные': 'Bilim',
    'Новости': 'Yangiliklar',
    'HD каналы': 'HD kanallar',
    'Интересное': 'Qiziqarli',
    'Развлекательные': "Ko'ngilochar",
    'Музыкальные': 'Musiqa',
    'Детские': 'Bolalar',
    'Национальные': 'Milliy',
    'Фильмы и сериалы': 'Kino va seriallar',
    'Спортивные': 'Sport',
  };

  /// Provayderning "Barcha kanallar" kategoriyasi. Ekranda "Barchasi" tabi
  /// baribir bor, shuning uchun bu ro'yxatdan chiqarib tashlanadi.
  static const int _oqAllChannelsCategoryId = 2;

  /// Katalog uchun token (`api.oq.uz` dan). Jarayon davomida saqlanadi.
  static String? _oqAccessToken;

  /// Strim uchun qurilma tokeni. `null` bo'lsa `SharedPreferences` dan
  /// o'qiladi yoki qaytadan olinadi.
  static String? _oqStreamToken;

  /// Bitta so'rovda kelgan xom kategoriyalar (kanallari bilan birga).
  /// `getTVChannels` shu nusxadan o'qiydi — bitta so'rov 275 KB va butun
  /// ro'yxatni olib keladi, kategoriya boshiga alohida so'rov kerak emas.
  static List<dynamic>? _oqRawCategories;

  static Future<dynamic> _sendRequest({
    required String url,
    required String source,
    Map<String, String>? headers,
  }) async {
    try {
      final combinedHeaders =
          source == "SpecUZ"
              ? {...defaultHeaders, ...specUzHeaders, ...?headers}
              : source == "OqTV"
              ? {...oqTvHeaders, ...?headers}
              : source == "OnTV"
              ? {...onTvHeaders, ...?headers}
              : {...defaultHeaders, ...?headers};

      final response = await http.get(Uri.parse(url), headers: combinedHeaders);

      appLogger.d("So'rov URL: $url");
      appLogger.d("Javob kodi: ${response.statusCode}");

      if (response.statusCode == 200 || response.statusCode == 202) {
        return jsonDecode(utf8.decode(response.bodyBytes));
      } else {
        return {"success": false, "error": "Xatolik: ${response.statusCode}"};
      }
    } catch (e) {
      appLogger.d("Tarmoq xatosi: $e");
      return {"success": false, "error": "Tarmoq xatosi: $e"};
    }
  }

  /// OnTV kanallari — kategoriyalari va logotipi bilan bitta so'rovda.
  ///
  /// Javob eskirganda (`_onTvChannelsTtl`) o'z-o'zidan qaytadan olinadi:
  /// ro'yxatdagi manzillar imzolangan va muddatli.
  static Future<List<dynamic>> _onTvChannelsRaw({bool force = false}) async {
    final fresh =
        _onTvFetchedAt != null &&
        DateTime.now().difference(_onTvFetchedAt!) < _onTvChannelsTtl;
    if (!force && fresh && _onTvRawChannels != null) return _onTvRawChannels!;

    final base = baseUrls["OnTV"]!;
    final response = await _sendRequest(
      url:
          '$base/api/v2/channels?append=promotion&include=file,categories'
          '&per_page=100&_f=json&_l=uz',
      source: "OnTV",
    );

    if (response is! Map || response['data'] is! List) {
      throw ApiErrorHandler.fromResponse(
        response is Map<String, dynamic>
            ? response
            : {"success": false, "error": "Noto'g'ri javob"},
        "Kanallar yuklanmadi",
      );
    }

    _onTvRawChannels = response['data'] as List;
    _onTvFetchedAt = DateTime.now();
    return _onTvRawChannels!;
  }

  /// Bitta OnTV kanalini ekran kutgan ko'rinishga keltiradi.
  ///
  /// Strim manzili ro'yxatning o'zida keladi — alohida so'rov yo'q.
  static Map<String, dynamic>? _onTvChannel(dynamic channel) {
    if (channel is! Map) return null;
    final id = channel['id'];
    if (id == null) return null;
    final file = channel['file'];
    return {
      "id": id.toString(),
      "title_uz": (channel['name'] ?? 'Noma\'lum').toString(),
      "image": file is Map ? file['url'] : null,
      "url": channel['url_1080'] ?? channel['url_720'] ?? channel['url_480'],
    };
  }

  /// Qurilma uchun barqaror seriya raqami. Bir marta yaratiladi va saqlanadi.
  static Future<String> _oqSerial() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsOqSerial);
    if (saved != null && saved.isNotEmpty) return saved;

    final random = Random();
    final serial =
        'riyaplay-${DateTime.now().millisecondsSinceEpoch}-'
        '${random.nextInt(0x7fffffff).toRadixString(16)}';
    await prefs.setString(_prefsOqSerial, serial);
    return serial;
  }

  /// Katalog tokeni: `token/base` dan bearer, undan `kinom/auth/token` orqali
  /// `access_token`. Ikkalasi ham anonim — foydalanuvchi hisobi kerak emas.
  ///
  /// [force] `true` bo'lsa keshdagi token tashlanadi (401 dan keyin).
  static Future<String> _oqAccess({bool force = false}) async {
    if (!force && _oqAccessToken != null) return _oqAccessToken!;

    final serial = await _oqSerial();

    final tokenResponse = await http.post(
      Uri.parse('$_oqAuthBase/token/base/'),
      headers: oqTvHeaders,
      body: jsonEncode({'serial_number': serial}),
    );
    if (tokenResponse.statusCode != 200 && tokenResponse.statusCode != 201) {
      throw ErrorInfo(
        type: ErrorType.serverError,
        message: 'oq token/base ${tokenResponse.statusCode}',
        userMessage: 'OqTV serveriga ulanib bo‘lmadi.',
        canRetry: true,
      );
    }
    final bearer =
        (jsonDecode(utf8.decode(tokenResponse.bodyBytes))
            as Map<String, dynamic>)['access'];
    if (bearer is! String || bearer.isEmpty) {
      throw const ErrorInfo(
        type: ErrorType.serverError,
        message: 'oq token/base: access missing',
        userMessage: 'OqTV serveriga ulanib bo‘lmadi.',
        canRetry: true,
      );
    }

    final authResponse = await http.post(
      Uri.parse('$_oqAuthBase/api/v1/kinom/auth/token/'),
      headers: {...oqTvHeaders, 'Authorization': 'Bearer $bearer'},
    );
    if (authResponse.statusCode != 200 && authResponse.statusCode != 201) {
      throw ErrorInfo(
        type: ErrorType.serverError,
        message: 'oq kinom/auth ${authResponse.statusCode}',
        userMessage: 'OqTV serveriga ulanib bo‘lmadi.',
        canRetry: true,
      );
    }
    final auth =
        jsonDecode(utf8.decode(authResponse.bodyBytes)) as Map<String, dynamic>;
    final access = auth['access_token'];
    if (access is! String || access.isEmpty) {
      throw const ErrorInfo(
        type: ErrorType.serverError,
        message: 'oq kinom/auth: access_token missing',
        userMessage: 'OqTV serveriga ulanib bo‘lmadi.',
        canRetry: true,
      );
    }

    _oqAccessToken = access;
    _oqUserId = auth['user_id'];
    return access;
  }

  /// Oxirgi autentifikatsiyadagi foydalanuvchi identifikatori — qurilmani
  /// ro'yxatdan o'tkazishda kerak.
  static dynamic _oqUserId;

  /// Qurilmani ro'yxatdan o'tkazadi va uning tokenini qaytaradi.
  static Future<String> _oqRegisterDevice(String access) async {
    final serial = await _oqSerial();
    final base = baseUrls["OqTV"]!;

    final registerResponse = await http.post(
      Uri.parse(
        '$base/v2/users/self/devices?access_token=${Uri.encodeQueryComponent(access)}',
      ),
      headers: {...oqTvHeaders, 'Kinom-Access-Token': access},
      body: jsonEncode({
        'name': 'RiyaPlay+${_oqUserId ?? ''}',
        'device_type': 'phone',
        'vendor': 'RiyaPlay',
        'serial': serial,
        'user_id': _oqUserId,
      }),
    );
    if (registerResponse.statusCode != 200 &&
        registerResponse.statusCode != 201) {
      throw ErrorInfo(
        type: ErrorType.serverError,
        message: 'oq devices ${registerResponse.statusCode}',
        userMessage: 'OqTV qurilmani ro‘yxatdan o‘tkazmadi.',
        canRetry: true,
      );
    }
    final deviceId =
        (jsonDecode(utf8.decode(registerResponse.bodyBytes))
            as Map<String, dynamic>)['id'];
    if (deviceId is! String || deviceId.isEmpty) {
      throw const ErrorInfo(
        type: ErrorType.serverError,
        message: 'oq devices: id missing',
        userMessage: 'OqTV qurilmani ro‘yxatdan o‘tkazmadi.',
        canRetry: true,
      );
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsOqDeviceId, deviceId);

    return _oqAuthDevice(access, deviceId);
  }

  /// Ro'yxatdan o'tgan qurilmani tasdiqlaydi. Javobdagi `access_token` —
  /// strim so'rovlari uchun yagona yaroqli token.
  ///
  /// Tanasi ataylab `x-www-form-urlencoded`: JSON bilan endpoint 400 beradi.
  static Future<String> _oqAuthDevice(String access, String deviceId) async {
    final base = baseUrls["OqTV"]!;
    final response = await http.post(
      Uri.parse(
        '$base/v2/auth/device?access_token=${Uri.encodeQueryComponent(access)}',
      ),
      headers: const {
        'User-Agent': 'Dart/3.9 (dart:io)',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: {'device_id': deviceId},
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw ErrorInfo(
        type: ErrorType.serverError,
        message: 'oq auth/device ${response.statusCode}',
        userMessage: 'OqTV qurilmani tasdiqlamadi.',
        canRetry: true,
      );
    }
    final token =
        (jsonDecode(utf8.decode(response.bodyBytes))
            as Map<String, dynamic>)['access_token'];
    if (token is! String || token.isEmpty) {
      throw const ErrorInfo(
        type: ErrorType.serverError,
        message: 'oq auth/device: access_token missing',
        userMessage: 'OqTV qurilmani tasdiqlamadi.',
        canRetry: true,
      );
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsOqStreamToken, token);
    _oqStreamToken = token;
    return token;
  }

  /// Strim tokenini qaytaradi: avval xotiradan, so'ng diskdan, bo'lmasa
  /// saqlangan qurilmani qayta tasdiqlab, u ham bo'lmasa yangi qurilma
  /// ro'yxatdan o'tkazib.
  static Future<String> _oqStream({bool force = false}) async {
    if (!force && _oqStreamToken != null) return _oqStreamToken!;

    final prefs = await SharedPreferences.getInstance();
    if (!force) {
      final saved = prefs.getString(_prefsOqStreamToken);
      if (saved != null && saved.isNotEmpty) {
        _oqStreamToken = saved;
        return saved;
      }
    }

    final access = await _oqAccess(force: force);
    final deviceId = prefs.getString(_prefsOqDeviceId);
    if (deviceId != null && deviceId.isNotEmpty) {
      try {
        return await _oqAuthDevice(access, deviceId);
      } catch (e) {
        // Qurilma provayder tomonidan o'chirilgan bo'lishi mumkin —
        // yangisini ro'yxatdan o'tkazamiz.
        appLogger.d('OqTV qurilmasi tasdiqlanmadi, yangisi olinadi: $e');
      }
    }
    return _oqRegisterDevice(access);
  }

  /// Kategoriyalarni (kanallari bilan) bir so'rovda oladi va keshlaydi.
  static Future<List<dynamic>> _oqCategoriesRaw({bool force = false}) async {
    if (!force && _oqRawCategories != null) return _oqRawCategories!;

    final base = baseUrls["OqTV"]!;
    var access = await _oqAccess(force: force);
    var response = await _sendRequest(
      url:
          '$base/v2/users/self/channels/categories'
          '?access_token=${Uri.encodeQueryComponent(access)}',
      source: "OqTV",
    );

    // Token eskirgan bo'lsa bitta marta yangilab ko'ramiz.
    if (response is Map && response['success'] == false) {
      access = await _oqAccess(force: true);
      response = await _sendRequest(
        url:
            '$base/v2/users/self/channels/categories'
            '?access_token=${Uri.encodeQueryComponent(access)}',
        source: "OqTV",
      );
    }

    if (response is! List) {
      throw ApiErrorHandler.fromResponse(
        response is Map<String, dynamic>
            ? response
            : {"success": false, "error": "Noto'g'ri javob"},
        "Kategoriyalar yuklanmadi",
      );
    }

    _oqRawCategories = response;
    return response;
  }

  /// Bitta kanalni ekran kutgan ko'rinishga keltiradi.
  static Map<String, dynamic>? _oqChannel(dynamic channel) {
    if (channel is! Map) return null;
    final id = channel['id'];
    if (id == null) return null;
    final cover = channel['cover'];
    final image =
        (cover is Map ? (cover['full'] ?? cover['bg']) : null) ??
        channel['icon'];
    return {
      "id": id.toString(),
      "title_uz": (channel['name'] ?? 'Noma\'lum').toString(),
      "image": image,
    };
  }

  static Future<List<dynamic>> getTVCategories(String source) async {
    if (source == "OqTV") {
      final raw = await _oqCategoriesRaw();
      final categories =
          raw
              .whereType<Map>()
              .where(
                (category) =>
                    category['id'] != null &&
                    category['id'] != _oqAllChannelsCategoryId,
              )
              .map((category) {
                final name = (category['name'] ?? '').toString();
                return {
                  "id": category['id'].toString(),
                  "title_uz": _oqCategoryNames[name] ?? name,
                };
              })
              .toList();
      categories.sort(
        (a, b) => (a['title_uz'] as String).compareTo(b['title_uz'] as String),
      );
      return categories;
    }

    if (source == "OnTV") {
      // Kategoriyalar kanallarning o'zida keladi. `/api/v2/categories` ham
      // bor, lekin u kinokatalogniki: 36 ta yozuvning faqat ikkitasi
      // telekanallarga tegishli (`type: 3`).
      final raw = await _onTvChannelsRaw();
      final seen = <String, Map<String, dynamic>>{};
      for (final channel in raw.whereType<Map>()) {
        for (final category in (channel['categories'] as List? ?? const [])) {
          if (category is! Map || category['id'] == null) continue;
          final id = category['id'].toString();
          seen[id] ??= {
            "id": id,
            "title_uz":
                (category['name_uz'] ?? category['name_ru'] ?? '').toString(),
            "sort": category['sort'] ?? 0,
          };
        }
      }
      final categories = seen.values.toList()
        ..sort((a, b) => (a['sort'] as num).compareTo(b['sort'] as num));
      return categories;
    }

    final baseUrl = baseUrls[source]!;
    final url = "$baseUrl/v1/tv/category?limit=50&page=1&search=&status=true";

    final response = await _sendRequest(url: url, source: source);

    if (response['success'] == false) {
      throw ApiErrorHandler.fromResponse(response, "Kategoriyalar yuklanmadi");
    }

    return response['categories'] as List<dynamic>;
  }

  static Future<Map<String, dynamic>> getTVChannels({
    required String source,
    int page = 1,
    int limit = 24,
    bool status = true,
    String? categoryId,
  }) async {
    if (source == "OqTV") {
      final raw = await _oqCategoriesRaw();
      final channels = <Map<String, dynamic>>[];
      final seen = <String>{};

      for (final category in raw.whereType<Map>()) {
        if (categoryId != null &&
            categoryId.isNotEmpty &&
            category['id']?.toString() != categoryId) {
          continue;
        }
        // Kategoriyasiz so'rov — "Barchasi" tabi: provayderning "Все каналы"
        // ro'yxati baribir hamma kanalni o'z ichiga oladi, lekin qolganlari
        // bilan takrorlanadi, shuning uchun `seen` bo'yicha filtrlanadi.
        for (final channel in (category['channels'] as List? ?? const [])) {
          final mapped = _oqChannel(channel);
          if (mapped == null) continue;
          if (!seen.add(mapped['id'] as String)) continue;
          channels.add(mapped);
        }
      }

      channels.sort(
        (a, b) => (a['title_uz'] as String).toLowerCase().compareTo(
          (b['title_uz'] as String).toLowerCase(),
        ),
      );
      return {"tv_channels": channels};
    }

    if (source == "OnTV") {
      final raw = await _onTvChannelsRaw();
      final channels = <Map<String, dynamic>>[];

      for (final channel in raw.whereType<Map>()) {
        if (categoryId != null && categoryId.isNotEmpty) {
          final belongs = (channel['categories'] as List? ?? const []).any(
            (category) =>
                category is Map && category['id']?.toString() == categoryId,
          );
          if (!belongs) continue;
        }
        final mapped = _onTvChannel(channel);
        if (mapped == null || mapped['url'] == null) continue;
        channels.add(mapped);
      }

      return {"tv_channels": channels};
    }

    final baseUrl = baseUrls[source]!;
    var url =
        "$baseUrl/v1/tv/channel?search=&limit=$limit&page=$page&status=$status";
    if (categoryId != null && categoryId.isNotEmpty) {
      url += "&category=$categoryId";
    } else {
      url += "&category=";
    }

    final response = await _sendRequest(url: url, source: source);

    if (response['success'] == false) {
      throw ApiErrorHandler.fromResponse(response, "Kanallar yuklanmadi");
    }

    return response;
  }

  /// Kanal uchun o'ynatiladigan HLS manzili.
  ///
  /// OqTV da manzil qurilma tokeni bilan imzolanadi va uzoq yashamaydi —
  /// shuning uchun u har safar kanal bosilganda qaytadan so'raladi, keshlanmaydi.
  static Future<String?> getStreamUrl({
    required String source,
    required String channelId,
  }) async {
    if (source == "OqTV") {
      final base = baseUrls["OqTV"]!;

      Future<dynamic> request(String token) => _sendRequest(
        url:
            '$base/v2/channels/${Uri.encodeComponent(channelId)}/stream'
            '?access_token=${Uri.encodeQueryComponent(token)}',
        source: "OqTV",
      );

      var response = await request(await _oqStream());
      if (response is Map && response['success'] == false) {
        // Saqlangan qurilma tokeni yaroqsiz — qaytadan tasdiqlaymiz.
        response = await request(await _oqStream(force: true));
      }
      if (response is! Map || response['success'] == false) {
        throw ApiErrorHandler.fromResponse(
          response is Map<String, dynamic>
              ? response
              : {"success": false, "error": "Noto'g'ri javob"},
          "Strim olinmadi",
        );
      }

      final url = response['hls_mbr'] ?? response['hls'];
      return url is String && url.isNotEmpty ? url : null;
    }

    if (source == "OnTV") {
      // Manzil ro'yxatdan olinadi. Eskirgan bo'lsa `_onTvChannelsRaw` uni
      // o'zi yangilaydi; kanal topilmasa ro'yxat majburan qayta so'raladi.
      var raw = await _onTvChannelsRaw();
      var match = raw.whereType<Map>().firstWhere(
        (channel) => channel['id']?.toString() == channelId,
        orElse: () => const {},
      );
      if (match.isEmpty) {
        raw = await _onTvChannelsRaw(force: true);
        match = raw.whereType<Map>().firstWhere(
          (channel) => channel['id']?.toString() == channelId,
          orElse: () => const {},
        );
      }
      final url =
          match['url_1080'] ?? match['url_720'] ?? match['url_480'];
      return url is String && url.isNotEmpty ? url : null;
    }

    final details = await getChannelDetails(source: source, channelId: channelId);
    final url = details['channel_stream_all'] ?? details['test_stream'];
    return url is String && url.isNotEmpty ? url : null;
  }

  static Future<Map<String, dynamic>> getChannelDetails({
    required String source,
    required String channelId,
  }) async {
    if (source != "SpecUZ") {
      return {"success": false, "error": "Faqat SpecUZ uchun ishlaydi"};
    }

    final baseUrl = baseUrls[source]!;
    final url = "$baseUrl/v1/tv/channel/$channelId";

    final response = await _sendRequest(url: url, source: source);

    if (response['success'] == false) {
      throw ApiErrorHandler.fromResponse(response, "Kanal detallari yuklanmadi");
    }

    return response;
  }
}
