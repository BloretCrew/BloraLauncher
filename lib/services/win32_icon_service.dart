import 'dart:ffi';
import 'dart:io';

typedef SetIconThemeNative = Void Function(Bool dark);
typedef SetIconThemeDart = void Function(bool dark);

class Win32IconService {
  static late SetIconThemeDart _setIconTheme;

  static void init() {
    final lib = DynamicLibrary.executable();

    _setIconTheme = (Platform.isWindows || Platform.isLinux) ? lib.lookupFunction<
        SetIconThemeNative,
        SetIconThemeDart
    >('SetIconTheme') : (_) => {};
  }

  static void switchIcon(bool dark) {
    _setIconTheme(dark);
  }
}