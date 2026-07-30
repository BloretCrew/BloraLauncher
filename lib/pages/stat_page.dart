import 'package:flutter/material.dart';

class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  Map<String, dynamic> overview = {};
  List<dynamic> versionStats = [];
  List<dynamic> sessionList = [];
  List<dynamic> dateList = [];
  List<dynamic> allVersions = [];

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

  void refreshAll() {
    // if (Backend == null) return;
    //
    // setState(() {
    //   overview = Backend.getPlayStatisticsOverview();
    //   versionStats = Backend.getPlayStatisticsVersions();
    //   dateList = Backend.getPlayStatisticsDates();
    //   allVersions = Backend.getPlayStatisticsAllVersions();
    //   currentPage = 1;
    // });

    loadSessions();
  }

  void loadSessions() {
    // if (Backend == null) return;
    //
    // final result = Backend.getPlayStatisticsPaginated(
    //   selectedDateFilter,
    //   selectedVersionFilter,
    //   currentPage,
    //   15,
    // );

    // setState(() {
    //   sessionList = result["sessions"] ?? [];
    //   totalPages = result["total_pages"] ?? 1;
    //   totalSessions = result["total"] ?? 0;
    // });
  }

  String formatTime(dynamic seconds) {
    // if (Backend == null) return "0s";
    // return Backend.formatPlayTime(seconds ?? 0);
    return "0s";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.only(
          left: 32,
          right: 16,
          top: 16,
          bottom: 16,
        ),
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 8, top: 8),
            child: Text(
              "统计信息",
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            "总览",
            style: TextStyle(
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
                title: "总游戏时间",
                value: formatTime(overview["total"]),
                subtitle:
                "前台 ${formatTime(overview["total_foreground"])} / 后台 ${formatTime(overview["total_background"])}",
                icon: Icons.timer,
              ),
              StatCard(
                title: "今日游玩",
                value: formatTime(
                  overview["today"]?["total"],
                ),
                subtitle:
                "${overview["today"]?["sessions"] ?? 0} 次会话",
                icon: Icons.calendar_today_outlined,
              ),
              StatCard(
                title: "本周游玩",
                value: formatTime(
                  overview["this_week"]?["total"],
                ),
                subtitle:
                "${overview["this_week"]?["sessions"] ?? 0} 次会话",
                icon: Icons.calendar_today,
              ),
              StatCard(
                title: "本月游玩",
                value: formatTime(
                  overview["this_month"]?["total"],
                ),
                subtitle:
                "${overview["this_month"]?["sessions"] ?? 0} 次会话",
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
                title: "游戏天数",
                value: "${overview["unique_days"] ?? 0} 天",
                icon: Icons.timelapse,
              ),
              StatCard(
                title: "日均游玩",
                value: formatTime(overview["avg_per_day"]),
                icon: Icons.schedule,
              ),
              StatCard(
                title: "最长单日",
                value: formatTime(
                  overview["longest_day_time"],
                ),
                subtitle: overview["longest_day"],
                icon: Icons.calendar_today,
              ),
              StatCard(
                title: "总会话数",
                value: "${overview["total_sessions"] ?? 0} 次",
                icon: Icons.chat_bubble_outline,
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text(
            "版本统计",
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          VersionStatsList(
            data: versionStats,
            formatTime: formatTime,
          ),
          const SizedBox(height: 24),
          const Text(
            "会话记录",
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
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
    return SizedBox(
      width: 240,
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
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
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
                      color: Colors.grey[100],
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

  const VersionStatsList({
    super.key,
    required this.data,
    required this.formatTime,
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(30),
          child: Center(
            child: Text("暂无数据"),
          ),
        ),
      );
    }

    return Column(
      children: data.map((item) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.blue.withValues(alpha: 0.15),
                    ),
                    child: Text(
                      (item["version"] ?? "?")
                          .toString()
                          .substring(0, 1)
                          .toUpperCase(),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
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
                          "${item["sessions"] ?? 0} 次会话",
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
                        "前 ${formatTime(item["foreground"])} / 后 ${formatTime(item["background"])}",
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

  const SessionList({
    super.key,
    required this.sessions,
    required this.formatTime,
  });

  @override
  Widget build(BuildContext context) {
    if (sessions.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(30),
          child: Center(
            child: Text("暂无会话记录"),
          ),
        ),
      );
    }

    return Column(
      children: sessions.map((item) {
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius:
                    BorderRadius.circular(8),
                    color:
                    Colors.blue.withValues(alpha: 0.12),
                  ),
                  child: Text(
                    (item["version"] ?? "?")
                        .toString()
                        .substring(0, 1)
                        .toUpperCase(),
                  ),
                ),
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
                      "前 ${formatTime(item["foreground"])} / 后 ${formatTime(item["background"])}",
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