import 'dart:ffi';
import 'dart:io';

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

  static final _regOpenKeyExW = _advapi32.lookupFunction<
      Int32 Function(
          IntPtr,
          Pointer<Utf16>,
          Uint32,
          Uint32,
          Pointer<IntPtr>,
          ),
      int Function(
          int,
          Pointer<Utf16>,
          int,
          int,
          Pointer<IntPtr>,
          )
  >('RegOpenKeyExW');

  static final _regQueryValueExW = _advapi32.lookupFunction<
      Int32 Function(
          IntPtr,
          Pointer<Utf16>,
          Pointer<Uint32>,
          Pointer<Uint32>,
          Pointer<Uint8>,
          Pointer<Uint32>,
          ),
      int Function(
          int,
          Pointer<Utf16>,
          Pointer<Uint32>,
          Pointer<Uint32>,
          Pointer<Uint8>,
          Pointer<Uint32>,
          )
  >('RegQueryValueExW');

  static const int _keyRead = 0x20019;

  static bool isBloraProtocolAvailable() => isProtocolAvailable('bloralauncher');

  static bool isProtocolAvailable(String scheme) {
    final path = 'Software\\Classes\\$scheme\\shell\\open\\command';

    final pathPtr = path.toNativeUtf16();
    final keyPtr = calloc<IntPtr>();

    try {
      final openResult = _regOpenKeyExW(
        _hkeyCurrentUser,
        pathPtr,
        0,
        _keyRead,
        keyPtr,
      );

      if (openResult != 0) {
        return false;
      }

      final key = keyPtr.value;

      try {
        final valueName = ''.toNativeUtf16();
        final type = calloc<Uint32>();
        final size = calloc<Uint32>();

        try {
          final queryResult = _regQueryValueExW(
            key,
            valueName,
            nullptr,
            type,
            nullptr,
            size,
          );

          if (queryResult != 0 || size.value == 0) {
            return false;
          }

          final buffer = calloc<Uint8>(size.value);

          try {
            final result = _regQueryValueExW(
              key,
              valueName,
              nullptr,
              type,
              buffer,
              size,
            );

            if (result != 0) {
              return false;
            }

            final command = buffer
                .cast<Utf16>()
                .toDartString();

            final match = RegExp(
              r'^"([^"]+)"',
            ).firstMatch(command);

            if (match == null) {
              return false;
            }

            return File(match.group(1)!).existsSync();
          } finally {
            calloc.free(buffer);
          }
        } finally {
          calloc.free(valueName);
          calloc.free(type);
          calloc.free(size);
        }
      } finally {
        _regCloseKey(key);
      }
    } finally {
      calloc.free(pathPtr);
      calloc.free(keyPtr);
    }
  }
}