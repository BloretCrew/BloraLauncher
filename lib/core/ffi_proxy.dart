import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/cupertino.dart';

final DynamicLibrary _executable = DynamicLibrary.executable();
final DynamicLibrary _kernel32 = DynamicLibrary.open("kernel32.dll");

final class MemoryStatusEx extends Struct {
  @Uint32()
  external int dwLength;
  @Uint32()
  external int dwMemoryLoad;
  @Uint64()
  external int ullTotalPhys;
  @Uint64()
  external int ullAvailPhys;
  @Uint64()
  external int ullTotalPageFile;
  @Uint64()
  external int ullAvailPageFile;
  @Uint64()
  external int ullTotalVirtual;
  @Uint64()
  external int ullAvailVirtual;
  @Uint64()
  external int ullAvailExtendedVirtual;
}

typedef GlobalMemoryStatusExNative =
    Int32 Function(Pointer<MemoryStatusEx> lpBuffer);
typedef GlobalMemoryStatusExDart =
    int Function(Pointer<MemoryStatusEx> lpBuffer);

class WinSystem {
  static final _getMemStatus = Platform.isWindows
      ? _kernel32.lookupFunction<
          GlobalMemoryStatusExNative,
          GlobalMemoryStatusExDart
        >("GlobalMemoryStatusEx")
      : null;

  static Map<String, double> getMemoryInfo() {
    if (_getMemStatus == null) return {"total": 16.0, "free": 8.0};

    final pointer = calloc<MemoryStatusEx>();
    pointer.ref.dwLength = sizeOf<MemoryStatusEx>();

    try {
      final result = _getMemStatus!(pointer);
      if (result != 0) {
        return {
          "total": pointer.ref.ullTotalPhys / (1024 * 1024 * 1024),
          "free": pointer.ref.ullAvailPhys / (1024 * 1024 * 1024),
        };
      }
    } finally {
      calloc.free(pointer);
    }
    return {"total": 16.0, "free": 8.0};
  }

  static bool showNotification(String title, String body) {
    if (!Platform.isWindows) return false;
    try {
      final titlePtr = title.toNativeUtf16();
      final bodyPtr = body.toNativeUtf16();
      try {
        return _showNotificationNative(titlePtr, bodyPtr);
      } finally {
        malloc.free(titlePtr);
        malloc.free(bodyPtr);
      }
    } catch (e) {
      debugPrint("FFI Error: $e");
      return false;
    }
  }

  static final _showNotificationNative = _executable.lookupFunction<
      Bool Function(Pointer<Utf16>, Pointer<Utf16>),
      bool Function(Pointer<Utf16>, Pointer<Utf16>)
  >('ShowWindowsNotification');

  static int isBloraLauncher(String path) {
    final pathPtr = path.toNativeUtf8();
    try {
      return _isBloraLauncher(pathPtr);
    } finally {
      malloc.free(pathPtr);
    }
  }

  static final _isBloraLauncher = _executable.lookupFunction<
      Uint8 Function(Pointer<Utf8>),
      int Function(Pointer<Utf8>)>('IsBloraLauncherUtf8');
}

typedef SetProgressNative = Void Function(Uint64 completed, Uint64 total);
typedef SetProgressDart = void Function(int completed, int total);

typedef SetStateNative = Void Function(Int32 state);
typedef SetStateDart = void Function(int state);

typedef SetIconThemeNative = Void Function(Bool dark);
typedef SetIconThemeDart = void Function(bool dark);

final terminateProcess = _executable
    .lookupFunction<Void Function(), void Function()>("c_terminate_process");

typedef ProcessPidNative = Void Function(Uint32 pid);
typedef ProcessPidDart = void Function(int pid);

typedef EfficiencyModeNative = Void Function(Uint32 pid, Bool enable);
typedef EfficiencyModeDart = void Function(int pid, bool enable);

typedef ExtractIconNative =
    Int32 Function(Pointer<Utf16> exePath, Pointer<Utf16> savePath);
typedef ExtractIconDart =
    int Function(Pointer<Utf16> exePath, Pointer<Utf16> savePath);

class WinWindow {
  static void setFullscreen(bool enable) {
    if (!Platform.isWindows) return;
    try {
      final func = _executable
          .lookupFunction<Void Function(Bool), void Function(bool)>(
            "SetFullscreen",
          );
      func(enable);
    } catch (e) {
      debugPrint("FFI Error: $e");
    }
  }

