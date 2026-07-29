import 'dart:ffi';
import 'dart:io';

final DynamicLibrary _executable = DynamicLibrary.executable();

typedef _SetProgress_Native = Void Function(Uint64 completed, Uint64 total);
typedef _SetProgress_Dart = void Function(int completed, int total);

typedef _SetState_Native = Void Function(Int32 state);
typedef _SetState_Dart = void Function(int state);

class WinTaskbar {
  static final _setProgress = Platform.isWindows 
      ? _executable.lookupFunction<_SetProgress_Native, _SetProgress_Dart>('SetTaskbarProgress') 
      : null;
  static final _setState = Platform.isWindows 
      ? _executable.lookupFunction<_SetState_Native, _SetState_Dart>('SetTaskbarState') 
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
