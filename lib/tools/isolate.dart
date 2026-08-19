import 'dart:async';
import 'dart:isolate';

Future<T> runIsolate<T, P>(
  FutureOr<T> Function(P param) task,
  P param, {
  String? debugName,
}) async {
  return Isolate.run<T>(
    () async => await task(param),
    debugName: debugName,
  );
}