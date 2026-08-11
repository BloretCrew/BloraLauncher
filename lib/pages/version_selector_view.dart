import 'dart:io';
import 'package:flutter/material.dart';
import '../core/i18n.dart';
import '../core/grammer_candy.dart';
import '../services/download_service.dart';
import '../services/launch_service.dart';
import '../widgets/windows_widgets.dart';

class VersionSelectorView extends StatefulWidget {
  final LoaderType type;
  final VoidCallback onBack;

  const VersionSelectorView({
    super.key,
    required this.type,
    required this.onBack,
  });

  @override
  State<VersionSelectorView> createState() => _VersionSelectorViewState();
}

class _VersionSelectorViewState extends State<VersionSelectorView> {
  List<MinecraftVersion> allVanillaVersions = [];
  List<String> loaders = [];
  bool isLoading = true;

  String? selectedMajorVersion;
  String currentType = "release";
  String? selectedMcVersion;
  List<String> mcVersionsForLoader = [];
  List<String> loaderVersions = [];

  final Map<String, IconData> typeIcons = {
    "release": Icons.verified,
    "snapshot": Icons.bug_report,
    "old_beta": Icons.history,
    "old_alpha": Icons.hourglass_empty,
  };

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => isLoading = true);
    if (widget.type == LoaderType.vanilla) {
      allVanillaVersions = await DownloadService.instance.fetchAllVanillaVersions();
      if (allVanillaVersions.isNotEmpty) {
        // Auto-select latest major version
        final releases = allVanillaVersions.where((v) => v.type == "release").toList();
        if (releases.isNotEmpty) {
          final latest = releases.first.id;
          final parts = latest.split('.');
          if (parts.length >= 2) {
            selectedMajorVersion = "${parts[0]}.${parts[1]}";
          }
        }
      }
    } else {
      // For loaders, we need vanilla versions to select the MC version first
      allVanillaVersions = await DownloadService.instance.fetchAllVanillaVersions();
      mcVersionsForLoader = allVanillaVersions
          .where((v) => v.type == "release")
          .map((v) => v.id)
          .toList();
      if (mcVersionsForLoader.isNotEmpty) {
        selectedMcVersion = mcVersionsForLoader.first;
        await _loadLoaderVersions();
      }
    }
    if (mounted) setState(() => isLoading = false);
  }

  Future<void> _loadLoaderVersions() async {
    if (selectedMcVersion == null) return;
    setState(() => isLoading = true);
    loaderVersions = await DownloadService.instance.fetchLoaderVersions(selectedMcVersion!, widget.type);
    setState(() => isLoading = false);
  }

  List<String> get majorVersions {
    final Set<String> majors = {};
    for (var v in allVanillaVersions) {
      if (v.type == "release") {
        final parts = v.id.split('.');
        if (parts.length >= 2) {
          majors.add("${parts[0]}.${parts[1]}");
        }
      }
    }
    final list = majors.toList()..sort((a, b) {
      final pa = a.split('.').map(int.parse).toList();
      final pb = b.split('.').map(int.parse).toList();
      for (int i = 0; i < pa.length && i < pb.length; i++) {
        if (pa[i] != pb[i]) return pb[i].compareTo(pa[i]);
      }
      return pb.length.compareTo(pa.length);
    });
    return list;
  }

  List<MinecraftVersion> get filteredVersions {
    var list = allVanillaVersions.where((v) => v.type == currentType).toList();
    if (selectedMajorVersion != null && currentType == "release") {
      list = list.where((v) => v.id.startsWith(selectedMajorVersion!)).toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        _buildHeader(theme),
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _buildVersionGrid(theme),
              ),
              _buildRightSidebar(theme),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: widget.onBack,
          ),
          const SizedBox(width: 8),
          Text(
            "${widget.type.name.toUpperCase()} ${"Installation".tl}",
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          if (widget.type == LoaderType.vanilla && currentType == "release")
            Win11Dropdown(
              width: 150,
              items: majorVersions.map((v) => Win11DropdownItem(label: v, value: v)).toList(),
              initialValue: selectedMajorVersion,
              onChanged: (v) => setState(() => selectedMajorVersion = v),
            ),
          if (widget.type != LoaderType.vanilla)
            Win11Dropdown(
              width: 150,
              items: mcVersionsForLoader.map((v) => Win11DropdownItem(label: v, value: v)).toList(),
              initialValue: selectedMcVersion,
              onChanged: (v) {
                setState(() => selectedMcVersion = v);
                _loadLoaderVersions();
              },
            ),
        ],
      ),
    );
  }

  Widget _buildVersionGrid(ThemeData theme) {
    if (widget.type == LoaderType.vanilla) {
      final versions = filteredVersions;
      if (versions.isEmpty) {
        return Center(child: Text("No versions found for this category".tl));
      }

      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: versions.map((v) => _buildVersionItem(theme, v.id, v.type)).toList(),
        ),
      );
    } else {
      if (loaderVersions.isEmpty) {
        return Center(child: Text("No loaders available for this Minecraft version".tl));
      }
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: loaderVersions.map((v) => _buildLoaderItem(theme, v)).toList(),
        ),
      );
    }
  }

  Widget _buildVersionItem(ThemeData theme, String id, String type) {
    return InkWell(
      onTap: () => _confirmInstallVanilla(id),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 120,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.dividerColor.withValues(alpha: 0.1)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(typeIcons[type] ?? Icons.layers, size: 24, color: theme.colorScheme.primary),
            const SizedBox(height: 8),
            Text(
              id,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoaderItem(ThemeData theme, String version) {
    return InkWell(
      onTap: () => _confirmInstallLoader(version),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 140,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.dividerColor.withValues(alpha: 0.1)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.settings_suggest, size: 24, color: theme.colorScheme.secondary),
            const SizedBox(height: 8),
            Text(
              version,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRightSidebar(ThemeData theme) {
    if (widget.type != LoaderType.vanilla) return const SizedBox.shrink();
    
    final categories = [
      {"id": "release", "label": "Formal".tl, "icon": Icons.verified},
      {"id": "snapshot", "label": "Test".tl, "icon": Icons.bug_report},
      {"id": "old_beta", "label": "Ancient (Beta)".tl, "icon": Icons.history},
      {"id": "old_alpha", "label": "Ancient (Alpha)".tl, "icon": Icons.hourglass_empty},
    ];

    return Container(
      width: 64,
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: theme.dividerColor.withValues(alpha: 0.1))),
      ),
      child: Column(
        children: categories.map((cat) {
          final isSelected = currentType == cat["id"];
          return Tooltip(
            message: cat["label"] as String,
            child: InkWell(
              onTap: () => setState(() => currentType = cat["id"] as String),
              child: Container(
                height: 64,
                width: 64,
                color: isSelected ? theme.colorScheme.primary.withValues(alpha: 0.1) : null,
                child: Icon(
                  cat["icon"] as IconData,
                  color: isSelected ? theme.colorScheme.primary : theme.colorScheme.outline,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Future<void> _confirmInstallVanilla(String versionId) async {
    final v = allVanillaVersions.firstWhere((element) => element.id == versionId);
    final String targetPath = LaunchService.instance.getPreferredDownloadDir();
    final targetDir = Directory(targetPath);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Install Minecraft".tl),
        content: Text("${"Install".tl} ${versionId} ${"to".tl} ${targetDir.path}?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text("Cancel".tl)),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text("Install".tl)),
        ],
      ),
    );

    if (confirm == true) {
      await DownloadService.instance.installVanilla(versionId, v.url, targetDir);
      showSuccess("Installation task for ${versionId} submitted.".tl);
    }
  }

  Future<void> _confirmInstallLoader(String loaderVersion) async {
    if (selectedMcVersion == null) return;
    final String targetPath = LaunchService.instance.getPreferredDownloadDir();
    final targetDir = Directory(targetPath);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Install Mod Loader".tl),
        content: Text("${"Install".tl} ${widget.type.name} $loaderVersion ${"for".tl} $selectedMcVersion?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text("Cancel".tl)),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text("Install".tl)),
        ],
      ),
    );

    if (confirm == true) {
      await DownloadService.instance.installLoader(selectedMcVersion!, loaderVersion, widget.type, targetDir);
      showSuccess("Installation task for ${widget.type.name} $loaderVersion submitted.".tl);
    }
  }
}
