import 'package:flutter/material.dart';

final Map<String, Color> appThemeColors = {
  "classic_blue": const Color(0xFF0078D4),
  "light_blue": Colors.lightBlue,
  "mint_green": const Color(0xFF98FF98),
  "sunrise_orange": const Color(0xFFFFA500),
  "glacier_gray": const Color(0xFFB0C4DE),
  "hoshino_pink": const Color(0xFFF1AEBA),
  "deep_sea": const Color(0xFF003366),
  "cosmic_purple": const Color(0xFF6A0DAD),
  "desert_gold": const Color(0xFFDAA520),
};

ThemeData buildAppTheme(Color seedColor, Brightness brightness) {
  final bool isDark = brightness == Brightness.dark;

  final Color baseBg = isDark
      ? const Color(0xFF121212)
      : const Color(0xFFF9F9F9);

  final Color tintedBg = Color.alphaBlend(
    seedColor.withValues(alpha: isDark ? 0.04 : 0.06),
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
    scaffoldBackgroundColor: tintedBg,
    cardTheme: CardTheme(
      elevation: 0,
      color: isDark ? null : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isDark
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.black.withValues(alpha: 0.12),
        ),
      ),
    ).data,
    buttonTheme: ButtonThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isDark
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.black.withValues(alpha: 0.1),
        ),
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
