import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

final DynamicLibrary _executable = DynamicLibrary.executable();

// Win32 Priority Constants
const int IDLE_PRIORITY_CLASS = 0x00000040;
const int BELOW_NORMAL_PRIORITY_CLASS = 0x00004000;
const int NORMAL_PRIORITY_CLASS = 0x00000020;
const int ABOVE_NORMAL_PRIORITY_CLASS = 0x00008000;
const int HIGH_PRIORITY_CLASS = 0x00000080;
const int REALTIME_PRIORITY_CLASS = 0x00000100;

class NativeProcess {
  final int? _handle;
  final int _pid;
  final Process? _dartProcess;
  int? _cachedExitCode;
  bool _isDisposed = false;

  NativeProcess(this._handle, this._pid, {this._dartProcess});

  factory NativeProcess.fromPid(int pid) {
    if (!Platform.isWindows) return NativeProcess(null, pid);
    final handle = _openProcessNative(0x1F0FFF, false, pid);
    return NativeProcess(handle == 0 ? null : handle, pid);
  }

  int get pid => _pid;

  int? get exitCode {
    if (_cachedExitCode != null) return _cachedExitCode;
    
    if (_dartProcess != null) {
      return _cachedExitCode;
    }

    if (_handle == null || _handle == 0) return null;

    final code = _getExitCodeNative(_handle);
    if (code >= 0) {
      _cachedExitCode = code;
      return _cachedExitCode;
    }
    return null;
  }

  bool get hasExited => exitCode != null;

  Future<int> wait() async {
    if (_cachedExitCode != null) return _cachedExitCode!;
    
    if (_dartProcess != null) {
      _cachedExitCode = await _dartProcess.exitCode;
      return _cachedExitCode!;
    }

    if (_handle == null || _handle == 0) return 0;

    final result = await compute(_waitInIsolate, _handle);
    _cachedExitCode = result;
    return result;
  }

  static int _waitInIsolate(int handle) {
    return _waitNative(handle);
  }

  void terminate() {
    if (_isDisposed) return;
    if (_handle != null && _handle != 0) {
      _terminateNative(_handle);
    } else if (_dartProcess != null) {
      _dartProcess.kill();
    }
  }

  void setPriority(int priority) {
    if (_isDisposed) return;
    if (_handle != null && _handle != 0) {
      _setPriorityNative(_handle, priority);
    } else if (Platform.isWindows) {
      _setPriorityByIdNative(_pid, priority);
    }
  }

  void dispose() {
    if (_isDisposed) return;
    if (_handle != null && _handle != 0) {
      _closeHandleNative(_handle);
    }
    _isDisposed = true;
  }
}

class WindowsNativeProcessService {
  static Future<NativeProcess> launchProcess({
    required String executable,
    List<String> arguments = const [],
    String? workingDirectory,
    bool runAsAdmin = false,
    int? priority,
    Map<String, String>? environment,
    bool detached = false,
  }) async {
    if (Platform.isWindows) {
      final exePtr = executable.toNativeUtf16();
      final argsString = arguments.map((a) {
        if (a.contains(' ') || a.contains('"')) {
          return '"${a.replaceAll('"', '\\"')}"';
        }
        return a;
      }).join(' ');
      final argsPtr = argsString.toNativeUtf16();
      final workingDirPtr = workingDirectory?.toNativeUtf16() ?? nullptr;
      final pidPtr = calloc<Uint32>();

      try {
        final handle = _launchNative(
          exePtr,
          argsPtr,
          workingDirPtr,
          runAsAdmin,
          priority ?? NORMAL_PRIORITY_CLASS,
          pidPtr,
        );

        if (handle == 0) {
          throw Exception("Failed to launch native process: $executable");
        }

        return NativeProcess(handle, pidPtr.value);
      } finally {
        malloc.free(exePtr);
        malloc.free(argsPtr);
        if (workingDirPtr != nullptr) malloc.free(workingDirPtr);
        calloc.free(pidPtr);
      }
    } else {
      final process = await Process.start(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        environment: environment,
        mode: detached ? ProcessStartMode.detached : ProcessStartMode.normal,
      );
      return NativeProcess(null, process.pid, dartProcess: process);
    }
  }

  static void setPriorityByPid(int pid, int priority) {
    if (!Platform.isWindows) return;
    _setPriorityByIdNative(pid, priority);
  }

  static void terminateByPid(int pid) {
    if (!Platform.isWindows) return;
    // PROCESS_TERMINATE (0x0001)
    final hProcess = _openProcessNative(0x0001, false, pid);
    if (hProcess != 0 && hProcess != -1) {
      _terminateNative(hProcess);
      _closeHandleNative(hProcess);
    }
  }

  /// 运行一个瞬时进程并等待结束（替代 Process.run）
  static Future<int> runNative({
    required String executable,
    List<String> arguments = const [],
    String? workingDirectory,
    bool runAsAdmin = false,
  }) async {
    final process = await launchProcess(
      executable: executable,
      arguments: arguments,
      workingDirectory: workingDirectory,
      runAsAdmin: runAsAdmin,
    );
    final code = await process.wait();
    process.dispose();
    return code;
  }

  static List<Map<String, dynamic>> listProcesses() {
    if (!Platform.isWindows) return [];
    final ptr = _listProcessesNative();
    if (ptr == nullptr) return [];
    final jsonStr = ptr.toDartString();
    try {
      final List<dynamic> data = json.decode(jsonStr);
      return data.map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (e) {
      debugPrint("Failed to parse process list JSON: $e");
      return [];
    }
  }
}

// FFI Definitions
final _launchNative = _executable.lookupFunction<
    IntPtr Function(Pointer<Utf16>, Pointer<Utf16>, Pointer<Utf16>, Bool, Uint32, Pointer<Uint32>),
    int Function(Pointer<Utf16>, Pointer<Utf16>, Pointer<Utf16>, bool, int, Pointer<Uint32>)
>("LaunchNativeProcess");

final _closeHandleNative = _executable.lookupFunction<
    Void Function(IntPtr),
    void Function(int)
>("CloseNativeHandle");

final _getExitCodeNative = _executable.lookupFunction<
    Int64 Function(IntPtr),
    int Function(int)
>("GetNativeProcessExitCode");

final _waitNative = _executable.lookupFunction<
    Uint32 Function(IntPtr),
    int Function(int)
>("WaitNativeProcess");

final _terminateNative = _executable.lookupFunction<
    Void Function(IntPtr),
    void Function(int)
>("TerminateNativeProcess");

final _setPriorityNative = _executable.lookupFunction<
    Void Function(IntPtr, Uint32),
    void Function(int, int)
>("SetNativeProcessPriority");

final _setPriorityByIdNative = _executable.lookupFunction<
    Void Function(Uint32, Uint32),
    void Function(int, int)
>("SetNativeProcessPriorityById");

final _listProcessesNative = _executable.lookupFunction<
    Pointer<Utf16> Function(),
    Pointer<Utf16> Function()
>("ListProcessesNative");

final _openProcessNative = DynamicLibrary.open("kernel32.dll").lookupFunction<
    IntPtr Function(Uint32, Bool, Uint32),
    int Function(int, bool, int)
>("OpenProcess");
