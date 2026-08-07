import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class LogNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}

class AppLogger {
  static AppLogger? _instance;
  late File _logFile;

  static final _logController = LogNotifier();
  static LogNotifier get notifier => _logController;

  static final Map<int, IconData> iconMap = {
    0: Icons.info_outline,
    1: Icons.warning_amber_rounded,
    2: Icons.error_outline_rounded,
    3: Icons.lan_outlined,
    4: Icons.terminal_rounded,
    5: Icons.sync_rounded,
    6: Icons.storage_rounded,
    7: Icons.cloud_queue_rounded,
    8: Icons.layers_outlined,
  };

  static int _getDefaultIconId(LogSource source) {
    switch (source) {
      case LogSource.system: return 0;
      case LogSource.network: return 3;
      case LogSource.ui: return 8;
      case LogSource.db: return 6;
      case LogSource.cache: return 5;
      case LogSource.tool: return 4;
      case LogSource.download: return 7;
      case LogSource.fileSystem: return 6;
    }
  }

  AppLogger._internal();

  static Future<AppLogger> getInstance() async {
    if (_instance == null) {
      _instance = AppLogger._internal();
      await _instance!._init();
    }
    return _instance!;
  }

  Future<void> _init() async {
    if (kIsWeb) return;
    Directory dir;
    if (Platform.isAndroid || Platform.isIOS) {
      dir = await getApplicationSupportDirectory();
    } else {
      dir = Directory(getExeDirectory());
    }
    _logFile = File('${dir.path}/app_log.json');
    if (!await _logFile.exists()) {
      await _logFile.create(recursive: true);
      await _logFile.writeAsString(jsonEncode([]));
    }
  }

  String getExeDirectory() {
    final path = Platform.resolvedExecutable;
    return p.dirname(path);
  }

  Future<void> info(String message, [LogSource source = LogSource.system]) async {
    await log(message, source: source);
  }

  Future<void> warning(String message, [LogSource source = LogSource.system]) async {
    await log(message, source: source, level: .warning);
  }

  Future<void> error(String message, [LogSource source = LogSource.system]) async {
    await log(message, source: source, level: .error);
  }

  Future<void> debug(String message, [LogSource source = LogSource.system]) async {
    await log(message, source: source, level: .debug);
  }

  Future<void> log(
      String message, {
        LogLevel level = LogLevel.info,
        int? iconId,
        LogSource source = LogSource.system,
        String detail = "",
      }) async {
    if (kIsWeb) return;

    final effectiveIconId = iconId ?? _getDefaultIconId(source);

    final entry = LogEntry(
      timestamp: DateTime.now(),
      message: message,
      level: level,
      iconId: effectiveIconId,
      source: source,
      detail: detail,
    );

    try {
      final logs = await getLogs();
      logs.add(entry);
      const maxLogs = 1000;
      if (logs.length > maxLogs) logs.removeRange(0, logs.length - maxLogs);

      final jsonList = logs.map((e) => e.toJson()).toList();
      await _logFile.writeAsString(jsonEncode(jsonList));

      if (kDebugMode) print(entry);
      _logController.notify();
    } catch (e) {
      debugPrint("Logging failed: $e");
    }
  }

  Future<List<LogEntry>> getLogs() async {
    try {
      if (!await _logFile.exists()) return [];
      final content = await _logFile.readAsString();
      final List<dynamic> jsonList = jsonDecode(content);
      return jsonList.map((e) => LogEntry.fromJson(e)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> clearLogs() async {
    await _logFile.writeAsString(jsonEncode([]));
    _logController.notify();
  }
}

enum LogLevel { error, warning, info, debug }
enum LogSource { system, network, ui, db, cache, tool, download, fileSystem }

String logSourceToString(LogSource source) => source.name;

class LogEntry {
  final DateTime timestamp;
  final String message;
  final LogLevel level;
  final int iconId;
  final LogSource source;
  final String detail;

  LogEntry({required this.timestamp, required this.message, required this.level, required this.iconId, required this.source, required this.detail});

  Map<String, dynamic> toJson() => {
    "timestamp": timestamp.toIso8601String(),
    "message": message,
    "level": level.name,
    "iconId": iconId,
    "source": source.name,
    "detail": detail,
  };

  static LogEntry fromJson(Map<String, dynamic> json) => LogEntry(
    timestamp: DateTime.parse(json["timestamp"]),
    message: json["message"] ?? "",
    level: LogLevel.values.firstWhere((e) => e.name == json["level"], orElse: () => LogLevel.info),
    iconId: json["iconId"] ?? 0,
    source: LogSource.values.firstWhere((e) => e.name == json["source"], orElse: () => LogSource.system),
    detail: json["detail"] ?? "",
  );

  @override
  String toString() {
    return toJson().toString();
  }
}