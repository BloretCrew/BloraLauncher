import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/i18n.dart';
import '../core/logger.dart';
import '../tools/grammer_candy.dart';

class AdvancedLogViewer extends StatefulWidget {
  final bool embedded;
  final bool canPop;
  const AdvancedLogViewer({super.key, this.embedded = false, this.canPop = false});

  @override
  State<AdvancedLogViewer> createState() => _AdvancedLogViewerState();
}

class _AdvancedLogViewerState extends State<AdvancedLogViewer> {
  List<LogEntry> _logs = [];
  String _filter = "";
  LogLevel? _levelFilter;

  @override
  void initState() {
    super.initState();
    _load();
    AppLogger.notifier.addListener(_load);
  }

  @override
  void dispose() {
    AppLogger.notifier.removeListener(_load);
    super.dispose();
  }

  void _load() async {
    final logger = await AppLogger.getInstance();
    final newLogs = await logger.getLogs();
    if (mounted) setState(() => _logs = newLogs.reversed.toList());
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _logs.where((l) {
      final m = l.message.toLowerCase().contains(_filter.toLowerCase());
      final lev = _levelFilter == null || l.level == _levelFilter;
      return m && lev;
    }).toList();

    return Container(
      color: widget.embedded ? Colors.transparent : const Color(0xFF0D0D0D),
      child: Column(
        children: [
          _buildToolbar(),
          Expanded(
            child: filtered.isEmpty
                ? Center(child: Text("No Logs Found".tl, style: const TextStyle(color: Colors.white10)))
                : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: filtered.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) => _buildLogCard(filtered[i]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(color: Colors.white.withOpacityEx(0.02), border: const Border(bottom: BorderSide(color: Colors.white10))),
      child: Row(
        children: [
          if (widget.canPop) IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white38, size: 20), onPressed: () => Navigator.pop(context)),
          Expanded(
            child: TextField(
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(hintText: "Search logs...".tl, hintStyle: const TextStyle(color: Colors.white24), border: InputBorder.none, icon: const Icon(Icons.search, size: 18, color: Colors.white24)),
              onChanged: (v) => setState(() => _filter = v),
            ),
          ),
          _buildLevelDot(LogLevel.error, Colors.redAccent),
          _buildLevelDot(LogLevel.warning, Colors.orangeAccent),
          _buildLevelDot(LogLevel.info, Colors.blueAccent),
          IconButton(icon: const Icon(Icons.delete_sweep_outlined, color: Colors.white38, size: 20), onPressed: () => AppLogger.getInstance().then((l) => l.clearLogs())),
        ],
      ),
    );
  }

  Widget _buildLevelDot(LogLevel level, Color color) {
    bool active = _levelFilter == level;
    return GestureDetector(
      onTap: () => setState(() => _levelFilter = active ? null : level),
      child: Container(
        margin: const EdgeInsets.only(left: 8),
        width: 12, height: 12,
        decoration: BoxDecoration(color: active ? color : color.withOpacityEx(0.2), shape: BoxShape.circle, border: active ? Border.all(color: Colors.white, width: 1.5) : null),
      ),
    );
  }

  Widget _buildLogCard(LogEntry log) {
    final color = _getLevelColor(log.level);
    final isMobile = MediaQuery.of(context).size.width < 600;

    return InkWell(
      onTap: () => _showDetail(log),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacityEx(0.03),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacityEx(0.1)),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Larger Icon Section
              Container(
                width: isMobile ? 48 : 56,
                decoration: BoxDecoration(
                  color: color.withOpacityEx(0.05),
                  borderRadius: const BorderRadius.only(topLeft: Radius.circular(8), bottomLeft: Radius.circular(8)),
                ),
                child: Center(
                  child: Icon(
                    AppLogger.iconMap[log.iconId] ?? Icons.info_outline,
                    size: isMobile ? 24 : 28,
                    color: color,
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: color.withOpacityEx(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              log.level.name.toUpperCase(),
                              style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              log.source.name.toUpperCase(),
                              style: TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            log.timestamp.toString().substring(11, 19),
                            style: const TextStyle(color: Colors.white12, fontSize: 8, fontFamily: 'monospace'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        log.message,
                        style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.3),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (log.detail.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          log.detail.split('\n').first,
                          style: TextStyle(color: color.withOpacityEx(0.4), fontSize: 10, fontFamily: 'monospace'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDetail(LogEntry log) {
    final color = _getLevelColor(log.level);
    HoshivetwDialog.show(
      context: context,
      title: log.level.name.toUpperCase(),
      icon: Icon(AppLogger.iconMap[log.iconId] ?? Icons.info_outline, color: color, size: 24),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(log.message, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              _detailRow("Time".tl, log.timestamp.toString()),
              _detailRow("Source".tl, log.source.name),
              const Divider(color: Colors.white10, height: 32),
              if (log.detail.isNotEmpty) ...[
                Text("STACK TRACE / DETAILS".tl, style: const TextStyle(color: Colors.blueAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.white10)),
                  child: SelectableText(log.detail, style: const TextStyle(color: Colors.greenAccent, fontSize: 11, fontFamily: 'monospace')),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () {
          Clipboard.setData(ClipboardData(text: "Message: ${log.message}\nDetail: ${log.detail}"));
          Navigator.pop(context);
        }, child: Text("Copy".tl)),
        TextButton(onPressed: () => Navigator.pop(context), child: Text("Close".tl)),
      ],
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 80, child: Text(label, style: const TextStyle(color: Colors.white24, fontSize: 12))),
          Expanded(
            child: Text(value, style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.2)),
          ),
        ],
      ),
    );
  }

  Color _getLevelColor(LogLevel level) {
    switch (level) {
      case LogLevel.error: return Colors.redAccent;
      case LogLevel.warning: return Colors.orangeAccent;
      case LogLevel.info: return Colors.blueAccent;
      case LogLevel.debug: return Colors.grey;
    }
  }
}

class HoshivetwDialog extends StatelessWidget {
  final String title;
  final Widget? icon;
  final Widget content;
  final List<Widget>? actions;
  final Color? accentColor;
  final bool showDivider;

  const HoshivetwDialog({
    super.key,
    required this.title,
    this.icon,
    required this.content,
    this.actions,
    this.accentColor,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    final color = accentColor ?? Theme.of(context).colorScheme.primary;

    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      titlePadding: EdgeInsets.zero,
      title: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: color.withOpacityEx(0.05),
          borderRadius: const BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12)),
          border: showDivider ? Border(bottom: BorderSide(color: color.withOpacityEx(0.15))) : null,
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              icon!,
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Text(
                title.tl,
                style: TextStyle(
                  color: color,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
      content: content,
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      actions: actions,
    );
  }

  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    Widget? icon,
    required Widget content,
    List<Widget>? actions,
    Color? accentColor,
  }) {
    return showDialog<T>(
      context: context,
      builder: (context) => HoshivetwDialog(
        title: title,
        icon: icon,
        content: content,
        actions: actions,
        accentColor: accentColor,
      ),
    );
  }
}

class HoshivetwDialogButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isPrimary;
  final bool isDanger;
  final Color? accentColor;

  const HoshivetwDialogButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isPrimary = false,
    this.isDanger = false,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDanger ? Colors.redAccent : accentColor ?? (isPrimary ? Theme.of(context).colorScheme.primary : Colors.white38);

    return TextButton(
      style: TextButton.styleFrom(
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      onPressed: onPressed,
      child: Text(
        text.tl,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1,
        ),
      ),
    );
  }
}