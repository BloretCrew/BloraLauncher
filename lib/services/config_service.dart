import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bloret_launcher/core/i18n.dart';
import 'package:bloret_launcher/services/bloriko.dart';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:encrypt/encrypt.dart' as encrypt_lib;
import 'package:flutter/cupertino.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ConfigService {
  static SharedPreferences? _prefs;
  static Map<String, dynamic> _desktopConfig = {};
  static File? _file;
  static String? lastError;

  static const String _fallbackKeySeed = "BLORET_INTERNAL_STABLE_KEY_2026";
  static const String _commonExportSeed = "BLORET_MIGRATION_COMMON_KEY";

  static bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  static Future<void> init() async {
    if (_isMobile) {
      _prefs = await SharedPreferences.getInstance();
    } else {
      Directory dir = await getSupportData();
      final oldJsonFile = File("${dir.path}/config.json");
      final newDatFile = File("${dir.path}/config.dat");
      _file = newDatFile;

      if (await oldJsonFile.exists() && !await newDatFile.exists()) {
        try {
          String content = await oldJsonFile.readAsString();
          _desktopConfig = jsonDecode(content);
          await _saveEncryptedDesktopConfig();
          await oldJsonFile.delete();
        } catch (e) {
          lastError =
              "Failed to read the old configuration file. Reset to default settings.";
          _desktopConfig = {};
        }
      }

      if (await newDatFile.exists()) {
        try {
          String encryptedData = await newDatFile.readAsString();
          String decrypted = await _decrypt(
            encryptedData,
            await _getEncryptionKey(),
          );
          _desktopConfig = jsonDecode(decrypted);
        } catch (e) {
          lastError =
              "Failed to decrypt the configuration file. Reset to default settings.";
          try {
            String encryptedData = await newDatFile.readAsString();
            String decrypted = await _decrypt(
              encryptedData,
              _deriveKey(_fallbackKeySeed),
            );
            _desktopConfig = jsonDecode(decrypted);
          } catch (e2) {
            lastError =
                "Failed to decrypt the configuration file: the hardware identifier may have changed or the file may be corrupted. Reset to default settings.";
            _desktopConfig = {};
          }
        }
      }
    }
  }

  static Future<encrypt_lib.Key> _getEncryptionKey() async {
    String? hwId = await _getHardwareId();
    return _deriveKey(hwId ?? _fallbackKeySeed);
  }

  static encrypt_lib.Key _deriveKey(String seed) {
    final hash = sha256.convert(utf8.encode(seed)).bytes;
    return encrypt_lib.Key(Uint8List.fromList(hash));
  }

  static Future<String?> _getHardwareId() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isWindows) {
        final winInfo = await deviceInfo.windowsInfo;
        return winInfo.deviceId;
      } else if (Platform.isMacOS) {
        final macInfo = await deviceInfo.macOsInfo;
        return macInfo.systemGUID;
      } else if (Platform.isLinux) {
        final linuxInfo = await deviceInfo.linuxInfo;
        return linuxInfo.machineId;
      }
    } catch (_) {}
    return null;
  }

  static Future<String> _encrypt(String plainText, encrypt_lib.Key key) async {
    final iv = encrypt_lib.IV.fromSecureRandom(16);
    final encrypter = encrypt_lib.Encrypter(encrypt_lib.AES(key));
    final encrypted = encrypter.encrypt(plainText, iv: iv);
    return "${iv.base64}:${encrypted.base64}";
  }

  static Future<String> _decrypt(
    String cipherTextWithIv,
    encrypt_lib.Key key,
  ) async {
    final parts = cipherTextWithIv.split(':');
    if (parts.length != 2) throw Exception("Invalid format");
    final iv = encrypt_lib.IV.fromBase64(parts[0]);
    final encrypter = encrypt_lib.Encrypter(encrypt_lib.AES(key));
    return encrypter.decrypt64(parts[1], iv: iv);
  }

  static Future<void> _saveEncryptedDesktopConfig() async {
    if (_file == null) return;
    try {
      String plainText = const JsonEncoder.withIndent(
        "  ",
      ).convert(_desktopConfig);
      String encrypted = await _encrypt(plainText, await _getEncryptionKey());

      final tmpFile = File("${_file!.path}.tmp");
      await tmpFile.writeAsString(encrypted, flush: true);

      if (await _file!.exists()) {
        await _file!.delete();
      }
      await tmpFile.rename(_file!.path);
    } catch (e) {
      debugPrint("Config save failed: $e");
    }
  }

  static Future<File?> exportCommonEncryptedConfig(String targetPath) async {
    try {
      final commonKey = _deriveKey(_commonExportSeed);
      String plainText = jsonEncode(_desktopConfig);
      String encrypted = await _encrypt(plainText, commonKey);
      final file = File(targetPath);
      return await file.writeAsString(encrypted);
    } catch (e) {
      return null;
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
      await _saveEncryptedDesktopConfig();
    }
  }

  static bool isFirstRun() {
    return get("is_first_run") ?? true;
  }

  static Future<void> setFirstRunCompleted() {
    Bloriko.getInstance();
    return set("is_first_run", false);
  }

  static String getLanguage() {
    return get("language") ?? "zh_cn";
  }

  static Future<void> setLanguage(String lang) async {
    I18n.load(lang);
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
  if (Platform.isAndroid || Platform.isIOS || Platform.isLinux) {
    return await getApplicationSupportDirectory();
  }

  final exeDir = File(Platform.resolvedExecutable).parent;
  final dir = Directory("${exeDir.path}/support_data");

  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }

  return dir;
}
