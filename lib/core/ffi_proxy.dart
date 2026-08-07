import 'dart:ffi';
import 'dart:io';

final DynamicLibrary _executable = DynamicLibrary.executable();

typedef SetProgressNative = Void Function(Uint64 completed, Uint64 total);
typedef SetProgressDart = void Function(int completed, int total);

typedef SetStateNative = Void Function(Int32 state);
typedef SetStateDart = void Function(int state);

final terminateProcess = _executable.lookupFunction<Void Function(), void Function()>("c_terminate_process");

typedef ProcessPidNative = Void Function(Uint32 pid);
typedef ProcessPidDart = void Function(int pid);

typedef EfficiencyModeNative = Void Function(Uint32 pid, Bool enable);
typedef EfficiencyModeDart = void Function(int pid, bool enable);

class WinProcess {
  static final _suspend = Platform.isWindows ? _executable.lookupFunction<ProcessPidNative, ProcessPidDart>("SuspendProcess") : null;
  static final _resume = Platform.isWindows ? _executable.lookupFunction<ProcessPidNative, ProcessPidDart>("ResumeProcess") : null;
  static final _cleanRAM = Platform.isWindows ? _executable.lookupFunction<ProcessPidNative, ProcessPidDart>("CleanProcessRAM") : null;
  static final _setEfficiency = Platform.isWindows ? _executable.lookupFunction<EfficiencyModeNative, EfficiencyModeDart>("SetEfficiencyMode") : null;

  static void suspend(int pid) => _suspend?.call(pid);
  static void resume(int pid) => _resume?.call(pid);
  static void cleanRAM(int pid) => _cleanRAM?.call(pid);
  static void setEfficiencyMode(int pid, bool enable) => _setEfficiency?.call(pid, enable);

  static final _getMem = Platform.isWindows ? _executable.lookupFunction<Uint64 Function(Uint32), int Function(int)>("GetProcessMemoryUsage") : null;
  static final _getCpu = Platform.isWindows ? _executable.lookupFunction<Uint64 Function(Uint32), int Function(int)>("GetProcessCpuTime") : null;
  static final _getCoreCount = Platform.isWindows ? _executable.lookupFunction<Int32 Function(), int Function()>("GetCpuCoreCount") : null;
  static final _isAlive = Platform.isWindows ? _executable.lookupFunction<Bool Function(Uint32), bool Function(int)>("IsProcessAlive") : null;

  static int getMemoryUsage(int pid) => _getMem?.call(pid) ?? 0;
  static int getCpuTime(int pid) => _getCpu?.call(pid) ?? 0;
  static int getCpuCoreCount() => _getCoreCount?.call() ?? 1;
  static bool isAlive(int pid) => _isAlive?.call(pid) ?? false;
}

final setClipboardImage =
_executable.lookupFunction<
    Bool Function(
        Pointer<Uint8>,
        Int32,
        Int32,
        ),
    bool Function(
        Pointer<Uint8>,
        int,
        int,
        )
>(
  "SetClipboardImage",
);

class WinTaskbar {
  static final _setProgress = (Platform.isWindows || Platform.isLinux)
      ? _executable.lookupFunction<SetProgressNative, SetProgressDart>('SetTaskbarProgress')
      : null;
  static final _setState = (Platform.isWindows || Platform.isLinux)
      ? _executable.lookupFunction<SetStateNative, SetStateDart>('SetTaskbarState')
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
