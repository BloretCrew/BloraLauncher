import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../core/grammer_candy.dart';
import '../core/i18n.dart';
import '../services/config_service.dart';
import '../services/external_app_service.dart';
import '../services/launch_service.dart';
import '../widgets/button.dart';
import 'external_app_selector_view.dart';

class CoresPage extends StatefulWidget {
  const CoresPage({super.key});

  @override
  State<CoresPage> createState() => _CoresPageState();
}

class _CoresPageState extends State<CoresPage> {
  List<Map<String, String>> launchItems = [];
  bool _isLoading = false;
  String _searchQuery = "";
  String? _selectedDirectoryFilter;
  final TextEditingController _searchController = TextEditingController();

  bool _isEditingExternal = false;
  CustomApp? _editingApp;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 100), () {
      refreshLaunchItems();
    });
  }

  void refreshLaunchItems() async {
    setState(() => _isLoading = true);
    var items = await LaunchService.instance.getAllAvailableVersions(
      query: _searchQuery,
    );

    if (_selectedDirectoryFilter != null) {
      items = items
          .where((i) => i['directory'] == _selectedDirectoryFilter)
          .toList();
    }

    if (mounted) {
      setState(() {
        launchItems = items;
        _isLoading = false;
      });
    }
  }

  Future<void> _checkAndComplete(String dir, String id) async {
    final isComplete = await LaunchService.instance.isVersionComplete(dir, id);
    if (isComplete) {
      if (mounted) {
        showSuccess("Core %s is complete.".tl.format(id));
      }
      return;
    }

    if (!mounted) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Missing Files".tl),
        content: Text(
          "Core $id is missing some libraries or assets. Download them now?".tl,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text("Cancel".tl),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text("Download".tl),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await LaunchService.instance.downloadMissingFiles(
        dir,
        id,
        onStatus: (status, progress) {
          debugPrint("Completion Status: $status ($progress)");
        },
      );
      if (mounted) {
        showSuccess("Download task submitted for $id.".tl);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isEditingExternal) {
      return ExternalAppEditorView(
        app: _editingApp,
        onBack: () => setState(() => _isEditingExternal = false),
        onSaved: () {
          setState(() => _isEditingExternal = false);
          refreshLaunchItems();
        },
      );
    }

    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.only(
              left: Platform.isAndroid ? 24 : 36,
              right: 24,
              top: 24,
            ),
            child: Row(
              children: [
                Text(
                  "Cores".tl,
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                BloretButton(
                  onPressed: () => setState(() {
                    _editingApp = null;
                    _isEditingExternal = true;
                  }),
                  text: "Add App".tl,
                  icon: Icons.add,
                  height: 40,
                ),
                const SizedBox(width: 12),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: refreshLaunchItems,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: TextField(
              controller: _searchController,
              onChanged: (v) {
                setState(() => _searchQuery = v);
                refreshLaunchItems();
              },
              decoration: InputDecoration(
                hintText: "Search cores...".tl,
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.3,
                ),
              ),
            ),
          ),
          _buildDirectoryFilter(theme),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : launchItems.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    itemCount: launchItems.length,
                    itemBuilder: (context, index) {
                      final item = launchItems[index];
                      return _buildCoreItem(theme, item);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            "No cores found".tl,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Check your game directories in settings.".tl,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildCoreItem(ThemeData theme, Map<String, String> item) {
    final id = item['id']!;
    final directory = item['directory']!;
    final type = item['type'] ?? "minecraft";
    final appId = item['appId'];
    final icon = item['icon'];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.1)),
      ),
      child: InkWell(
        onTap: type == "minecraft"
            ? () => _checkAndComplete(directory, id)
            : () {
                final apps = ExternalAppService.instance.getCustomApps();
                final app = apps.firstWhere((e) => e.id == appId);
                setState(() {
                  _editingApp = app;
                  _isEditingExternal = true;
                });
              },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(
                    alpha: 0.3,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: () {
                  if (type == "minecraft") {
                    final iconPath = p.join(
                      directory,
                      "versions",
                      id,
                      "icon.png",
                    );
                    final iconFile = File(iconPath);
                    if (iconFile.existsSync()) {
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(iconFile, fit: BoxFit.cover),
                      );
                    }
                    return Icon(Icons.layers, color: theme.colorScheme.primary);
                  } else {
                    if (icon != null &&
                        icon.isNotEmpty &&
                        File(icon).existsSync()) {
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(File(icon), fit: BoxFit.cover),
                      );
                    }
                    return Icon(Icons.apps, color: theme.colorScheme.primary);
                  }
                }(),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      id,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      directory,
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (type == "minecraft")
                BloretButton(
                  onPressed: () => _checkAndComplete(directory, id),
                  text: "Check".tl,
                  height: 36,
                )
              else
                IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () {
                    final apps = ExternalAppService.instance.getCustomApps();
                    final app = apps.firstWhere((e) => e.id == appId);
                    setState(() {
                      _editingApp = app;
                      _isEditingExternal = true;
                    });
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDirectoryFilter(ThemeData theme) {
    final List<dynamic> dirs = ConfigService.get('minecraft_dirs') ?? [];
    if (dirs.length <= 1) return const SizedBox.shrink();

    return Container(
      height: 40,
      margin: const EdgeInsets.only(bottom: 12),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        children: [
          FilterChip(
            label: Text("All Folders".tl),
            selected: _selectedDirectoryFilter == null,
            onSelected: (v) {
              setState(() => _selectedDirectoryFilter = null);
              refreshLaunchItems();
            },
          ),
          const SizedBox(width: 8),
          ...dirs.map((d) {
            final dir = d.toString();
            final isSelected = _selectedDirectoryFilter == dir;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(p.basename(dir)),
                tooltip: dir,
                selected: isSelected,
                onSelected: (v) {
                  setState(
                    () => _selectedDirectoryFilter = isSelected ? null : dir,
                  );
                  refreshLaunchItems();
                },
              ),
            );
          }),
        ],
      ),
    );
  }
}
