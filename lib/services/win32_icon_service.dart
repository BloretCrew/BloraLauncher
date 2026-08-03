import 'dart:ffi';
import 'dart:io';

typedef SetIconThemeNative = Void Function(Bool dark);
typedef SetIconThemeDart = void Function(bool dark);

class Win32IconService {
  static late SetIconThemeDart _setIconTheme;

  static void init() {
    if (!Platform.isWindows) return;

    final lib = DynamicLibrary.executable();

    _setIconTheme = lib.lookupFunction<
        SetIconThemeNative,
        SetIconThemeDart
    >('SetIconTheme');
  }

  static void switchIcon(bool dark) {
    _setIconTheme(dark);
  }
}