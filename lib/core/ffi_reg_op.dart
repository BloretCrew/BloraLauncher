import 'dart:ffi';

import 'package:ffi/ffi.dart';

class WindowsRegedit {
  static const int _hkeyCurrentUser = 0x80000001;
  static const int _regSz = 1;
  static const int _keyWrite = 0x20006;

  static final DynamicLibrary _advapi32 =
  DynamicLibrary.open('advapi32.dll');

  static final int Function(
      int,
      Pointer<Utf16>,
      int,
      Pointer<Utf16>,
      int,
      int,
      Pointer<Void>,
      Pointer<IntPtr>,
      Pointer<Uint32>,
      ) _regCreateKeyExW = _advapi32.lookupFunction<
      Int32 Function(
          IntPtr,
          Pointer<Utf16>,
          Uint32,
          Pointer<Utf16>,
          Uint32,
          Uint32,
          Pointer<Void>,
          Pointer<IntPtr>,
          Pointer<Uint32>,
          ),
      int Function(
          int,
          Pointer<Utf16>,
          int,
          Pointer<Utf16>,
          int,
          int,
          Pointer<Void>,
          Pointer<IntPtr>,
          Pointer<Uint32>,
          )>('RegCreateKeyExW');

  static final int Function(
      int,
      Pointer<Utf16>,
      int,
      int,
      Pointer<Uint8>,
      int,
      ) _regSetValueExW = _advapi32.lookupFunction<
      Int32 Function(
          IntPtr,
          Pointer<Utf16>,
          Uint32,
          Uint32,
          Pointer<Uint8>,
          Uint32,
          ),
      int Function(
          int,
          Pointer<Utf16>,
          int,
          int,
          Pointer<Uint8>,
          int,
          )>('RegSetValueExW');

  static final int Function(int) _regCloseKey =
  _advapi32.lookupFunction<
      Int32 Function(IntPtr),
      int Function(int)>('RegCloseKey');

  static int _createKey(String path) {
    final subKey = path.toNativeUtf16();
    final result = calloc<IntPtr>();
    final disposition = calloc<Uint32>();

    try {
      final code = _regCreateKeyExW(
        _hkeyCurrentUser,
        subKey,
        0,
        nullptr,
        0,
        _keyWrite,
        nullptr,
        result,
        disposition,
      );

      if (code != 0) {
        throw StateError(
          'RegCreateKeyExW failed: $code',
        );
      }

      return result.value;
    } finally {
      calloc.free(subKey);
      calloc.free(result);
      calloc.free(disposition);
    }
  }

  static void _setString(
      int key,
      String name,
      String value,
      ) {
    final namePtr = name.toNativeUtf16();
    final valuePtr = value.toNativeUtf16();

    try {
      final code = _regSetValueExW(
        key,
        namePtr,
        0,
        _regSz,
        valuePtr.cast<Uint8>(),
        (value.length + 1) * 2,
      );

      if (code != 0) {
        throw StateError(
          'RegSetValueExW failed: $code',
        );
      }
    } finally {
      calloc.free(namePtr);
      calloc.free(valuePtr);
    }
  }

  static void registerProtocol(String exePath) {
    final protocolKey = _createKey(
      r'Software\Classes\bloralauncher',
    );

    try {
      _setString(
        protocolKey,
        '',
        'URL:Blora Launcher Protocol',
      );

      _setString(
        protocolKey,
        'URL Protocol',
        '',
      );
    } finally {
      _regCloseKey(protocolKey);
    }

    final commandKey = _createKey(
      r'Software\Classes\bloralauncher\shell\open\command',
    );

    try {
      _setString(
        commandKey,
        '',
        '"$exePath" "%1"',
      );
    } finally {
      _regCloseKey(commandKey);
    }
  }
}