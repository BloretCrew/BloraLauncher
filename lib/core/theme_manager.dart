import 'package:flutter/material.dart';

import '../services/config_service.dart';
import 'theme.dart';

class ThemeManager extends ChangeNotifier {
  static final ThemeManager instance = ThemeManager._();
  ThemeManager._();

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

    // Default color if none set
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
    await ConfigService.set(
      "theme_seed_color",
      null,
    ); // Clear custom hex if selecting preset
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
