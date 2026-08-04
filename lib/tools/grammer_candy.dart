import 'dart:ui';

extension WithOpacity on Color {
  Color withOpacityEx(double opacity) => withAlpha((opacity * 255).toInt());
}