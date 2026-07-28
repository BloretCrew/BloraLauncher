import 'package:shared_preferences/shared_preferences.dart';

class ConfigService {
  static late SharedPreferences _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static bool isFirstRun() {
    return _prefs.getBool('is_first_run') ?? true;
  }

  static Future<void> setFirstRunCompleted() async {
    await _prefs.setBool('is_first_run', false);
  }

  static String getLanguage() {
    return _prefs.getString('language') ?? 'zh-cn';
  }

  static Future<void> setLanguage(String lang) async {
    await _prefs.setString('language', lang);
  }

  // Generic methods for other settings
  static dynamic get(String key) => _prefs.get(key);
  static Future<void> set(String key, dynamic value) async {
    if (value is String) await _prefs.setString(key, value);
    else if (value is bool) await _prefs.setBool(key, value);
    else if (value is int) await _prefs.setInt(key, value);
    else if (value is double) await _prefs.setDouble(key, value);
    else if (value is List<String>) await _prefs.setStringList(key, value);
  }
}
