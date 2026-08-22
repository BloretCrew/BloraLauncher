import 'dart:io';

import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../services/launch_service.dart';
import '../services/stats_service.dart';
import '../widgets/core_icon.dart';

class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  Map<String, dynamic> overview = {};
  List<Map<String, dynamic>> versionStats = [];
  List<dynamic> sessionList = [];
  List<String> dateList = [];
  List<String> allVersions = [];
  Map<String, Map<String, String>> versionMap = {};

  int currentPage = 1;
  int totalPages = 1;
  int totalSessions = 0;

  String selectedDateFilter = "";
  String selectedVersionFilter = "";

  @override
  void initState() {
    super.initState();
    refreshAll();
  }

  Future<void> refreshAll() async {
    await Future.delayed(const Duration(milliseconds: 400));
    final ov = await StatsService.instance.getOverview();
    final vs = await StatsService.instance.getVersionStats();
    final dl = await StatsService.instance.getAllDates();
    final av = await StatsService.instance.getAllVersions();
    final allAvailable = await LaunchService.instance.getAllAvailableVersions();
    final vMap = {for (var v in allAvailable) v['id']!: v};

    if (mounted) {
      setState(() {
        overview = ov;
        versionStats = vs;
        dateList = dl;
        allVersions = av;
        versionMap = vMap;
        currentPage = 1;
      });
      loadSessions();
    }
  }

  Future<void> loadSessions() async {
    final result = await StatsService.instance.getSessionsPaginated(
      dateFilter: selectedDateFilter,
      versionFilter: selectedVersionFilter,
      page: currentPage,
      pageSize: 15,
    );

    if (mounted) {
      setState(() {
        sessionList = result["sessions"] ?? [];
        totalPages = result["total_pages"] ?? 1;
        totalSessions = result["total"] ?? 0;
      });
    }
  }

  String formatTime(dynamic seconds) {
    return StatsService.instance.formatPlayTime(seconds ?? 0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: ListView(
        padding: EdgeInsets.only(
          left: Platform.isAndroid ? 16 : 32,
          right: 16,
          top: 16,
          bottom: 16,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              "Statistics".tl,
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            "Overview".tl,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              StatCard(
                title: "Total Play Time".tl,
                value: formatTime(overview["total"]),
                subtitle:
                "${"Foreground".tl} ${formatTime(overview["total_foreground"])} / ${"Background".tl} ${formatTime(overview["total_background"])}",
                icon: Icons.timer,
              ),
              StatCard(
                title: "Today".tl,
                value: formatTime(
                  overview["today"]?["total"],
                ),
                subtitle:
                "${overview["today"]?["sessions"] ?? 0} ${"sessions".tl}",
                icon: Icons.calendar_today_outlined,
              ),
              StatCard(
                title: "This Week".tl,
                value: formatTime(
                  overview["this_week"]?["total"],
                ),
                subtitle:
                "${overview["this_week"]?["sessions"] ?? 0} ${"sessions".tl}",
                icon: Icons.calendar_today,
              ),
              StatCard(
                title: "This Month".tl,
                value: formatTime(
                  overview["this_month"]?["total"],
                ),
                subtitle:
                "${overview["this_month"]?["sessions"] ?? 0} ${"sessions".tl}",
                icon: Icons.calendar_month,
              ),
            ],
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              StatCard(
                title: "Days Played".tl,
                value: "${overview["unique_days"] ?? 0} ${"days".tl}",
                icon: Icons.timelapse,
              ),
              StatCard(
                title: "Daily Average".tl,
                value: formatTime(overview["avg_per_day"]),
                icon: Icons.schedule,
              ),
              StatCard(
                title: "Longest Day".tl,
                value: formatTime(
                  overview["longest_day_time"],
                ),
                subtitle: overview["longest_day"],
                icon: Icons.calendar_today,
              ),
              StatCard(
                title: "Total Sessions".tl,
                value: "${overview["total_sessions"] ?? 0} ${"times".tl}",
                icon: Icons.chat_bubble_outline,
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            "Version Stats".tl,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          VersionStatsList(
            data: versionStats,
            formatTime: formatTime,
            versionMap: versionMap,
          ),
          const SizedBox(height: 24),
          Text(
            "Session Logs".tl,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          _buildFilters(theme),
          const SizedBox(height: 12),
          SessionList(
            sessions: sessionList,
            formatTime: formatTime,
            versionMap: versionMap,
          ),
          const SizedBox(height: 12),
          _buildPagination(theme),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildFilters(ThemeData theme) {
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue: selectedDateFilter.isEmpty ? null : selectedDateFilter,
            decoration: InputDecoration(
              labelText: "Date".tl,
              isDense: true,
              border: const OutlineInputBorder(),
            ),
            items: [
              DropdownMenuItem(value: "", child: Text("All Dates".tl)),
              ...dateList.map((d) => DropdownMenuItem(value: d, child: Text(d))),
            ],
            onChanged: (v) {
              setState(() {
                selectedDateFilter = v ?? "";
                currentPage = 1;
              });
              loadSessions();
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue: selectedVersionFilter.isEmpty ? null : selectedVersionFilter,
            decoration: InputDecoration(
              labelText: "Version".tl,
              isDense: true,
              border: const OutlineInputBorder(),
            ),
            items: [
              DropdownMenuItem(value: "", child: Text("All Versions".tl)),
              ...allVersions.map((v) => DropdownMenuItem(value: v, child: Text(v))),
            ],
            onChanged: (v) {
              setState(() {
                selectedVersionFilter = v ?? "";
                currentPage = 1;
              });
              loadSessions();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPagination(ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: currentPage > 1 ? () {
            setState(() => currentPage--);
            loadSessions();
          } : null,
        ),
        Text("${"Page".tl} $currentPage / $totalPages"),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: currentPage < totalPages ? () {
            setState(() => currentPage++);
            loadSessions();
          } : null,
        ),
      ],
    );
  }
}

class StatCard extends StatelessWidget {
  final String title;
  final String value;
  final String? subtitle;
  final IconData icon;

  const StatCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isPortrait = MediaQuery.of(context).size.height > screenWidth;

    double width = isPortrait ? (screenWidth - 48) : 240.0;
    if (width > 600) width = 600;

    return SizedBox(
      width: width,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (subtitle != null && subtitle!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).brightness == Brightness.dark 
                          ? Colors.grey[400] 
                          : Colors.grey[600],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class VersionStatsList extends StatelessWidget {
  final List<dynamic> data;
  final String Function(dynamic) formatTime;
  final Map<String, Map<String, String>> versionMap;

  const VersionStatsList({
    super.key,
    required this.data,
    required this.formatTime,
    required this.versionMap,
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Center(
            child: Text("No data available".tl),
          ),
        ),
      );
    }

    return Column(
      children: data.map((item) {
        final vId = item["version"]?.toString() ?? "";
        final vData = versionMap[vId] ?? {'id': vId};

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  CoreIcon(item: vData, size: 40),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                      CrossAxisAlignment.start,
                      children: [
                        Text(
                          item["version"] ?? "",
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          "${item["sessions"] ?? 0} ${"sessions".tl}",
                          style: const TextStyle(
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment:
                    CrossAxisAlignment.end,
                    children: [
                      Text(
                        formatTime(item["total"]),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        "${"Fore".tl} ${formatTime(item["foreground"])} / ${"Back".tl} ${formatTime(item["background"])}",
                        style: const TextStyle(
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class SessionList extends StatelessWidget {
  final List<dynamic> sessions;
  final String Function(dynamic) formatTime;
  final Map<String, Map<String, String>> versionMap;

  const SessionList({
    super.key,
    required this.sessions,
    required this.formatTime,
    required this.versionMap,
  });

  @override
  Widget build(BuildContext context) {
    if (sessions.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Center(
            child: Text("No session logs".tl),
          ),
        ),
      );
    }

    return Column(
      children: sessions.map((item) {
        final vId = item["version"]?.toString() ?? "";
        final vData = versionMap[vId] ?? {'id': vId};

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                CoreIcon(item: vData, size: 36),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                    CrossAxisAlignment.start,
                    children: [
                      Text(
                        item["version"] ?? "",
                        style: const TextStyle(
                          fontWeight:
                          FontWeight.bold,
                        ),
                      ),
                      Text(
                        "${item["date"] ?? ""}  ${item["start_time"] ?? ""} - ${item["end_time"] ?? ""}",
                        style:
                        const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatTime(item["total"]),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      "${"Fore".tl} ${formatTime(item["foreground"])} / ${"Back".tl} ${formatTime(item["background"])}",
                      style:
                      const TextStyle(fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
