import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

// Define FFI function prototypes
typedef SetAppIconNative = Void Function(IntPtr hwnd, Pointer<Utf16> iconPath);
typedef SetAppIconDart = void Function(int hwnd, Pointer<Utf16> iconPath);

// User32 GetActiveWindow
typedef GetActiveWindowNative = IntPtr Function();
typedef GetActiveWindowDart = int Function();

class Win32IconService {
  static late DynamicLibrary _executable;
  static late SetAppIconDart _setAppIcon;
  static late GetActiveWindowDart _getActiveWindow;

  static void init() {
    if (!Platform.isWindows) return;

    try {
      // DynamicLibrary.executable() points to the running .exe which contains our exported SetAppIcon
      _executable = DynamicLibrary.executable();
      _setAppIcon = _executable.lookupFunction<SetAppIconNative, SetAppIconDart>('SetAppIcon');

      // Standard user32.dll for window management
      final user32 = DynamicLibrary.open('user32.dll');
      _getActiveWindow = user32.lookupFunction<GetActiveWindowNative, GetActiveWindowDart>('GetActiveWindow');
    } catch (e) {
      print('Failed to initialize Win32 FFI: $e');
    }
  }

  static Future<void> switchIcon(bool isDark) async {
    if (!Platform.isWindows) return;

    // Use absolute paths from extracted assets
    final String iconName = isDark ? 'bloret_dark.ico' : 'bloret_light.ico';

    final assetPath = 'assets/$iconName';
    
    try {
      final tempDir = await getTemporaryDirectory();
      final iconFile = File(p.join(tempDir.path, iconName));
      
      final byteData = await rootBundle.load(assetPath);
      await iconFile.writeAsBytes(byteData.buffer.asUint8List());

      final hwnd = _getActiveWindow();
      if (hwnd == 0) return;

      final pIconPath = iconFile.path.toNativeUtf16();
      _setAppIcon(hwnd, pIconPath);
      malloc.free(pIconPath);
    } catch (e) {
      print('Error switching Windows icon: $e');
    }
  }
}
