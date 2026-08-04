import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ConfigService {
  static SharedPreferences? _prefs;
  static Map<String,dynamic> _desktopConfig = {};
  static File? _file;

  static bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  static Future<void> init() async {
    if (_isMobile) {
      _prefs = await SharedPreferences.getInstance();
    } else {
      Directory dir = await getSupportData();
      _file = File("${dir.path}/config.json");
      if (await _file!.exists()) {
        try {
          _desktopConfig = jsonDecode(await _file!.readAsString());
        } catch (_) {
          _desktopConfig = {};
        }
      }
    }
  }

  static dynamic get(String key) {
    if (_isMobile) return _prefs?.get(key);
    return _desktopConfig[key];
  }

  static Future<void> set(String key, dynamic value) async {
    if (_isMobile) {
      if (value is String) {
        await _prefs!.setString(key, value);
      } else if (value is bool) {
        await _prefs!.setBool(key, value);
      } else if (value is int) {
        await _prefs!.setInt(key, value);
      } else if (value is double) {
        await _prefs!.setDouble(key, value);
      } else if (value is List<String>) {
        await _prefs!.setStringList(key, value);
      }
    } else {
      _desktopConfig[key] = value;
      await _file!.writeAsString(
        const JsonEncoder.withIndent("  ").convert(_desktopConfig),
      );
    }
  }

  static bool isFirstRun() {
    return get("is_first_run") ?? true;
  }

  static Future<void> setFirstRunCompleted() {
    return set("is_first_run", false);
  }

  static String getLanguage() {
    return get("language") ?? "zh-cn";
  }

  static Future<void> setLanguage(String lang) {
    return set("language", lang);
  }

  static String getExitBehavior() {
    return get("exit_behavior") ?? "ask";
  }

  static Future<void> setExitBehavior(String behavior) async {
    await set("exit_behavior", behavior);
  }
}

Future<Directory> getSupportData() async {
  if (Platform.isAndroid || Platform.isIOS) {
    return await getApplicationSupportDirectory();
  }

  final exeDir =
      File(Platform.resolvedExecutable).parent;

  final dir =
  Directory("${exeDir.path}/support_data");

  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }

  return dir;
}