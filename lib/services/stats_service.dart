import 'dart:convert';
import 'dart:io';
import 'package:intl/intl.dart';
import 'config_service.dart';

class SessionRecord {
  final String version;
  final DateTime startTime;
  final DateTime endTime;
  final int total;
  final int foreground;
  final int background;

  SessionRecord({
    required this.version,
    required this.startTime,
    required this.endTime,
    required this.total,
    this.foreground = 0,
    this.background = 0,
  });

  Map<String, dynamic> toJson() => {
    'version': version,
    'start_time': startTime.toIso8601String(),
    'end_time': endTime.toIso8601String(),
    'total': total,
    'foreground': foreground,
    'background': background,
  };

  factory SessionRecord.fromJson(Map<String, dynamic> json) => SessionRecord(
    version: json['version'] ?? 'Unknown',
    startTime: DateTime.parse(json['start_time']),
    endTime: DateTime.parse(json['end_time']),
    total: json['total'] ?? 0,
    foreground: json['foreground'] ?? 0,
    background: json['background'] ?? 0,
  );
}

class StatsService {
  static final StatsService instance = StatsService._();
  StatsService._();

  List<SessionRecord> _sessions = [];
  bool _loaded = false;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final dir = await getSupportData();
    final file = File("${dir.path}/stats.json");
    if (await file.exists()) {
      try {
        final List<dynamic> list = jsonDecode(await file.readAsString());
        _sessions = list.map((e) => SessionRecord.fromJson(e)).toList();
      } catch (_) {
        _sessions = [];
      }
    }
    _loaded = true;
  }

  Future<void> addSession(SessionRecord session) async {
    await _ensureLoaded();
    _sessions.add(session);
    final dir = await getSupportData();
    final file = File("${dir.path}/stats.json");
    await file.writeAsString(jsonEncode(_sessions.map((e) => e.toJson()).toList()));
  }

  Future<Map<String, dynamic>> getOverview() async {
    await _ensureLoaded();
    int total = 0;
    int totalFore = 0;
    int totalBack = 0;
    
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekStart = today.subtract(Duration(days: now.weekday - 1));
    final monthStart = DateTime(now.year, now.month, 1);

    Map<String, dynamic> todayStats = {'total': 0, 'sessions': 0};
    Map<String, dynamic> weekStats = {'total': 0, 'sessions': 0};
    Map<String, dynamic> monthStats = {'total': 0, 'sessions': 0};
    
    Set<String> uniqueDays = {};
    Map<String, int> dailyTime = {};

    for (var s in _sessions) {
      total += s.total;
      totalFore += s.foreground;
      totalBack += s.background;

      final sDate = DateTime(s.startTime.year, s.startTime.month, s.startTime.day);
      final dateKey = DateFormat('yyyy-MM-dd').format(sDate);
      uniqueDays.add(dateKey);
      dailyTime[dateKey] = (dailyTime[dateKey] ?? 0) + s.total;

      if (sDate.isAtSameMomentAs(today)) {
        todayStats['total'] += s.total;
        todayStats['sessions']++;
      }
      if (sDate.isAfter(weekStart) || sDate.isAtSameMomentAs(weekStart)) {
        weekStats['total'] += s.total;
        weekStats['sessions']++;
      }
      if (sDate.isAfter(monthStart) || sDate.isAtSameMomentAs(monthStart)) {
        monthStats['total'] += s.total;
        monthStats['sessions']++;
      }
    }

    String longestDay = "None";
    int longestDayTime = 0;
    dailyTime.forEach((k, v) {
      if (v > longestDayTime) {
        longestDayTime = v;
        longestDay = k;
      }
    });

    return {
      "total": total,
      "total_foreground": totalFore,
      "total_background": totalBack,
      "today": todayStats,
      "this_week": weekStats,
      "this_month": monthStats,
      "unique_days": uniqueDays.length,
      "avg_per_day": uniqueDays.isEmpty ? 0 : total ~/ uniqueDays.length,
      "longest_day_time": longestDayTime,
      "longest_day": longestDay,
      "total_sessions": _sessions.length,
    };
  }

  Future<List<Map<String, dynamic>>> getVersionStats() async {
    await _ensureLoaded();
    Map<String, Map<String, dynamic>> stats = {};

    for (var s in _sessions) {
      final v = s.version;
      if (!stats.containsKey(v)) {
        stats[v] = {
          "version": v,
          "sessions": 0,
          "total": 0,
          "foreground": 0,
          "background": 0,
        };
      }
      stats[v]!["sessions"]++;
      stats[v]!["total"] += s.total;
      stats[v]!["foreground"] += s.foreground;
      stats[v]!["background"] += s.background;
    }

    final list = stats.values.toList();
    list.sort((a, b) => b["total"].compareTo(a["total"]));
    return list;
  }

  Future<Map<String, dynamic>> getSessionsPaginated({
    String dateFilter = "",
    String versionFilter = "",
    int page = 1,
    int pageSize = 15,
  }) async {
    await _ensureLoaded();
    var filtered = _sessions.where((s) {
      if (dateFilter.isNotEmpty && DateFormat('yyyy-MM-dd').format(s.startTime) != dateFilter) {
        return false;
      }
      if (versionFilter.isNotEmpty && s.version != versionFilter) {
        return false;
      }
      return true;
    }).toList();

    filtered.sort((a, b) => b.startTime.compareTo(a.startTime));

    final total = filtered.length;
    final totalPages = (total / pageSize).ceil();
    final start = (page - 1) * pageSize;
    final end = start + pageSize;
    
    final paged = filtered.sublist(
      start.clamp(0, total),
      end.clamp(0, total),
    );

    return {
      "sessions": paged.map((s) => {
        "version": s.version,
        "date": DateFormat('yyyy-MM-dd').format(s.startTime),
        "start_time": DateFormat('HH:mm').format(s.startTime),
        "end_time": DateFormat('HH:mm').format(s.endTime),
        "total": s.total,
        "foreground": s.foreground,
        "background": s.background,
      }).toList(),
      "total_pages": totalPages == 0 ? 1 : totalPages,
      "total": total,
    };
  }

  Future<List<String>> getAllVersions() async {
    await _ensureLoaded();
    return _sessions.map((e) => e.version).toSet().toList();
  }

  Future<List<String>> getAllDates() async {
    await _ensureLoaded();
    return _sessions.map((e) => DateFormat('yyyy-MM-dd').format(e.startTime)).toSet().toList();
  }

  String formatPlayTime(int seconds) {
    if (seconds < 60) return "${seconds}s";
    if (seconds < 3600) return "${seconds ~/ 60}m ${seconds % 60}s";
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    return "${h}h ${m}m";
  }
}