  static void setAcrylic(bool enable) {
    if (!Platform.isWindows) return;
    try {
      final func = _executable
          .lookupFunction<Void Function(Bool), void Function(bool)>(
            "SetAcrylic",
          );
      func(enable);
    } catch (e) {
      debugPrint("FFI Error: $e");
    }
  }

  static final _setIconTheme = (Platform.isWindows || Platform.isLinux)
      ? _executable.lookupFunction<SetIconThemeNative, SetIconThemeDart>(
          "SetIconTheme",
        )
      : null;

  static void setIconTheme(bool dark) {
    _setIconTheme?.call(dark);
  }
}

class WinProcess {
  static final _suspend = Platform.isWindows
      ? _executable.lookupFunction<ProcessPidNative, ProcessPidDart>(
          "SuspendProcess",
        )
      : null;
  static final _resume = Platform.isWindows
      ? _executable.lookupFunction<ProcessPidNative, ProcessPidDart>(
          "ResumeProcess",
        )
      : null;
  static final _cleanRAM = Platform.isWindows
      ? _executable.lookupFunction<ProcessPidNative, ProcessPidDart>(
          "CleanProcessRAM",
        )
      : null;
  static final _setEfficiency = Platform.isWindows
      ? _executable.lookupFunction<EfficiencyModeNative, EfficiencyModeDart>(
          "SetEfficiencyMode",
        )
      : null;
  static final _extractIcon = Platform.isWindows
      ? _executable.lookupFunction<ExtractIconNative, ExtractIconDart>(
          "ExtractHighResIcon",
        )
      : null;

  static void suspend(int pid) => _suspend?.call(pid);
  static void resume(int pid) => _resume?.call(pid);
  static void cleanRAM(int pid) => _cleanRAM?.call(pid);
  static void setEfficiencyMode(int pid, bool enable) =>
      _setEfficiency?.call(pid, enable);

  static int extractHighResIcon(String exePath, String savePath) {
    if (_extractIcon == null) return -1;
    final exePtr = exePath.toNativeUtf16();
    final savePtr = savePath.toNativeUtf16();
    try {
      return _extractIcon!(exePtr, savePtr);
    } finally {
      malloc.free(exePtr);
      malloc.free(savePtr);
    }
  }

  static final _getMem = Platform.isWindows
      ? _executable.lookupFunction<Uint64 Function(Uint32), int Function(int)>(
          "GetProcessMemoryUsage",
        )
      : null;
  static final _getCpu = Platform.isWindows
      ? _executable.lookupFunction<Uint64 Function(Uint32), int Function(int)>(
          "GetProcessCpuTime",
        )
      : null;
  static final _getCoreCount = Platform.isWindows
      ? _executable.lookupFunction<Int32 Function(), int Function()>(
          "GetCpuCoreCount",
        )
      : null;
  static final _isAlive = Platform.isWindows
      ? _executable.lookupFunction<Bool Function(Uint32), bool Function(int)>(
          "IsProcessAlive",
        )
      : null;

  static int getMemoryUsage(int pid) => _getMem?.call(pid) ?? 0;
  static int getCpuTime(int pid) => _getCpu?.call(pid) ?? 0;
  static int getCpuCoreCount() => _getCoreCount?.call() ?? 1;
  static bool isAlive(int pid) => _isAlive?.call(pid) ?? false;
}

final setClipboardImage = _executable
    .lookupFunction<
      Bool Function(Pointer<Uint8>, Int32, Int32),
      bool Function(Pointer<Uint8>, int, int)
    >("SetClipboardImage");

class WinTaskbar {
  static final _setProgress = (Platform.isWindows || Platform.isLinux)
      ? _executable.lookupFunction<SetProgressNative, SetProgressDart>(
          'SetTaskbarProgress',
        )
      : null;
  static final _setState = (Platform.isWindows || Platform.isLinux)
      ? _executable.lookupFunction<SetStateNative, SetStateDart>(
          'SetTaskbarState',
        )
      : null;

  /// TBPF_NOPROGRESS = 0, TBPF_INDETERMINATE = 1, TBPF_NORMAL = 2, TBPF_ERROR = 4, TBPF_PAUSED = 8
  static void setState(int state) {
    _setState?.call(state);
  }

  static void setProgress(int current, int total) {
    _setProgress?.call(current, total);
  }

  static void showProgress(int current, int total) {
    setState(2); // TBPF_NORMAL
    setProgress(current, total);
  }

  static void hideProgress() {
    setState(0); // TBPF_NOPROGRESS
  }

  static void setError() {
    setState(4); // TBPF_ERROR
  }

  static void setIndeterminate() {
    setState(1); // TBPF_INDETERMINATE
  }
}
