import 'package:flutter/material.dart';

import '../services/config_service.dart';
import 'theme.dart';

class ThemeManager extends ChangeNotifier {
  static final ThemeManager instance = ThemeManager._();
  ThemeManager._();

  // Background Settings
  String? get backgroundImage => ConfigService.get("bg_image");
  double get backgroundBlur => (ConfigService.get("bg_blur") ?? 0.0).toDouble();
  double get backgroundOpacity => (ConfigService.get("bg_opacity") ?? 1.0).toDouble();
  double get backgroundOffsetX => (ConfigService.get("bg_offset_x") ?? 0.0).toDouble();
  double get backgroundOffsetY => (ConfigService.get("bg_offset_y") ?? 0.0).toDouble();
  double get backgroundScale => (ConfigService.get("bg_scale") ?? 1.0).toDouble();
  double get backgroundRotation => (ConfigService.get("bg_rotation") ?? 0.0).toDouble();

  Future<void> setBackgroundConfig({
    String? image,
    double? blur,
    double? opacity,
    double? offsetX,
    double? offsetY,
    double? scale,
    double? rotation,
  }) async {
    if (image != null) await ConfigService.set("bg_image", image);
    if (blur != null) await ConfigService.set("bg_blur", blur);
    if (opacity != null) await ConfigService.set("bg_opacity", opacity);
    if (offsetX != null) await ConfigService.set("bg_offset_x", offsetX);
    if (offsetY != null) await ConfigService.set("bg_offset_y", offsetY);
    if (scale != null) await ConfigService.set("bg_scale", scale);
    if (rotation != null) await ConfigService.set("bg_rotation", rotation);
    notifyListeners();
  }

  ThemeMode get themeMode {
    final mode = ConfigService.get("theme_mode") ?? "Auto";
    switch (mode) {
      case "Light":
        return ThemeMode.light;
      case "Dark":
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  Color get seedColor {
    final colorHex = ConfigService.get("theme_seed_color");
    if (colorHex != null && colorHex is String) {
      try {
        return Color(int.parse(colorHex, radix: 16));
      } catch (_) {}
    }

    final colorKey = ConfigService.get("theme_color_key") ?? "classic_blue";
    return appThemeColors[colorKey] ?? const Color(0xFF0078D4);
  }

  ThemeData getTheme(Brightness brightness) {
    return buildAppTheme(seedColor, brightness);
  }

  void updateTheme() {
    notifyListeners();
  }

  Future<void> setThemeColor(String key) async {
    await ConfigService.set("theme_color_key", key);
    await ConfigService.set("theme_seed_color", null);
    notifyListeners();
  }

  Future<void> setCustomSeedColor(Color color) async {
    await ConfigService.set(
      "theme_seed_color",
      color.toARGB32().toRadixString(16),
    );
    notifyListeners();
  }
}
