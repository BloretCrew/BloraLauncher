import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../main.dart';
import '../services/config_service.dart';
import '../core/logger.dart';

enum TranslationEngine { auto, google, mymemory, libre, deepl, sogou, youdao, bing }

class TranslateApi {
  static final Dio _dio = Dio();
  static String? _bingCookie;

  static final List<String> _googleEndpoints = [
    "https://translate.googleapis.com/translate_a/single",
    "https://translate.google.com/translate_a/single",
  ];

  static final List<String> _libreInstances = [
    "https://libretranslate.de/translate",
    "https://translate.argosopentech.com/translate",
  ];

  static final List<String> _deeplMirrors = [
    "https://deepl-api.vercel.app/translate",
    "https://api.deeplx.org/translate",
  ];

  // Helper to map launcher language to engine-specific codes
  static String _getMappedLang(String lang, TranslationEngine engine) {
    lang = lang.toLowerCase();
    if (engine == TranslationEngine.google) {
      if (lang.contains("zh_tw") || lang.contains("zh_hk")) return "zh-TW";
      if (lang.contains("zh")) return "zh-CN";
      return lang.split('_').first;
    }
    
    if (engine == TranslationEngine.deepl) {
       if (lang.contains("zh")) return "ZH";
       return lang.split('_').first.toUpperCase();
    }
    
    if (engine == TranslationEngine.bing) {
      if (lang.contains("zh_tw") || lang.contains("zh_hk")) return "zh-Hant";
      if (lang.contains("zh")) return "zh-Hans";
      return lang.split('_').first;
    }

    if (lang.contains("zh")) return "zh"; 
    return lang.split('_').first;
  }

  static Future<bool> checkApiStatus() async {
    final engineStr = ConfigService.get("translation_engine") ?? "auto";
    String checkUrl = "";
    
    if (engineStr == "auto" || engineStr == "google") {
      checkUrl = _googleEndpoints.first;
    } else if (engineStr == "mymemory") {
      checkUrl = "https://api.mymemory.translated.net/get";
    } else if (engineStr == "libre") {
      checkUrl = _libreInstances.first;
    } else if (engineStr == "deepl") {
      checkUrl = _deeplMirrors.first;
    } else if (engineStr == "sogou") {
      checkUrl = "https://fanyi.sogou.com/";
    } else if (engineStr == "youdao") {
      checkUrl = "https://fanyi.youdao.com/";
    } else if (engineStr == "bing") {
      checkUrl = "https://www.bing.com/ttranslatev3";
    }

    if (checkUrl.isEmpty) return true;

    try {
      final res = await translate("ping");
      return res.isNotEmpty && 
             res.toLowerCase() != "ping" && 
             !res.contains("linux.do") && 
             !res.contains("http");
    } catch (_) {
      return false;
    }
  }

  /// The main entry point for translation with automatic fallback
  static Future<String> translate(String text) async {
    final engineStr = ConfigService.get("translation_engine") ?? "auto";
    
    if (engineStr == "google") return _googleTranslate(text);
    if (engineStr == "mymemory") return _myMemoryTranslate(text);
    if (engineStr == "libre") return _libreTranslate(text);
    if (engineStr == "deepl") return _deepLTranslate(text);
    if (engineStr == "sogou") return _sogouTranslate(text);
    if (engineStr == "youdao") return _youdaoTranslate(text);
    if (engineStr == "bing") return _bingTranslate(text);

    // Auto Mode: Try in order of perceived reliability/quality
    final engines = [
      _googleTranslate,
      _bingTranslate,
      _deepLTranslate,
      _myMemoryTranslate,
      _sogouTranslate,
      _youdaoTranslate,
      _libreTranslate,
    ];

    for (var engineFunc in engines) {
      try {
        return await engineFunc(text);
      } catch (e) {
        debugPrint("Auto fallback skipping an engine: $e");
      }
    }
    
    return text; // Everything failed
  }

