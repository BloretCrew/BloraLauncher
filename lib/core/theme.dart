import 'package:flutter/material.dart';

final Map<String, Color> appThemeColors = {
  "classic_blue": const Color(0xFF0078D4),
  "light_blue": Colors.lightBlue,
  "mint_green": const Color(0xFF98FF98),
  "cosmic_purple": const Color(0xFF6A0DAD),
  "sunrise_orange": const Color(0xFFFFA500),
  "glacier_gray": const Color(0xFFB0C4DE),
  "hoshino_pink": const Color(0xFFF1AEBA),
  "deep_sea": const Color(0xFF003366),
  "desert_gold": const Color(0xFFDAA520),
};

ThemeData buildAppTheme(Color seedColor, Brightness brightness) {
  // 计算带有淡淡主题色的背景色
  final Color baseBg = brightness == Brightness.dark
      ? const Color(0xFF121212)
      : const Color(0xFFF9F9F9);

  // 混合 4% 的主题色到背景中，使其拥有极淡的色调感
  final Color tintedBg = Color.alphaBlend(
    seedColor.withValues(alpha: 0.04),
    baseBg,
  );

  final scheme = ColorScheme.fromSeed(
    seedColor: seedColor,
    brightness: brightness,
    surface: tintedBg,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: brightness == Brightness.dark
        ? tintedBg
        : Colors.transparent,
    cardTheme: CardTheme(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: brightness == Brightness.dark
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.grey.withValues(alpha: 0.2),
        ),
      ),
    ).data,
    buttonTheme: ButtonThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
      ),
    ),
    fontFamily: "Microsoft",
    textTheme: const TextTheme().apply(fontFamily: "Microsoft"),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: scheme.primary,
      elevation: 0,
    ),
  );
}
