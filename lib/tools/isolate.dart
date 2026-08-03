import 'dart:isolate';

Future<T> runIsolate<T, P>(
    Future<T> Function(P param) task,
    P param,
    ) async {
  final receivePort = ReceivePort();

  await Isolate.spawn<_IsolateMessage<P>>(
    _isolateEntry,
    _IsolateMessage(
      sendPort: receivePort.sendPort,
      task: task,
      param: param,
    ),
  );

  final result = await receivePort.first as T;

  receivePort.close();

  return result;
}

class _IsolateMessage<P> {
  final SendPort sendPort;
  final Future<dynamic> Function(P) task;
  final P param;

  _IsolateMessage({
    required this.sendPort,
    required this.task,
    required this.param,
  });
}

Future<void> _isolateEntry<P>(
    _IsolateMessage<P> msg,
    ) async {
  final result = await msg.task(msg.param);

  msg.sendPort.send(result);
}