  // Compatibility for older calls
  static Future<String> googleTranslate(String text) => translate(text);

  static Future<String> _googleTranslate(String text) async {
    final lang = _getMappedLang(ConfigService.getLanguage(), TranslationEngine.google);
    final source = _protectBrands(text);

    for (var endpoint in _googleEndpoints) {
      try {
        final response = await _dio.get(
          endpoint,
          queryParameters: {"client": "gtx", "sl": "auto", "tl": lang, "dt": "t", "q": source},
        ).timeout(const Duration(seconds: 5));

        if (response.statusCode == 200 && response.data is List) {
          final List parts = response.data[0];
          var result = parts.map((p) => p[0]).join();
          return _restoreBrands(result);
        }
      } catch (e) {
        logger.warning("Google endpoint failed ($endpoint): $e", LogSource.network);
      }
    }
    throw Exception("Google Translate failed");
  }

  static Future<String> _deepLTranslate(String text) async {
    final lang = _getMappedLang(ConfigService.getLanguage(), TranslationEngine.deepl);
    final source = _protectBrands(text);

    for (var mirror in _deeplMirrors) {
      try {
        final response = await _dio.post(
          mirror,
          data: {"text": source, "target_lang": lang},
        ).timeout(const Duration(seconds: 8));

        if (response.statusCode == 200) {
          final result = _restoreBrands(response.data['data'] ?? response.data['translated_text'] ?? "");
          if (result.contains("linux.do") || result.startsWith("http")) {
            throw Exception("DeepL mirror returned a metadata link");
          }
          return result;
        }
      } catch (e) {
        logger.warning("DeepL mirror failed ($mirror): $e", LogSource.network);
      }
    }
    throw Exception("DeepL failed");
  }

