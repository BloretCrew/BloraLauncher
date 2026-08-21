import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/grammer_candy.dart';
import '../core/i18n.dart';
import '../services/download_service.dart';
import 'dart:io';

class VersionLoaderSelector extends StatefulWidget {
  final String mcVersion;
  final String targetDirectory;
  final String customVersionId;
  final VoidCallback onCompleted;

  const VersionLoaderSelector({
    super.key,
    required this.mcVersion,
    required this.targetDirectory,
    required this.customVersionId,
    required this.onCompleted,
  });

  @override
  State<VersionLoaderSelector> createState() => _VersionLoaderSelectorState();
}

class _VersionLoaderSelectorState extends State<VersionLoaderSelector> {
  final Map<LoaderType, List<Map<String, dynamic>>> _loaderVersionsMap = {};
  final Map<LoaderType, bool> _isLoadingMap = {};
  final Set<LoaderType> _expandedLoaders = {};
  
  LoaderType? _selectedType;
  String? _selectedLoaderVersion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              _buildOption(LoaderType.vanilla, "Vanilla".tl, Icons.eco_outlined, theme),
              const SizedBox(height: 12),
              _buildOption(LoaderType.fabric, "Fabric", CupertinoIcons.map_fill, theme, true),
              const SizedBox(height: 12),
              _buildOption(LoaderType.forge, "Forge", Icons.fireplace_outlined, theme),
              const SizedBox(height: 12),
              _buildOption(LoaderType.neoforge, "NeoForge", Icons.handyman_outlined, theme),
              const SizedBox(height: 12),
              _buildOption(LoaderType.quilt, "Quilt", Icons.grid_view_outlined, theme),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: ElevatedButton.icon(
            onPressed: _selectedType == null ? null : _apply,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 54),
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: theme.colorScheme.onPrimary,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            icon: const Icon(Icons.check_circle_outline),
            label: Text("Install & Apply".tl, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ),
      ],
    );
  }

  Widget _buildOption(LoaderType type, String label, IconData icon, ThemeData theme, [bool fabric = false]) {
    final bool isSelected = _selectedType == type;
    final bool isExpanded = _expandedLoaders.contains(type);
    final versions = _loaderVersionsMap[type];
    final isLoading = _isLoadingMap[type] ?? false;

    return Container(
      decoration: BoxDecoration(
        color: isSelected
            ? theme.colorScheme.primary.withValues(alpha: 0.05)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected
              ? theme.colorScheme.primary.withValues(alpha: 0.3)
              : theme.dividerColor.withValues(alpha: 0.05),
        ),
      ),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                if (type == LoaderType.vanilla) {
                  setState(() {
                    _selectedType = LoaderType.vanilla;
                    _selectedLoaderVersion = null;
                  });
                  return;
                }
                if (versions == null && !isLoading) {
                  _fetch(type);
                }
                setState(() {
                  if (isExpanded) {
                    _expandedLoaders.remove(type);
                  } else {
                    _expandedLoaders.add(type);
                  }
                });
              },
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    RotatedBox(
                      quarterTurns: fabric ? 1 : 0,
                      child: Icon(
                        icon,
                        color: isSelected ? theme.colorScheme.primary : null,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: isSelected ? theme.colorScheme.primary : null,
                            ),
                          ),
                          if (isSelected && (type == LoaderType.vanilla || _selectedLoaderVersion != null))
                            Text(
                              type == LoaderType.vanilla ? "Official Clean Version".tl : _selectedLoaderVersion!,
                              style: TextStyle(fontSize: 12, color: theme.colorScheme.primary.withValues(alpha: 0.7)),
                            )
                          else
                            Text(
                              type == LoaderType.vanilla 
                                ? "Install Minecraft without any mods".tl 
                                : versions == null 
                                  ? "Loading versions...".tl 
                                  : "${versions.length} ${"versions available".tl}",
                              style: TextStyle(fontSize: 12, color: theme.colorScheme.outline),
                            ),
                        ],
                      ),
                    ),
                    if (isLoading)
                      const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5))
                    else if (type != LoaderType.vanilla)
                      AnimatedRotation(
                        turns: isExpanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 250),
                        child: Icon(Icons.expand_more, color: theme.colorScheme.outline),
                      )
                    else if (isSelected)
                      Icon(Icons.check_circle, size: 20, color: theme.colorScheme.primary),
                  ],
                ),
              ),
            ),
          ),
          ClipRect(
            child: AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOutCubic,
              alignment: Alignment.topCenter,
              child: isExpanded && versions != null
                  ? Container(
                      constraints: const BoxConstraints(maxHeight: 280),
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildVersionList(type, versions, theme),
                    )
                  : const SizedBox(width: double.infinity, height: 0),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVersionList(LoaderType type, List<Map<String, dynamic>> versions, ThemeData theme) {
    if (versions.isEmpty) return Center(child: Text("No compatible versions found".tl, style: const TextStyle(fontSize: 11)));

    final latestStable = versions.firstWhere(
      (v) => v['stable'] == true,
      orElse: () => versions.first,
    );
    final others = versions.where((v) => v != latestStable).toList();

    return ListView.builder(
      shrinkWrap: true,
      physics: const ClampingScrollPhysics(),
      itemCount: others.length + 1,
      itemBuilder: (context, idx) {
        final vData = idx == 0 ? latestStable : others[idx - 1];
        final String v = vData['version'];
        final bool isVerSelected = _selectedType == type && _selectedLoaderVersion == v;
        final String typeLabel = vData['type'] ?? "Stable".tl;
        final Color typeColor = vData['stable'] == false ? Colors.orange : Colors.green;
        final String? date = vData['time'] != null 
            ? DateFormat('yyyy-MM-dd').format(DateTime.parse(vData['time'])) 
            : null;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Material(
            color: isVerSelected
                ? theme.colorScheme.primary.withValues(alpha: 0.1)
                : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: () {
                setState(() {
                  _selectedType = type;
                  _selectedLoaderVersion = v;
                  _expandedLoaders.remove(type);
                });
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isVerSelected ? theme.colorScheme.primary.withValues(alpha: 0.3) : Colors.transparent,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: (isVerSelected ? theme.colorScheme.primary : theme.colorScheme.secondary).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.terminal_outlined,
                        color: isVerSelected ? theme.colorScheme.primary : theme.colorScheme.secondary,
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(v, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isVerSelected ? theme.colorScheme.primary : null)),
                              if (idx == 0) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                                  child: Text("RECOMMENDED".tl, style: const TextStyle(color: Colors.green, fontSize: 8, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Text(typeLabel, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: typeColor.withValues(alpha: 0.8))),
                              if (date != null) ...[
                                const SizedBox(width: 6),
                                Text("·", style: TextStyle(color: theme.colorScheme.outline, fontSize: 10)),
                                const SizedBox(width: 6),
                                Text(date, style: TextStyle(fontSize: 10, color: theme.colorScheme.outline)),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (isVerSelected) Icon(Icons.check_circle, size: 18, color: theme.colorScheme.primary),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _fetch(LoaderType type) async {
    setState(() => _isLoadingMap[type] = true);
    try {
      final res = await DownloadService.instance.fetchLoaderVersions(widget.mcVersion, type);
      if (mounted) {
        setState(() {
          _loaderVersionsMap[type] = res;
          _isLoadingMap[type] = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingMap[type] = false);
    }
  }

  void _apply() async {
    showInfo("Switching loader...".tl);
    final dir = Directory(widget.targetDirectory);
    if (_selectedType == LoaderType.vanilla) {
      final List<MinecraftVersion> vanillas = await DownloadService.instance.fetchAllVanillaVersions();
      final version = vanillas.firstWhere((v) => v.id == widget.mcVersion, orElse: () => throw Exception("Version not found"));
      await DownloadService.instance.installVanilla(widget.customVersionId, version.url, dir);
    } else {
      await DownloadService.instance.installLoader(
        widget.mcVersion, 
        _selectedLoaderVersion!, 
        _selectedType!, 
        dir,
        customVersionId: widget.customVersionId,
      );
    }
    widget.onCompleted();
  }
}
