import 'dart:convert';
import 'dart:io';
import 'package:bloret_launcher/services/config_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'global.dart';

class I18n extends ChangeNotifier {
  static final I18n instance = I18n._();
  I18n._();

  static Map<String, String> _localizedValues = {};
  static String _currentLang = 'en_us';
  static final Set<String> _calledKeys = {};
  static final Map<String, String> _missingValues = {};
  static bool _isSavingMissing = false;

  static String get currentLang => _currentLang;

  /// Initialize internationalization settings
  static Future<void> init() async {
    final lang = ConfigService.getLanguage();
    await _loadMissingKeys();
    await load(lang);
  }

  static Future<void> _loadMissingKeys() async {
    try {
      final customDir = await getCustomLangDir();
      final file = File(p.join(customDir.path, 'missing_keys.json'));
      if (await file.exists()) {
        await file.delete();
        await file.create();
      }
    } catch (_) {}
  }

  static Future<void> _saveMissingKeys() async {
    if (_isSavingMissing) return;
    _isSavingMissing = true;
    try {
      final customDir = await getCustomLangDir();
      final file = File(p.join(customDir.path, 'missing_keys.json'));
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(_missingValues),
        mode: FileMode.write,
        flush: true,
      );
    } catch (_) {} finally {
      _isSavingMissing = false;
    }
  }

  static Future<Directory> getCustomLangDir() async {
    Directory? baseDir = await getSupportData();
    final dir = Directory(p.join(baseDir.path, 'lang'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Loads the translation map for a specific language code (e.g., 'zh_cn', 'en_us', 'ja_jp')
  /// Expected asset path: assets/lang/{lang}.json OR appSupport/lang/{lang}.json
  static Future<void> load(String lang) async {
    try {
      String jsonString;
      final customDir = await getCustomLangDir();
      final customFile = File(p.join(customDir.path, '$lang.json'));

      if (await customFile.exists()) {
        jsonString = await customFile.readAsString();
      } else {
        jsonString = await rootBundle.loadString('assets/lang/$lang.json');
      }

      final Map<String, dynamic> jsonMap = json.decode(jsonString);

      _localizedValues.clear();
      _localizedValues = jsonMap.map((key, value) => MapEntry(key, value.toString()));
      _currentLang = lang;

      // Clear translation cache when language changes
      TranslationStore.resetCache();

      instance.notifyListeners();

    } catch (e) {
      if (lang != 'en_us') {
        await load('en_us');
      } else {
        _localizedValues = {};
        _currentLang = 'en_us';
        instance.notifyListeners();
      }
    }
  }

  static Future<Map<String, String>> getAvailableLanguages() async {
    final Map<String, String> langs = {
      'en_us': 'English (US)',
      'zh_cn': '简体中文',
      'ja_jp': '日本語',
      'ru_ru': 'Русский'
    };

    try {
      final customDir = await getCustomLangDir();
      final files = customDir.listSync().whereType<File>().where((f) => f.path.endsWith('.json'));
      for (final f in files) {
        final content = await f.readAsString();
        final Map<String, dynamic> jsonMap = json.decode(content);
        final name = jsonMap['__NAME__']?.toString();
        if (name != null) {
          final langKey = p.basenameWithoutExtension(f.path);
          langs[langKey] = name;
        }
      }
    } catch (_) {}
    return langs;
  }

  /// Translates a key based on the current loaded language
  static String translate(String key) {
    _calledKeys.add(key);
    final value = _localizedValues[key];
    
    if (value == null) {
      if (!_missingValues.containsKey(key)) {
        _missingValues[key] = "";
        _saveMissingKeys();
      }
      if (_currentLang != 'en_us') debugPrint("----------MISSING KEY: $key-----------");
    }

    return value ?? key;
  }

  /// Returns all keys that have been called via .tl as a sorted JSON string
  static String getCalledKeysJson() {
    final List<String> sortedKeys = _calledKeys.toList()..sort();
    final Map<String, String> exportMap = { 
      "__NAME__": "New Language",
      for (var k in sortedKeys) k: k 
    };
    return const JsonEncoder.withIndent('  ').convert(exportMap);
  }
}

extension I18nExtension on String {
  /// Internationalization syntax sugar. Use as: 'my_key'.tl
  String get tl => I18n.translate(this);
}