  static Future<String> _myMemoryTranslate(String text) async {
    final lang = _getMappedLang(ConfigService.getLanguage(), TranslationEngine.mymemory);
    final source = _protectBrands(text);
    
    try {
      final response = await _dio.get(
        "https://api.mymemory.translated.net/get",
        queryParameters: {"q": source, "langpair": "en|$lang"},
      ).timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final data = response.data;
        if (data['responseData'] != null) {
          return _restoreBrands(data['responseData']['translatedText']);
        }
      }
    } catch (e) {
      logger.warning("MyMemory failed: $e", LogSource.network);
    }
    throw Exception("MyMemory failed");
  }

  static Future<String> _sogouTranslate(String text) async {
    final lang = _getMappedLang(ConfigService.getLanguage(), TranslationEngine.sogou);
    final source = _protectBrands(text);

    try {
      final response = await _dio.post(
        "https://fanyi.sogou.com/revent_api/translate",
        data: {
          "from": "auto",
          "to": lang == "zh" ? "zh-CHS" : lang,
          "text": source,
          "client": "web",
          "uuid": _generateUuid(),
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        return _restoreBrands(response.data['translate']['outputs'][0]['output'] ?? "");
      }
    } catch (e) {
      logger.warning("Sogou failed: $e", LogSource.network);
    }
    throw Exception("Sogou failed");
  }

  static Future<String> _youdaoTranslate(String text) async {
    final lang = _getMappedLang(ConfigService.getLanguage(), TranslationEngine.youdao);
    final source = _protectBrands(text);

    try {
      final response = await _dio.post(
        "https://fanyi.youdao.com/translate?smartresult=dict&smartresult=rule",
        data: {
          "i": source,
          "from": "AUTO",
          "to": lang.toUpperCase(),
          "smartresult": "dict",
          "client": "fanyideskweb",
          "doctype": "json",
          "version": "2.1",
          "keyfrom": "fanyi.web",
          "action": "FY_BY_REALTME"
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final List transResults = response.data['translateResult']?[0] ?? [];
        final result = transResults.map((e) => e['tgt']).join("");
        return _restoreBrands(result);
      }
    } catch (e) {
      logger.warning("Youdao failed: $e", LogSource.network);
    }
    throw Exception("Youdao failed");
  }

  static Future<String> _libreTranslate(String text) async {
    final lang = _getMappedLang(ConfigService.getLanguage(), TranslationEngine.libre);
    final source = _protectBrands(text);

    for (var instance in _libreInstances) {
      try {
        final response = await _dio.post(
          instance,
          data: {"q": source, "source": "auto", "target": lang, "format": "text"},
          options: Options(contentType: Headers.formUrlEncodedContentType),
        ).timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          return _restoreBrands(response.data['translatedText']);
        }
      } catch (e) {
        logger.warning("LibreTranslate failed ($instance): $e", LogSource.network);
      }
    }
    throw Exception("LibreTranslate failed");
  }

  static Future<String> _bingTranslate(String text) async {
    final lang = _getMappedLang(ConfigService.getLanguage(), TranslationEngine.bing);
    final source = _protectBrands(text);

    try {
      if (_bingCookie == null) {
        await _refreshBingSession();
      }

      final response = await _dio.post(
        "https://www.bing.com/ttranslatev3?isVertical=1",
        data: {
          "fromLang": "auto-detect",
          "to": lang,
          "text": source,
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Referer": "https://www.bing.com/translator",
            "Cookie": ?_bingCookie,
          },
        ),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final List results = response.data;
        if (results.isNotEmpty) {
          final translated = results[0]['translations'][0]['text'];
          return _restoreBrands(translated);
        }
      }
    } catch (e) {
      _bingCookie = null;
      logger.warning("Bing Translate failed: $e", LogSource.network);
    }
    throw Exception("Bing failed");
  }

  static Future<void> _refreshBingSession() async {
    try {
      final response = await _dio.get(
        "https://www.bing.com/translator?setlang=zh-cn",
        options: Options(
          headers: {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
          },
        ),
      ).timeout(const Duration(seconds: 5));

      final cookies = response.headers['set-cookie'];
      if (cookies != null) {
        _bingCookie = cookies.map((c) => c.split(';').first).join('; ');
      }
    } catch (e) {
      logger.warning("Failed to refresh Bing session: $e", LogSource.network);
    }
  }

  static String _generateUuid() {
    final random = Random();
    return List.generate(32, (index) => random.nextInt(16).toRadixString(16)).join();
  }

  static String _protectBrands(String text) {
    final Map<String, String> protectionMap = {
      "百络谷": "___BLORET_P___",
      "络可": "___BLORIKO_P___",
      "ロコ": "___BLORIKO_P___",
      "Блорико": "___BLORIKO_P___",
      "Blora": "___BLORA_P___",
      "BloretLauncher": "___BL_LAUNCHER_P___",
      "Bloret Launcher": "___BL_LAUNCHER_P___",
      "RinUI": "___RINUI_P___",
      "Hoshivetw": "___HOSHIVETW_P___",
    };

    String source = text;
    protectionMap.forEach((key, placeholder) {
      source = source.replaceAll(key, placeholder);
    });
    return source;
  }

  static String _restoreBrands(String text) {
    String restore(String content, String placeholder, String brand) {
      final escaped = placeholder.replaceAll('_', r'[_ ]*');
      return content.replaceAll(RegExp(escaped, caseSensitive: false), brand);
    }

    var result = text;
    result = restore(result, "___BLORET_P___", "Bloret");
    result = restore(result, "___BLORIKO_P___", "Bloriko");
    result = restore(result, "___BLORA_P___", "Blora");
    result = restore(result, "___BL_LAUNCHER_P___", "Bloret Launcher");
    result = restore(result, "___RINUI_P___", "RinUI");
    result = restore(result, "___HOSHIVETW_P___", "Hoshivetw");
    
    // Legacy support
    result = result.replaceAll("___BORET_P___", "Bloret");
    return result;
  }
}
