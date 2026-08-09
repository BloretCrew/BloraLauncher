import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../core/i18n.dart';
import '../core/grammer_candy.dart';
import '../services/launch_service.dart';
import '../services/config_service.dart';
import '../widgets/button.dart';

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

  @override
  void initState() {
    super.initState();
    refreshLaunchItems();
  }

  void refreshLaunchItems() async {
    setState(() => _isLoading = true);
    var items = await LaunchService.instance.getAllAvailableVersions(query: _searchQuery);
    
    if (_selectedDirectoryFilter != null) {
      items = items.where((i) => i['directory'] == _selectedDirectoryFilter).toList();
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
        showSuccess("Core $id is complete.".tl);
      }
      return;
    }

    if (!mounted) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Missing Files".tl),
        content: Text("Core $id is missing some libraries or assets. Download them now?".tl),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text("Cancel".tl)),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text("Download".tl)),
        ],
      ),
    );

    if (confirm == true) {
      await LaunchService.instance.downloadMissingFiles(
        dir, id, 
        onStatus: (status, progress) {
          debugPrint("Completion Status: $status ($progress)");
        }
      );
      if (mounted) {
        showSuccess("Download task submitted for $id.".tl);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
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
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    itemCount: launchItems.length,
                    itemBuilder: (context, index) {
                      final item = launchItems[index];
                      return _buildCoreItem(theme, item['id']!, item['directory']!);
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
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey),
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

  Widget _buildCoreItem(ThemeData theme, String id, String directory) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.1)),
      ),
      child: InkWell(
        onTap: () => _checkAndComplete(directory, id),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.layers, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(id, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Text(directory, style: const TextStyle(fontSize: 11, color: Colors.grey), overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              BloretButton(
                onPressed: () => _checkAndComplete(directory, id),
                text: "Check".tl,
                height: 36,
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
                  setState(() => _selectedDirectoryFilter = isSelected ? null : dir);
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
