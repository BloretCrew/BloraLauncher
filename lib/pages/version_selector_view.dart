import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../core/grammer_candy.dart';
import '../core/i18n.dart';
import '../services/download_service.dart';
import '../services/launch_service.dart';
import '../widgets/button.dart';
import '../widgets/google_widgets.dart';
import 'mods_page.dart';

class VersionSelectorView extends StatefulWidget {
  final VoidCallback onBack;

  const VersionSelectorView({super.key, required this.onBack});

  @override
  State<VersionSelectorView> createState() => _VersionSelectorViewState();
}

class _VersionSelectorViewState extends State<VersionSelectorView>
    with TickerProviderStateMixin {
  List<MinecraftVersion> allVanillaVersions = [];
  bool isLoading = true;

  final Set<String> _expandedKeys = {"latest"};

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";
  bool _showSearchBar = false;

  MinecraftVersion? _selectedVersion;
  final TextEditingController _customNameController = TextEditingController();
  String? _customIconPath;
  String? _selectedTargetDir;

  // Loader State
  final Map<LoaderType, List<Map<String, dynamic>>> _loaderVersionsMap =
      <LoaderType, List<Map<String, dynamic>>>{};
  final Map<LoaderType, bool> _isLoadingLoadersMap = {};
  final Set<LoaderType> _expandedLoaders = {};
  LoaderType? _selectedLoader;
  String? _selectedLoaderVersion;
  bool _isAccelerated = false;

  final PageController _pageController = PageController();

  @override
  void initState() {
    super.initState();
    _loadData();
    _selectedTargetDir = LaunchService.instance.getPreferredDownloadDir();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
    DownloadService.instance.addListener(_onDownloadServiceUpdate);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _customNameController.dispose();
    DownloadService.instance.removeListener(_onDownloadServiceUpdate);
    _pageController.dispose();
    super.dispose();
  }

  void _onDownloadServiceUpdate() {
    if (mounted) {
      setState(() {
        if (!DownloadService.instance.isVersionsUpdating) {
          allVanillaVersions = DownloadService.instance.cachedVanillaVersions;
        }
      });
    }
  }

  Future<void> _loadData() async {
    allVanillaVersions = await DownloadService.instance
        .fetchAllVanillaVersions();
    if (mounted) setState(() => isLoading = false);
  }

  Future<void> _fetchLoaderVersions(LoaderType type) async {
    if (_selectedVersion == null) return;
    if (_loaderVersionsMap.containsKey(type)) {
      // Toggle expansion if already loaded
      setState(() {
        if (_expandedLoaders.contains(type)) {
          _expandedLoaders.remove(type);
        } else {
          _expandedLoaders.add(type);
        }
      });
      return;
    }

    setState(() {
      _isLoadingLoadersMap[type] = true;
      // Note: Auto-expansion is not triggered here to let user click manually
    });

    try {
      final versions = await DownloadService.instance.fetchLoaderVersions(
        _selectedVersion!.id,
        type,
      );
      if (mounted) {
        setState(() {
          _loaderVersionsMap[type] = versions;
          _isLoadingLoadersMap[type] = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingLoadersMap[type] = false);
        showError("Failed to fetch loader versions".tl);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ds = DownloadService.instance;

    return PageView(
      controller: _pageController,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        Column(
          key: const ValueKey("list_view"),
          children: [
            _buildHeader(theme),
            AnimatedSize(
              duration: const Duration(milliseconds: 400),
              curve: Curves.fastOutSlowIn,
              alignment: Alignment.topCenter,
              child: ds.isVersionsUpdating
                  ? _buildUpdateProgress(theme, ds)
                  : const SizedBox(width: double.infinity, height: 0),
            ),
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : allVanillaVersions.isEmpty && !ds.isVersionsUpdating
                  ? _buildErrorState(theme)
                  : _buildVersionList(theme),
            ),
          ],
        ),
        _buildDetailsView(theme),
      ],
    );
  }

  Widget _buildDetailsView(ThemeData theme) {
    if (_selectedVersion == null) return const SizedBox.shrink();
    final dateStr = DateFormat(
      'yyyy-MM-dd',
    ).format(_selectedVersion!.releaseTime);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
        children: [
          // Row 1: Back and Title
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, size: 28),
                onPressed: () async {
                  await _pageController.previousPage(
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeInOutCubic,
                  );
                  if (mounted) {
                    setState(() {
                      _selectedVersion = null;
                      _selectedLoader = null;
                      _selectedLoaderVersion = null;
                      _loaderVersionsMap.clear();
                      _isLoadingLoadersMap.clear();
                      _expandedLoaders.clear();
                      _isAccelerated = false;
                      _customIconPath = null;
                    });
                  }
                },
              ),
              const SizedBox(width: 8),
              Text(
                "Install Options".tl,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Row 2: Icon, Info, Download
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(width: 8),
              Tooltip(
                message: "Click to change icon".tl,
                child: InkWell(
                  onTap: () async {
                    FilePickerResult? result = await FilePicker.platform
                        .pickFiles(type: FileType.image);
                    if (result != null && result.files.single.path != null) {
                      setState(() {
                        _customIconPath = result.files.single.path;
                      });
                    }
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: _customIconPath != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.file(
                              File(_customIconPath!),
                              fit: BoxFit.cover,
                            ),
                          )
                        : Icon(
                            _isAccelerated
                                ? Icons.bolt_outlined
                                : Icons.auto_awesome_outlined,
                            size: 32,
                            color: theme.colorScheme.primary,
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: _customNameController,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                      decoration: InputDecoration(
                        hintText: "Instance Name".tl,
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () async {
                        String? path = await FilePicker.platform
                            .getDirectoryPath();
                        if (path != null) {
                          setState(() {
                            _selectedTargetDir = path;
                          });
                        }
                      },
                      child: Row(
                        children: [
                          Icon(
                            Icons.folder_outlined,
                            size: 14,
                            color: theme.colorScheme.outline,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _selectedTargetDir ??
                                  "Select Target Directory".tl,
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.outline,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _selectedVersion!.id,
                            style: TextStyle(
                              color: theme.colorScheme.onSecondaryContainer,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (_isAccelerated) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              "ACCELERATED".tl,
                              style: const TextStyle(
                                color: Colors.amber,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(width: 12),
                        Text(
                          dateStr,
                          style: TextStyle(
                            color: theme.colorScheme.outline,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              BloretButton(
                height: 46,
                onPressed: _startInstallation,
                text: "Download".tl,
                icon: Icons.download,
              ),
            ],
          ),
          const SizedBox(height: 32),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Mod Loader Selectors".tl,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                _buildLoaderSection(
                  LoaderType.vanilla,
                  "Vanilla".tl,
                  Icons.eco_outlined,
                  theme,
                ),
                const SizedBox(height: 10),
                _buildLoaderSection(
                  LoaderType.fabric,
                  "Fabric",
                  CupertinoIcons.map_fill,
                  theme,
                  true,
                ),
                const SizedBox(height: 10),
                _buildLoaderSection(
                  LoaderType.forge,
                  "Forge",
                  Icons.fireplace_outlined,
                  theme,
                ),
                const SizedBox(height: 10),
                _buildLoaderSection(
                  LoaderType.neoforge,
                  "NeoForge",
                  Icons.handyman_outlined,
                  theme,
                ),
                const SizedBox(height: 10),
                _buildLoaderSection(
                  LoaderType.quilt,
                  "Quilt",
                  Icons.grid_view_outlined,
                  theme,
                ),
              ],
            ),
          ),
          const SizedBox(height: 48),
        ],
      ),
    );
  }

  Widget _buildLoaderSection(
    LoaderType type,
    String label,
    IconData icon,
    ThemeData theme, [
    bool fabric = false,
  ]) {
    final bool isSelected = _selectedLoader == type;
    final versions = _loaderVersionsMap[type];
    final isLoading = _isLoadingLoadersMap[type] ?? false;
    final bool isExpanded = _expandedLoaders.contains(type);

    // Auto-fetch if not loaded and this is the details view
    if (type != LoaderType.vanilla && versions == null && !isLoading) {
      Future.microtask(() => _fetchLoaderVersions(type));
    }

    return Container(
      decoration: BoxDecoration(
        color: isSelected
            ? theme.colorScheme.primary.withValues(alpha: 0.05)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
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
                    _selectedLoader = LoaderType.vanilla;
                    _selectedLoaderVersion = null;
                    if (_selectedVersion != null) {
                      _customNameController.text = _selectedVersion!.id;
                    }
                  });
                  return;
                }
                setState(() {
                  if (isExpanded) {
                    _expandedLoaders.remove(type);
                  } else {
                    _expandedLoaders.add(type);
                  }
                });
              },
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
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
                              color: isSelected
                                  ? theme.colorScheme.primary
                                  : null,
                            ),
                          ),
                          if (isSelected &&
                              (type == LoaderType.vanilla ||
                                  _selectedLoaderVersion != null))
                            Text(
                              type == LoaderType.vanilla
                                  ? "Official Clean Version".tl
                                  : _selectedLoaderVersion!,
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.primary.withValues(
                                  alpha: 0.7,
                                ),
                              ),
                            )
                          else
                            Text(
                              type == LoaderType.vanilla
                                  ? "Install Minecraft without any mods".tl
                                  : versions == null
                                  ? "Loading versions...".tl
                                  : versions.isEmpty
                                  ? "No compatible loader versions found for this MC version"
                                        .tl
                                  : "${versions.length} ${"versions available".tl}",
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.outline,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (isLoading)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else if (type != LoaderType.vanilla)
                      AnimatedRotation(
                        turns: isExpanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          Icons.expand_more,
                          color: theme.colorScheme.outline,
                        ),
                      )
                    else if (isSelected)
                      Icon(
                        Icons.check_circle,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
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
                      constraints: const BoxConstraints(maxHeight: 320),
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildLoaderVersionList(type, versions, theme),
                    )
                  : const SizedBox(width: double.infinity, height: 0),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoaderVersionList(
    LoaderType type,
    List<Map<String, dynamic>> versions,
    ThemeData theme,
  ) {
    if (versions.isEmpty) return const SizedBox.shrink();

    // Fabric/Quilt/NeoForge: first one is usually latest stable
    // We separate them by stable/snapshot and put latest stable at front
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
        if (idx == 0) {
          return _buildLoaderVersionTile(
            type,
            latestStable,
            theme,
            isLatest: true,
          );
        }
        return _buildLoaderVersionTile(type, others[idx - 1], theme);
      },
    );
  }

  Widget _buildLoaderVersionTile(
    LoaderType type,
    Map<String, dynamic> vData,
    ThemeData theme, {
    bool isLatest = false,
  }) {
    final String v = vData['version'];
    final bool isSelected = _selectedLoader == type;
    final bool isVerSelected = isSelected && _selectedLoaderVersion == v;
    final String typeLabel = vData['type'] ?? "Stable".tl;
    final Color typeColor = vData['stable'] == false
        ? Colors.orange
        : Colors.green;
    final String? date = vData['time'] != null
        ? DateFormat('yyyy-MM-dd').format(DateTime.parse(vData['time']))
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedLoader = type;
            _selectedLoaderVersion = v;
            _expandedLoaders.remove(type);
            if (_selectedVersion != null) {
              _customNameController.text =
                  "${_selectedVersion!.id}-${type.name}-$v";
            }
          });
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isVerSelected
                ? theme.colorScheme.primary.withValues(alpha: 0.1)
                : theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.3,
                  ),
            borderRadius: BorderRadius.circular(12),
            border: isVerSelected
                ? Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.3),
                  )
                : Border.all(color: theme.dividerColor.withValues(alpha: 0.05)),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color:
                      (isVerSelected
                              ? theme.colorScheme.primary
                              : theme.colorScheme.secondary)
                          .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.terminal_outlined,
                  color: isVerSelected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.secondary,
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
                        Text(
                          v,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: isVerSelected
                                ? theme.colorScheme.primary
                                : null,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (isLatest) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              "RECOMMENDED".tl,
                              style: const TextStyle(
                                color: Colors.green,
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          typeLabel,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: typeColor.withValues(alpha: 0.8),
                          ),
                        ),
                        if (date != null) ...[
                          const SizedBox(width: 6),
                          Text(
                            "·",
                            style: TextStyle(
                              color: theme.colorScheme.outline,
                              fontSize: 10,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            date,
                            style: TextStyle(
                              fontSize: 10,
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (isVerSelected)
                Icon(
                  Icons.check_circle,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _startInstallation() async {
    if (_selectedVersion == null) return;
    final String baseVersionId = _selectedVersion!.id;
    final String customName = _customNameController.text.trim().isEmpty
        ? baseVersionId
        : _customNameController.text.trim();
    final String targetPath =
        _selectedTargetDir ?? LaunchService.instance.getPreferredDownloadDir();
    final targetDir = Directory(targetPath);

    String finalVersionId = customName;
    if (_selectedLoader != null && _selectedLoader != LoaderType.vanilla) {
      if (_selectedLoaderVersion == null) {
        showWarning("Please select a loader version first".tl);
        return;
      }
    }

    final versionPath = p.join(targetDir.path, "versions", finalVersionId);
    final versionDir = Directory(versionPath);
    if (await versionDir.exists()) {
      bool isJunk = true;
      try {
        final entities = await versionDir.list().toList();
        for (var entity in entities) {
          final name = p.basename(entity.path).toLowerCase();
          if (entity is File) {
            if (name.endsWith(".json") || name.endsWith(".jar")) {
              isJunk = false;
              break;
            }
          } else if (entity is Directory) {
            if (name == "saves" || name == "screenshots" || name == "resourcepacks") {
              isJunk = false;
              break;
            }
          }
        }
      } catch (_) {
        isJunk = false;
      }

      if (!isJunk) {
        showError("A valid version or user data already exists in this folder".tl);
        return;
      } else {
        try {
          await versionDir.delete(recursive: true);
        } catch (e) {
          showError("Failed to clear existing invalid folder: $e".tl);
          return;
        }
      }
    }

    Future<void> copyIcon(String vid) async {
      if (_customIconPath != null) {
        try {
          final versionPath = p.join(targetDir.path, "versions", vid);
          await Directory(versionPath).create(recursive: true);
          final destFile = File(p.join(versionPath, "icon.png"));
          await File(_customIconPath!).copy(destFile.path);
          debugPrint("Icon copied to ${destFile.path}");
        } catch (e) {
          debugPrint("Failed to copy icon: $e");
        }
      }
    }

    showSuccess("Installation task for %s submitted.".tl.format(customName));
    _pageController
        .animateToPage(
      0,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOutCubic,
    )
        .then((_) {
      if (mounted) {
        setState(() {
          _selectedVersion = null;
          _selectedLoader = null;
          _selectedLoaderVersion = null;
          _loaderVersionsMap.clear();
          _isLoadingLoadersMap.clear();
          _expandedLoaders.clear();
          _isAccelerated = false;
          _customIconPath = null;
        });
      }
    });

    if (_isAccelerated &&
        (baseVersionId == "1.21.8" || baseVersionId == "1.21.7")) {
      final url =
          "https://raw.gitcode.com/Bloret/$baseVersionId/archive/refs/heads/main.zip";
      await DownloadService.instance.downloadFile(
        "Install_$finalVersionId",
        url,
        "minecraft_source_$baseVersionId.zip",
        (path, updateStatus) async {
          updateStatus("Extracting...".tl);
          final success = await DownloadService.instance.extractZip(
            File(path),
            Directory(p.join(targetDir.path, "versions", finalVersionId)),
            stripRoot: true,
          );
          if (success) {
            await copyIcon(finalVersionId);
            showSuccess("Minecraft $customName installed".tl);
          } else {
            showError("Installation failed".tl);
          }
          try {
            await File(path).delete();
          } catch (_) {}
          return success;
        },
      );
    } else if (_selectedLoader == null ||
        _selectedLoader == LoaderType.vanilla) {
      await copyIcon(finalVersionId);
      await DownloadService.instance.installVanilla(
        finalVersionId,
        _selectedVersion!.url,
        targetDir,
      );
    } else {
      await copyIcon(finalVersionId);
      await DownloadService.instance.installLoader(
        baseVersionId,
        _selectedLoaderVersion!,
        _selectedLoader!,
        targetDir,
        customVersionId: finalVersionId,
      );
    }
  }

  Widget _buildUpdateProgress(ThemeData theme, DownloadService ds) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Column(
        children: [
          Row(
            children: [
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  ds.versionsUpdateStatus,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              Text(
                "${(ds.versionsUpdateProgress * 100).toInt()}%",
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: IgnorePointer(
              child: GoogleSquigglySlider(
                value: ds.versionsUpdateProgress,
                paddingH: 0,
                paddingV: 0,
                max: 1,
                height: 8,
                hasThumb: false,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: 64,
            color: theme.colorScheme.error.withOpacityEx(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            "Failed to fetch versions".tl,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            "Please check your internet connection".tl,
            style: TextStyle(color: theme.colorScheme.outline),
          ),
          const SizedBox(height: 24),
          BloretButton(
            onPressed: () => DownloadService.instance.fetchAllVanillaVersions(
              forceRefresh: true,
            ),
            text: "Retry".tl,
            icon: Icons.refresh,
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: widget.onBack,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.2),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                );
              },
              child: _showSearchBar
                  ? TextField(
                      key: const ValueKey("search_field"),
                      controller: _searchController,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: "Search versions...".tl,
                        isDense: true,
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () {
                            setState(() {
                              _showSearchBar = false;
                              _searchController.clear();
                            });
                          },
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                    )
                  : Text(
                      "Minecraft ${"Installation".tl}",
                      key: const ValueKey("title_text"),
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
          if (!_showSearchBar) ...[
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(scale: animation, child: child),
              ),
              child: DownloadService.instance.isVersionsUpdating
                  ? const Padding(
                      key: ValueKey("updating_indicator"),
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    )
                  : IconButton(
                      key: const ValueKey("refresh_button"),
                      icon: const Icon(Icons.refresh),
                      tooltip: "Refresh".tl,
                      onPressed: () => DownloadService.instance
                          .fetchAllVanillaVersions(forceRefresh: true),
                    ),
            ),
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: () => setState(() => _showSearchBar = true),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVersionList(ThemeData theme) {
    if (allVanillaVersions.isEmpty) {
      return Center(child: Text("No versions found".tl));
    }

    Widget content;
    if (_searchQuery.isNotEmpty) {
      final results = allVanillaVersions
          .where((v) => v.id.toLowerCase().contains(_searchQuery))
          .toList();
      content = ListView.builder(
        key: ValueKey("search_results_${_searchQuery.hashCode}"),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        itemCount: results.length,
        itemBuilder: (context, index) =>
            _buildVersionTile(results[index], theme),
      );
    } else {
      final latestRelease = allVanillaVersions.firstWhere(
        (v) => v.type == "release",
      );
      final latestSnapshot = allVanillaVersions.firstWhere(
        (v) => v.type == "snapshot",
      );

      final aprilFools = allVanillaVersions
          .where((v) => _isAprilFools(v.id))
          .toList();
      final remaining = allVanillaVersions
          .where((v) => !_isAprilFools(v.id))
          .toList();

      final releases = remaining.where((v) => v.type == "release").toList();
      final snapshots = remaining.where((v) => v.type == "snapshot").toList();
      final oldBetas = remaining.where((v) => v.type == "old_beta").toList();
      final oldAlphas = remaining.where((v) => v.type == "old_alpha").toList();

      content = ListView(
        key: const ValueKey("category_list"),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.1),
              ),
            ),
            child: Stack(
              children: [
                Align(
                  alignment: .centerRight,
                  child: CustomPaint(
                    painter: BloretIcon(color: Colors.grey.withOpacityEx(0.2)),
                    size: const Size(120, 120),
                  ),
                ),
                Column(
                  children: [
                    if (allVanillaVersions.any((v) => v.id == "1.21.8"))
                      _buildVersionTile(
                        allVanillaVersions.firstWhere((v) => v.id == "1.21.8"),
                        theme,
                        isLatest: true,
                        label: "Bloret Speed-up Version".tl,
                        icon: Icons.double_arrow,
                        forceAccelerated: true,
                      ),
                    if (allVanillaVersions.any((v) => v.id == "1.21.8") &&
                        allVanillaVersions.any((v) => v.id == "1.21.7"))
                      Divider(
                        height: 1,
                        indent: 12,
                        endIndent: 12,
                        color: theme.dividerColor.withValues(alpha: 0.05),
                      ),
                    if (allVanillaVersions.any((v) => v.id == "1.21.7"))
                      _buildVersionTile(
                        allVanillaVersions.firstWhere((v) => v.id == "1.21.7"),
                        theme,
                        isLatest: true,
                        label: "Bloret Speed-up Version".tl,
                        icon: Icons.double_arrow,
                        forceAccelerated: true,
                      ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.1),
              ),
            ),
            child: Column(
              children: [
                _buildVersionTile(
                  latestRelease,
                  theme,
                  isLatest: true,
                  label: "Latest Release".tl,
                ),
                Divider(
                  height: 1,
                  indent: 12,
                  endIndent: 12,
                  color: theme.dividerColor.withValues(alpha: 0.05),
                ),
                _buildVersionTile(
                  latestSnapshot,
                  theme,
                  isLatest: true,
                  label: "Latest Snapshot".tl,
                  icon: Icons.bug_report_outlined,
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          _buildSection(
            "Release".tl,
            "${releases.length} ${"versions".tl}",
            Icons.verified_outlined,
            "release",
            releases,
            theme,
          ),
          const SizedBox(height: 12),
          _buildSection(
            "Snapshot".tl,
            "${snapshots.length} ${"versions".tl}",
            Icons.science_outlined,
            "snapshot",
            snapshots,
            theme,
            useGrouping: true,
          ),
          const SizedBox(height: 12),
          _buildSection(
            "April Fools'".tl,
            "${aprilFools.length} ${"versions".tl}",
            Icons.celebration_outlined,
            "april_fools",
            aprilFools,
            theme,
          ),
          const SizedBox(height: 12),
          _buildSection(
            "Ancient (Beta)".tl,
            "${oldBetas.length} ${"versions".tl}",
            Icons.history,
            "old_beta",
            oldBetas,
            theme,
          ),
          const SizedBox(height: 12),
          _buildSection(
            "Ancient (Alpha)".tl,
            "${oldAlphas.length} ${"versions".tl}",
            Icons.hourglass_empty,
            "old_alpha",
            oldAlphas,
            theme,
          ),
          const SizedBox(height: 24),
        ],
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.02),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: content,
    );
  }

  Widget _buildSection(
    String title,
    String subtitle,
    IconData icon,
    String key,
    List<MinecraftVersion> versions,
    ThemeData theme, {
    bool useGrouping = false,
  }) {
    if (versions.isEmpty) return const SizedBox.shrink();
    final bool isExpanded = _expandedKeys.contains(key);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.05)),
      ),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                setState(() {
                  if (isExpanded) {
                    _expandedKeys.remove(key);
                  } else {
                    _expandedKeys.add(key);
                  }
                });
              },
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Icon(icon, color: theme.colorScheme.primary, size: 22),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          Text(
                            subtitle,
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ],
                      ),
                    ),
                    AnimatedRotation(
                      turns: isExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        Icons.expand_more,
                        color: theme.colorScheme.outline,
                      ),
                    ),
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
              child: isExpanded
                  ? Container(
                      constraints: const BoxConstraints(maxHeight: 360),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: useGrouping
                            ? _buildGroupedVersionList(versions, theme)
                            : Column(
                                children: versions
                                    .map(
                                      (v) => Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                        ),
                                        child: _buildVersionTile(v, theme),
                                      ),
                                    )
                                    .toList(),
                              ),
                      ),
                    )
                  : const SizedBox(width: double.infinity, height: 0),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupedVersionList(
    List<MinecraftVersion> versions,
    ThemeData theme,
  ) {
    // Group snapshots by their year/prefix (e.g., "24w", "23w")
    final Map<String, List<MinecraftVersion>> groups = {};
    for (var v in versions) {
      String groupKey = "Other".tl;
      if (v.id.contains('w')) {
        groupKey = v.id.substring(0, v.id.indexOf('w') + 1); // e.g., "24w"
      } else if (v.id.startsWith('1.')) {
        final parts = v.id.split('.');
        if (parts.length >= 2) groupKey = "${parts[0]}.${parts[1]}";
      }
      groups.putIfAbsent(groupKey, () => []).add(v);
    }

    final groupKeys = groups.keys.toList();

    return Column(
      children: groupKeys.map((gk) {
        final groupVersions = groups[gk]!;
        final subKey = "sub_$gk";
        final bool isSubExpanded = _expandedKeys.contains(subKey);

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Column(
            children: [
              InkWell(
                onTap: () {
                  setState(() {
                    if (isSubExpanded) {
                      _expandedKeys.remove(subKey);
                    } else {
                      _expandedKeys.add(subKey);
                    }
                  });
                },
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Text(
                        gk,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        "(${groupVersions.length})",
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.outline,
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        isSubExpanded ? Icons.expand_less : Icons.expand_more,
                        size: 16,
                        color: theme.colorScheme.outline,
                      ),
                    ],
                  ),
                ),
              ),
              ClipRect(
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOutCubic,
                  alignment: Alignment.topCenter,
                  child: isSubExpanded
                      ? ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: groupVersions.length,
                          itemBuilder: (context, index) => Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: _buildVersionTile(
                              groupVersions[index],
                              theme,
                            ),
                          ),
                        )
                      : const SizedBox(width: double.infinity, height: 0),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  bool _isAprilFools(String id) {
    const jokes = {
      '26w14a',
      '25w14craftmine',
      '23w13a_or_b',
      '24w14spoiler',
      '24w14potato',
      '22w13oneblockatatime',
      '20w14infinite',
      '3D Shareware v1.34',
      '1.RV-Pre1',
      '15w14a',
      '2.0',
    };
    if (jokes.contains(id)) return true;
    if (id.contains('love') || id.contains('joke') || id.contains('spoiler')) {
      return true;
    }
    return false;
  }

  Widget _buildVersionTile(
    MinecraftVersion version,
    ThemeData theme, {
    bool isLatest = false,
    String? label,
    IconData? icon,
    bool forceAccelerated = false,
  }) {
    final dateStr = DateFormat('yyyy-MM-dd').format(version.releaseTime);
    final bool isAprilFools = _isAprilFools(version.id);

    return Padding(
      padding: const EdgeInsets.only(bottom: 2, top: 2),
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedVersion = version;
            _customNameController.text = version.id;
            _selectedLoader = null; // Don't select any loader by default
            _selectedLoaderVersion = null;
            _isAccelerated = forceAccelerated;
          });
          _pageController.nextPage(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOutCubic,
          );
        },
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isLatest
                ? Colors.transparent
                : theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.3,
                  ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color:
                      (isAprilFools ? Colors.purple : theme.colorScheme.primary)
                          .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isAprilFools
                      ? Icons.celebration_outlined
                      : (icon ?? Icons.view_in_ar_outlined),
                  size: 18,
                  color: isAprilFools
                      ? Colors.purple
                      : theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      version.id == '20w14infinite' ? '20w14∞' : version.id,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Row(
                      children: [
                        Text(
                          label ?? dateStr,
                          style: TextStyle(
                            fontSize: 11,
                            color: isLatest
                                ? theme.colorScheme.primary.withValues(
                                    alpha: 0.7,
                                  )
                                : Colors.grey,
                          ),
                        ),
                        if (isAprilFools) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.purple.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              "April Fools'".tl,
                              style: const TextStyle(
                                color: Colors.purple,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: theme.colorScheme.outline.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
