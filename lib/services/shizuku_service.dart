import 'dart:io';
import 'package:flutter/services.dart';

import '../core/android_bridge.dart';

class ShizukuService {
  /// 初始化 Shizuku
  /// 返回值: 0-成功, 1-失败, 2-不支持, 3-正在运行, -1-未知
  static Future<int> init() async {
    if (!Platform.isAndroid) return 2;
    try {
      final int result = await methodChannel.invokeMethod('initShizuku');
      return result;
    } on PlatformException catch (_) {
      return 1;
    }
  }

  /// 检查 Shizuku 权限
  static Future<bool> checkPermission() async {
    if (!Platform.isAndroid) return false;
    try {
      final bool result = await methodChannel.invokeMethod('checkShizukuPermission');
      return result;
    } on PlatformException catch (_) {
      return false;
    }
  }

  /// 使用 Shizuku 执行 Shell 命令
  static Future<String> runShell(String command) async {
    if (!Platform.isAndroid) return "Error: Not supported on this platform";
    try {
      final String result = await methodChannel.invokeMethod('runShizukuShell', {
        'command': command,
      });
      return result;
    } on PlatformException catch (e) {
      return "Error: ${e.message}";
    }
  }
}
