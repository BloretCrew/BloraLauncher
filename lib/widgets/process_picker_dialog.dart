import 'dart:io';

import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../services/external_app_service.dart';

class ProcessPickerDialog extends StatefulWidget {
  final Function(Map<String, dynamic>) onSelected;

  const ProcessPickerDialog({super.key, required this.onSelected});

  @override
  State<ProcessPickerDialog> createState() => _ProcessPickerDialogState();
}

class _ProcessPickerDialogState extends State<ProcessPickerDialog> {
  String _query = "";
  final Map<String, String?> _iconCache = {};
  List<Map<String, dynamic>>? _allProcesses;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProcesses();
  }

  Future<void> _loadProcesses() async {
    final list = await ExternalAppService.instance.listRunningProcesses();
    if (mounted) {
      setState(() {
        _allProcesses = list;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered =
        _allProcesses?.where((proc) {
          final name = proc['Name'].toString().toLowerCase();
          final pid = proc['ProcessId'].toString();
          return name.contains(_query.toLowerCase()) || pid.contains(_query);
        }).toList() ??
        [];

    return AlertDialog(
      title: Text("Select Process".tl),
      content: SizedBox(
        width: 500,
        height: 600,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  TextField(
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(
                      hintText: "Search by name or PID...".tl,
                      prefixIcon: const Icon(Icons.search),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final proc = filtered[index];
                        final pid = proc['ProcessId'];
                        final name = proc['Name'];
                        final exePath = proc['ExecutablePath'];
                        final ppid = proc['ParentProcessId'];

                        return ListTile(
                          leading: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: FutureBuilder<String?>(
                              future: _getIcon(exePath),
                              builder: (context, snapshot) {
                                if (snapshot.hasData && snapshot.data != null) {
                                  return Image.file(
                                    File(snapshot.data!),
                                    width: 32,
                                    height: 32,
                                    filterQuality: .low,
                                  );
                                }
                                return Icon(
                                  Icons.apps,
                                  size: 18,
                                  color: theme.colorScheme.primary.withValues(
                                    alpha: 0.5,
                                  ),
                                );
                              },
                            ),
                          ),
                          title: Text(
                            name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "PID: $pid · Parent: $ppid",
                                style: const TextStyle(fontSize: 10),
                              ),
                              if (exePath != null)
                                Text(
                                  exePath,
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: theme.colorScheme.outline,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                          onTap: () {
                            widget.onSelected(proc);
                            Navigator.pop(context);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text("Cancel".tl),
        ),
      ],
    );
  }

  Future<String?> _getIcon(String? path) async {
    if (path == null || path.isEmpty) return null;
    if (_iconCache.containsKey(path)) return _iconCache[path];

    // ExternalAppService.extractIcon internally uses runIsolate
    final icon = await ExternalAppService.instance.extractIcon(path);
    _iconCache[path] = icon;
    return icon;
  }
}
