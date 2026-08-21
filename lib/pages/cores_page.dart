import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bloret_launcher/widgets/google_widgets.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../core/ffi_proxy.dart';
import '../core/grammer_candy.dart';
import '../core/i18n.dart';
import '../core/java_config.dart';
import '../services/config_service.dart';
import '../services/external_app_service.dart';
import '../services/launch_service.dart';
import '../services/stats_service.dart';
import '../shell/main_shell.dart';
import '../widgets/button.dart';
import '../widgets/core_icon.dart';
import '../widgets/windows_widgets.dart';
import 'external_app_selector_view.dart';
import '../widgets/loader_selector.dart';
import '../services/minecraft_server_service.dart';

class CoresPage extends StatefulWidget {
  const CoresPage({super.key});

  @override
  State<CoresPage> createState() => _CoresPageState();
}

enum CorePageMode { list, externalEditor, coreDetail }

class _CoresPageState extends State<CoresPage> {
  List<Map<String, String>> launchItems = [];
  bool _isLoading = false;
  String _searchQuery = "";
  String? _selectedDirectoryFilter;
  final TextEditingController _searchController = TextEditingController();

  late PageController _pageController;
  CorePageMode _mode = CorePageMode.list;
  Map<String, String>? _selectedItem;
  CustomApp? _editingApp;
  final Set<String> _collapsedCategories = {};

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    LaunchService.instance.addListener(refreshLaunchItems);
    Future.delayed(const Duration(milliseconds: 100), () {
      refreshLaunchItems();
    });
  }

  @override
  void dispose() {
    LaunchService.instance.removeListener(refreshLaunchItems);
    _pageController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _switchPage(CorePageMode mode, int index) async {
    setState(() {
      _mode = mode;
    });

    final shellState = context.findAncestorStateOfType<MainShellState>();

    if (index != 0) {
      if (shellState?.isExtended == true) {
        shellState?.setNavExtended(false);
        await Future.delayed(const Duration(milliseconds: 250));
      }
    }

    if (mounted) {
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutQuart,
      );
    }
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

    items.sort((a, b) {
      final idA = a['id']!;
      final idB = b['id']!;
      final uidA = a['unique_id'] ?? idA;
      final uidB = b['unique_id'] ?? idB;
      final favA = (a['bl_favorite'] == 'true' || ConfigService.get('favorite_$uidA') == true) ? 1 : 0;
      final favB = (b['bl_favorite'] == 'true' || ConfigService.get('favorite_$uidB') == true) ? 1 : 0;
      if (favA != favB) return favB.compareTo(favA);
      return idA.toLowerCase().compareTo(idB.toLowerCase());
    });

    if (mounted) {
      setState(() {
        launchItems = items;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageView(
      controller: _pageController,
      physics: const NeverScrollableScrollPhysics(),
      children: [_buildListView(context), _buildSecondPage(context)],
    );
  }

  Widget _buildSecondPage(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: _mode == CorePageMode.externalEditor
          ? ExternalAppEditorView(
              key: const ValueKey("external_editor"),
              app: _editingApp,
              onBack: () => _switchPage(CorePageMode.list, 0),
              onSaved: () {
                _switchPage(CorePageMode.list, 0);
                refreshLaunchItems();
              },
            )
          : (_selectedItem != null
                ? CoreDetailView(
                    key: ValueKey("detail_${_selectedItem!['id']}"),
                    item: _selectedItem!,
                    onBack: () => _switchPage(CorePageMode.list, 0),
                  )
                : const SizedBox.shrink()),
    );
  }

  Widget _buildListView(BuildContext context) {
    final theme = Theme.of(context);

    // Grouping logic (using absolute path uniqueness)
    final Map<String, List<Map<String, String>>> groups = {};
    for (var item in launchItems) {
      final id = item['id']!;
      final uniqueId = item['unique_id'] ?? id;
      final type = item['type'] ?? "minecraft";

      String category = "Standard";
      if (type == "minecraft") {
        category = item['bl_instance_category'] ?? ConfigService.get('instance_category_$uniqueId') ?? "Standard";
      } else {
        category = item['category'] ?? "Standard";
      }

      groups.putIfAbsent(category, () => []).add(item);
    }

    final sortedCategories = groups.keys.toList()
      ..sort((a, b) {
        if (a == "Exclusive") return -1;
        if (b == "Exclusive") return 1;
        if (a == "Standard") return -1;
        if (b == "Standard") return 1;
        return a.compareTo(b);
      });

    return Scaffold(
      key: const ValueKey("list"),
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
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
                    itemCount: sortedCategories.length,
                    itemBuilder: (context, catIndex) {
                      final category = sortedCategories[catIndex];
                      final items = groups[category]!;
                      final isCollapsed = _collapsedCategories.contains(
                        category,
                      );

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          InkWell(
                            onTap: () {
                              setState(() {
                                if (isCollapsed) {
                                  _collapsedCategories.remove(category);
                                } else {
                                  _collapsedCategories.add(category);
                                }
                              });
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 8,
                                horizontal: 4,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    isCollapsed
                                        ? Icons.chevron_right
                                        : Icons.expand_more,
                                    size: 18,
                                    color: theme.colorScheme.outline,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    category.tl,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: theme.colorScheme.outline,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    "(${items.length})",
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: theme.colorScheme.outline
                                          .withValues(alpha: 0.6),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            transitionBuilder:
                                (Widget child, Animation<double> animation) {
                                  return SizeTransition(
                                    sizeFactor: animation,
                                    alignment: .topCenter,
                                    child: child,
                                  );
                                },
                            child: isCollapsed
                                ? const SizedBox.shrink()
                                : Column(
                                    children: items
                                        .map(
                                          (item) => _buildCoreItem(theme, item),
                                        )
                                        .toList(),
                                  ),
                          ),
                          const SizedBox(height: 4),
                        ],
                      );
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
    final uniqueId = item['unique_id'] ?? id;
    final type = item['type'] ?? "minecraft";
    final appId = item['appId'];

    String displayName = id;
    String displayDesc = item['directory']!;
    String category = "Standard";
    bool isFavorite = false;

    if (type == "minecraft") {
      displayName = item['bl_instance_name'] ?? ConfigService.get('instance_name_$uniqueId') ?? id;
      displayDesc =
          item['bl_instance_desc'] ?? ConfigService.get('instance_desc_$uniqueId') ?? item['directory']!;
      category = item['bl_instance_category'] ?? ConfigService.get('instance_category_$uniqueId') ?? "Standard";
      isFavorite = item['bl_favorite'] == 'true' || ConfigService.get('favorite_$uniqueId') == true;
    } else {
      displayName = id;
      displayDesc = item['directory']!;
      category = item['category'] ?? "Standard";
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.dividerColor.withValues(alpha: 0.1),
          width: isFavorite ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: () {
          if (type == "minecraft") {
            _selectedItem = item;
            _switchPage(CorePageMode.coreDetail, 1);
          } else {
            final apps = ExternalAppService.instance.getCustomApps();
            final app = apps.firstWhere((e) => e.id == appId);
            _editingApp = app;
            _switchPage(CorePageMode.externalEditor, 1);
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CoreIcon(item: item),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              displayName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            if (isFavorite) ...[
                              const SizedBox(width: 8),
                              const Icon(
                                Icons.star,
                                color: Colors.orange,
                                size: 16,
                              ),
                            ],
                          ],
                        ),
                        Text(
                          displayDesc,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (type == "minecraft")
                    const Icon(Icons.chevron_right, color: Colors.grey)
                  else
                    IconButton(
                      icon: const Icon(Icons.settings_outlined),
                      onPressed: () {
                        final apps = ExternalAppService.instance
                            .getCustomApps();
                        final app = apps.firstWhere((e) => e.id == appId);
                        _editingApp = app;
                        _switchPage(CorePageMode.externalEditor, 1);
                      },
                    ),
                ],
              ),
            ),
            if (category != "Standard")
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    category.tl,
                    style: TextStyle(
                      fontSize: 9,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ),
          ],
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

class CoreDetailView extends StatefulWidget {
  final Map<String, String> item;
  final VoidCallback onBack;

  const CoreDetailView({super.key, required this.item, required this.onBack});

  @override
  State<CoreDetailView> createState() => _CoreDetailViewState();
}

class _CoreDetailViewState extends State<CoreDetailView> {
  int _activeTabIndex = 0;
  Map<String, dynamic>? _versionData;
  Map<String, dynamic>? _mrpackMeta;
  Map<String, dynamic>? _stats;
  int _launchCount = 0;
  bool _isFavorite = false;

  String? _customName;
  String? _customDescription;
  String _selectedIcon = "Auto";
  String _selectedCategory = "Standard";

  String _memoryMode = "Global";
  double _customMemory = 4096;
  String _customWindowTitle = "";
  String _customInfo = "";
  String _javaSelection = "Global";
  String _restrictionMode = "None";
  String _autoJoinServer = "";
  String _renderer = "Global";
  String _jvmArgsHeader = "";
  String _gameArgsTail = "";
  String _classpathHeader = "";
  String _preLaunchCommand = "";

  // Export State
  String _exportPackName = "";
  String _exportPackVersion = "1.0.0";
  bool _exportCore = true;
  bool _exportSettings = true;
  bool _exportMods = true;
  bool _exportModConfigs = true;
  bool _exportSaves = false;
  bool _exportServers = true;
  bool _exportOthers = false;

  final TextEditingController _saveSearchController = TextEditingController();
  String _saveSearchQuery = "";

  // Screenshot State
  List<File> _screenshotFiles = [];
  final Set<int> _selectedScreenshotIndices = {};
  bool _isScreenshotMultiSelectMode = false;
  bool _isScreenshotsLoading = false;

  double _totalRamGb = 16.0;
  double _usedRamGb = 8.0;
  Timer? _memoryTimer;

  @override
  void initState() {
    super.initState();
    _loadMetadata();
    _startMemoryMonitoring();
    _saveSearchController.addListener(() {
      setState(() {
        _saveSearchQuery = _saveSearchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _memoryTimer?.cancel();
    _saveSearchController.dispose();
    super.dispose();
  }

  void _startMemoryMonitoring() {
    _updateMemoryInfo();
    _memoryTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (mounted && _activeTabIndex == 1) {
        _updateMemoryInfo();
      }
    });
  }

  Future<void> _updateMemoryInfo() async {
    if (!Platform.isWindows) return;
    try {
      final info = WinSystem.getMemoryInfo();
      setState(() {
        _totalRamGb = info["total"] ?? 16.0;
        _usedRamGb = (info["total"] ?? 16.0) - (info["free"] ?? 8.0);
      });
    } catch (_) {}
  }

  Future<void> _loadMetadata() async {
    final id = widget.item['id']!;
    final uniqueId = widget.item['unique_id'] ?? id;
    final dir = widget.item['directory']!;
    final versionDir = p.join(dir, "versions", id);

    try {
      _versionData = await LaunchService.instance.loadMergedVersionJson(dir, id);
    } catch (_) {}

    try {
      final metaFile = File(p.join(versionDir, "bloret-mrpack-meta.json"));
      if (await metaFile.exists()) {
        _mrpackMeta = jsonDecode(await metaFile.readAsString());
      }
    } catch (_) {}

    try {
      final allStats = await StatsService.instance.getVersionStats();
      _stats = allStats.firstWhere((s) => s['version'] == id, orElse: () => {});
    } catch (_) {}

    // Load from .BLF.json
    final blData = await LaunchService.instance.getBlVersionData(dir, id);
    
    // Helper to get with migration from ConfigService
    T getVal<T>(String key, T defaultValue) {
      if (blData.containsKey(key)) return blData[key] as T;
      final legacy = ConfigService.get('${key}_$uniqueId');
      if (legacy != null) {
        // Migrate immediately
        _saveConfig(key, legacy);
        return legacy as T;
      }
      return defaultValue;
    }

    _launchCount = _stats?['sessions'] ?? ConfigService.get('launch_count_$uniqueId') ?? 0;
    _isFavorite = getVal('favorite', false);

    _customName = getVal('instance_name', null);
    _customDescription = getVal('instance_desc', null);
    _selectedIcon = getVal('instance_icon', "Auto");
    _selectedCategory = getVal('instance_category', "Standard");

    _memoryMode = getVal('memory_mode', "Global");
    _customMemory = (getVal('custom_memory', 4096)).toDouble();
    _customWindowTitle = getVal('custom_window_title', "");
    _customInfo = getVal('custom_info', "");
    _javaSelection = getVal('java_selection', "Global");
    _restrictionMode = getVal('restriction_mode', "None");
    _autoJoinServer = getVal('auto_join_server', "");
    _renderer = getVal('renderer', "Global");
    _jvmArgsHeader = getVal('jvm_args_header', "");
    _gameArgsTail = getVal('game_args_tail', "");
    _classpathHeader = getVal('classpath_header', "");
    _preLaunchCommand = getVal('pre_launch_command', "");

    _exportPackName = _customName ?? id;

    // Load servers directly from game's servers.dat
    MinecraftServerService.loadFromGame(dir, id).then((list) {
      if (mounted) {
        setState(() {
          _servers = list;
          _refreshAllServers();
        });
      }
    });

    if (mounted) setState(() {});
  }

  void _saveConfig(String key, dynamic value) {
    final id = widget.item['id']!;
    final dir = widget.item['directory']!;
    
    // Save to .BLF.json via LaunchService
    LaunchService.instance.updateBlJson(dir, id, extra: {key: value});

    if (key == 'instance_icon') _selectedIcon = value;
    if (key == 'instance_category') _selectedCategory = value;
    if (key == 'memory_mode') _memoryMode = value;
    if (key == 'custom_window_title') _customWindowTitle = value;
    if (key == 'custom_info') _customInfo = value;
    if (key == 'java_selection') _javaSelection = value;
    if (key == 'restriction_mode') _restrictionMode = value;
    if (key == 'auto_join_server') _autoJoinServer = value;
    if (key == 'renderer') _renderer = value;
    if (key == 'jvm_args_header') _jvmArgsHeader = value;
    if (key == 'game_args_tail') _gameArgsTail = value;
    if (key == 'classpath_header') _classpathHeader = value;
    if (key == 'pre_launch_command') _preLaunchCommand = value;
    if (key == 'favorite') _isFavorite = value;
    if (key == 'instance_name') _customName = value;
    if (key == 'instance_desc') _customDescription = value;
    
    setState(() {});
    final coreState = context.findAncestorStateOfType<_CoresPageState>();
    coreState?.refreshLaunchItems();
  }

  final List<dynamic> _tabs = [
    (Icons.auto_awesome_outlined, "Overview".tl),
    (Icons.settings_outlined, "Settings".tl),
    (Icons.edit_note_outlined, "Modify".tl),
    (Icons.ios_share_outlined, "Export".tl),
    "divider",
    (Icons.save_outlined, "Saves".tl),
    (Icons.photo_library_outlined, "Screenshots".tl),
    (Icons.extension_outlined, "Mods".tl),
    (Icons.palette_outlined, "Resource Packs".tl),
    (Icons.wb_sunny_outlined, "Shader Packs".tl),
    (Icons.architecture_outlined, "Schematics".tl),
    (Icons.dns_outlined, "Servers".tl),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                _buildHeader(theme),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: _buildContent(theme),
                  ),
                ),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          _buildRightSidebar(theme),
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    final id = widget.item['id']!;
    final directory = widget.item['directory']!;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: widget.onBack,
          ),
          const SizedBox(width: 12),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (Widget child, Animation<double> animation) {
              return FadeTransition(opacity: animation, child: child);
            },
            child: CoreIcon(
              key: ValueKey("detail_icon_${_selectedIcon}_$_selectedCategory"),
              item: {
                ...widget.item,
                'bl_instance_icon': _selectedIcon,
                'bl_instance_category': _selectedCategory,
              },
              size: 80,
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _customName ?? id,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Tooltip(
                  message: directory,
                  child: Text(
                    (_customDescription != null &&
                            _customDescription!.isNotEmpty)
                        ? _customDescription!
                        : directory,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRightSidebar(ThemeData theme) {
    return Container(
      width: 200,
      color: theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.5),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        itemCount: _tabs.length,
        itemBuilder: (context, index) {
          final item = _tabs[index];
          if (item is String) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Divider(height: 1, indent: 8, endIndent: 8),
            );
          }

          final bool isSelected = _activeTabIndex == index;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: InkWell(
              onTap: () => setState(() => _activeTabIndex = index),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: isSelected
                      ? theme.colorScheme.primaryContainer.withValues(
                          alpha: 0.5,
                        )
                      : Colors.transparent,
                ),
                child: Row(
                  children: [
                    Icon(
                      item.$1,
                      size: 20,
                      color: isSelected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      item.$2,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isSelected
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildContent(ThemeData theme) {
    final String tabName = _tabs[_activeTabIndex] is String
        ? ""
        : _tabs[_activeTabIndex].$2;

    return ListView(
      key: ValueKey("content_$_activeTabIndex"),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      children: [
        Text(
          tabName,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        _buildSectionContent(theme),
      ],
    );
  }

  Widget _buildSectionContent(ThemeData theme) {
    switch (_activeTabIndex) {
      case 0: // Overview
        return _buildOverview(theme);
      case 1: // Settings
        return _buildSettings(theme);
      case 2: // Modify
        return _buildModify(theme);
      case 3: // Export
        return _buildExport(theme);
      case 5: // Saves
        return _buildSavesView(theme);
      case 6: // Screenshots
        return _buildScreenshotsView(theme);
      case 7: // Mods
        return _buildFolderList(theme, "mods", Icons.extension_rounded);
      case 8: // Resource Packs
        return _buildFolderList(theme, "resourcepacks", Icons.palette_rounded);
      case 9: // Shader Packs
        return _buildFolderList(theme, "shaderpacks", Icons.wb_sunny_rounded);
      case 10: // Schematics
        return _buildFolderList(theme, "schematics", Icons.architecture_rounded);
      case 11: // Servers
        return _buildServerList(theme);
      default:
        return _buildFolderAction(theme);
    }
  }

  List<MinecraftServer> _servers = [];
  bool _isPingUpdating = false;
  final Set<int> _selectedServerIndices = {};
  bool _isServerMultiSelectMode = false;

  Widget _buildServerList(ThemeData theme) {
    final _ = widget.item['id']!;
    final _ = widget.item['directory']!;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildServerToolbar(theme),
        const SizedBox(height: 16),
        if (_servers.isEmpty && !_isPingUpdating)
           Center(
             child: Padding(
               padding: const EdgeInsets.symmetric(vertical: 40),
               child: Column(
                 children: [
                   Icon(Icons.dns_rounded, size: 48, color: theme.colorScheme.outline.withValues(alpha: 0.2)),
                   const SizedBox(height: 12),
                   Text("No servers added".tl, style: TextStyle(color: theme.colorScheme.outline)),
                   const SizedBox(height: 16),
                   BloretButton(
                     text: "Add Server".tl,
                     icon: Icons.add,
                     onPressed: _showAddServerDialog,
                   ),
                 ],
               ),
             ),
           )
        else
           ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _servers.length,
              itemBuilder: (context, index) {
                final server = _servers[index];
                final isSelected = _selectedServerIndices.contains(index);

                return TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: Duration(milliseconds: 300 + (index * 50).clamp(0, 300)),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, child) {
                    return Opacity(
                      opacity: value,
                      child: Transform.translate(
                        offset: Offset(0, 20 * (1 - value)),
                        child: child,
                      ),
                    );
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected 
                            ? theme.colorScheme.primary.withValues(alpha: 0.5) 
                            : theme.dividerColor.withValues(alpha: 0.05),
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          if (_isServerMultiSelectMode) {
                            setState(() {
                              if (isSelected) {
                                _selectedServerIndices.remove(index);
                              } else {
                                _selectedServerIndices.add(index);
                              }
                            });
                          }
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 300),
                                    switchInCurve: Curves.easeOutCubic,
                                    switchOutCurve: Curves.easeInCubic,
                                    transitionBuilder: (child, animation) => FadeTransition(
                                      opacity: animation,
                                      child: SizeTransition(
                                        sizeFactor: animation,
                                        axis: Axis.horizontal,
                                        alignment: .centerLeft,
                                        child: child,
                                      ),
                                    ),
                                    child: _isServerMultiSelectMode
                                        ? Padding(
                                            padding: const EdgeInsets.only(right: 12),
                                            child: Checkbox(
                                              value: isSelected,
                                              visualDensity: VisualDensity.compact,
                                              onChanged: (v) {
                                                setState(() {
                                                  if (v == true) {
                                                    _selectedServerIndices.add(index);
                                                  } else {
                                                    _selectedServerIndices.remove(index);
                                                  }
                                                });
                                              },
                                            ),
                                          )
                                        : const SizedBox.shrink(),
                                  ),
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.primary.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: server.iconBase64 != null 
                                       ? ClipRRect(
                                           borderRadius: BorderRadius.circular(8),
                                           child: Image.memory(
                                             base64Decode(server.iconBase64!.split(',').last),
                                             fit: BoxFit.cover,
                                           ),
                                         )
                                       : Icon(Icons.dns_rounded, color: theme.colorScheme.primary, size: 22),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    flex: 1,
                                    child: Column(
                                      mainAxisSize: .min,
                                      crossAxisAlignment: .start,
                                      children: [
                                        Text(
                                          server.name,
                                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                            server.ip,
                                            style: TextStyle(
                                                fontSize: 10,
                                                color: theme.colorScheme.outline.withValues(alpha: 0.5),
                                            )
                                        ),
                                      ],
                                    )
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: (server.motdParts != null && server.motdParts!.isNotEmpty) ?
                                      Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                        child: Center(
                                          child: RichText(
                                            textAlign: TextAlign.center,
                                            text: TextSpan(
                                              children: server.motdParts!.map((part) {
                                                return TextSpan(
                                                  text: part['text'],
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: (part['bold'] == true) ? FontWeight.bold : FontWeight.normal,
                                                    color: _parseMcColor(part['color'], theme),
                                                    fontFamily: 'monospace',
                                                    height: 1.4,
                                                  ),
                                                );
                                              }).toList(),
                                            ),
                                          ),
                                        ),
                                      ) : const SizedBox(height: 16),
                                  ),
                                  const SizedBox(width: 16),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (server.isOnline)
                                        Row(
                                          mainAxisSize: .min ,
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: (server.ping! < 100 ? Colors.green : (server.ping! < 250 ? Colors.orange : Colors.red)).withValues(alpha: 0.15),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              alignment: Alignment.center,
                                              child: Text(
                                                "${server.ping}ms",
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w900,
                                                  height: 1.0,
                                                  color: server.ping! < 100 ? Colors.green : (server.ping! < 250 ? Colors.orange : Colors.red),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              alignment: Alignment.center,
                                              child: Text(
                                                "${server.playersOnline ?? "--"}/${server.playersMax ?? "--"}",
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w900,
                                                  height: 1.0,
                                                ),
                                              ),
                                            )
                                          ],
                                        )
                                      else if (_isPingUpdating)
                                        const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2.5))
                                      else
                                        const Icon(Icons.signal_cellular_connected_no_internet_4_bar, size: 16, color: Colors.grey),

                                      AnimatedSwitcher(
                                          duration: const Duration(milliseconds: 300),
                                          switchInCurve: Curves.easeOutCubic,
                                          switchOutCurve: Curves.easeInCubic,
                                          transitionBuilder: (child, animation) => FadeTransition(
                                            opacity: animation,
                                            child: SizeTransition(
                                              sizeFactor: animation,
                                              axis: Axis.horizontal,
                                              alignment: .centerLeft,
                                              child: child,
                                            ),
                                          ),
                                          child: !_isServerMultiSelectMode ?
                                            Padding(
                                              padding: const EdgeInsets.only(left: 4),
                                              child: IconButton(
                                                icon: const Icon(Icons.delete_outline, size: 20, color: Colors.redAccent),
                                                onPressed: () => _deleteServers([index]),
                                                visualDensity: VisualDensity.compact,
                                              ),
                                            ) : const SizedBox.shrink(),
                                      )
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
           ),
      ],
    );
  }

  Widget _buildServerToolbar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          _toolbarBtn(
            icon: Icons.refresh_rounded,
            label: "Refresh".tl,
            onPressed: _refreshAllServers,
            isLoading: _isPingUpdating,
          ),
          const SizedBox(width: 8),
          _toolbarBtn(
            icon: Icons.add_rounded,
            label: "Add".tl,
            onPressed: _showAddServerDialog,
          ),
          const Spacer(),
          if (_isServerMultiSelectMode) ...[
            Text("${_selectedServerIndices.length} ${"Selected".tl}", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            _toolbarBtn(
              icon: Icons.delete_sweep_rounded,
              label: "Delete".tl,
              onPressed: _selectedServerIndices.isEmpty ? null : () => _deleteServers(_selectedServerIndices.toList()),
              color: Colors.redAccent,
            ),
            const SizedBox(width: 8),
            _toolbarBtn(
              icon: Icons.close_rounded,
              label: "Cancel".tl,
              onPressed: () => setState(() {
                _isServerMultiSelectMode = false;
                _selectedServerIndices.clear();
              }),
            ),
          ] else
            _toolbarBtn(
              icon: Icons.checklist_rounded,
              label: "Select".tl,
              onPressed: _servers.isEmpty ? null : () => setState(() => _isServerMultiSelectMode = true),
            ),
        ],
      ),
    );
  }

  Widget _toolbarBtn({required IconData icon, required String label, required VoidCallback? onPressed, bool isLoading = false, Color? color}) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: isLoading 
        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) 
        : Icon(icon, size: 18, color: color),
      label: Text(label, style: TextStyle(fontSize: 12, color: color)),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Future<void> _refreshAllServers() async {
    if (_isPingUpdating) return;
    setState(() => _isPingUpdating = true);
    
    // If list is empty, try to load from config (sidecar)
    if (_servers.isEmpty) {
      final String id = widget.item['id']!;
      final List<dynamic> saved = ConfigService.get("server_list_$id") ?? [];
      _servers = saved.map((e) => MinecraftServer(name: e['name'], ip: e['ip'])).toList();
    }

    final futures = _servers.map((s) => MinecraftServerService.pingServer(s, onConnected: () {
      if (mounted) setState(() {});
    })).toList();
    await Future.wait(futures);
    
    if (mounted) {
      setState(() => _isPingUpdating = false);
    }
  }

  void _showAddServerDialog() {
    final nameController = TextEditingController();
    final ipController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Add Server".tl),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: InputDecoration(labelText: "Server Name".tl, hintText: "My Server".tl),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ipController,
              decoration: InputDecoration(labelText: "Server Address".tl, hintText: "play.example.com"),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text("Cancel".tl)),
          TextButton(
            onPressed: () {
              if (ipController.text.trim().isEmpty) return;
              setState(() {
                final newServer = MinecraftServer(
                  name: nameController.text.trim().isEmpty ? ipController.text.trim() : nameController.text.trim(),
                  ip: ipController.text.trim(),
                );
                _servers.add(newServer);
                _saveServerList();
                MinecraftServerService.pingServer(newServer).then((_) => setState(() {}));
              });
              Navigator.pop(context);
            },
            child: Text("Add".tl),
          ),
        ],
      ),
    );
  }

  void _deleteServers(List<int> indices) {
    indices.sort((a, b) => b.compareTo(a));
    setState(() {
      for (var idx in indices) {
        _servers.removeAt(idx);
      }
      _selectedServerIndices.clear();
      _isServerMultiSelectMode = false;
      _saveServerList();
    });
  }

  void _saveServerList() {
    final String id = widget.item['id']!;
    final String dir = widget.item['directory']!;

    MinecraftServerService.saveToGame(dir, id, _servers);
  }

  Color _parseMcColor(String? colorStr, ThemeData theme) {
    if (colorStr == null) return theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7);
    if (colorStr.startsWith('#')) {
      try {
        return Color(int.parse(colorStr.replaceFirst('#', '0xFF')));
      } catch (_) {
        return theme.colorScheme.onSurfaceVariant;
      }
    }

    switch (colorStr.toLowerCase()) {
      case 'black': return Colors.black;
      case 'dark_blue': return const Color(0xFF0000AA);
      case 'dark_green': return const Color(0xFF00AA00);
      case 'dark_aqua': return const Color(0xFF00AAAA);
      case 'dark_red': return const Color(0xFFAA0000);
      case 'dark_purple': return const Color(0xFFAA00AA);
      case 'gold': return const Color(0xFFFFAA00);
      case 'gray': return const Color(0xFFAAAAAA);
      case 'dark_gray': return const Color(0xFF555555);
      case 'blue': return const Color(0xFF5555FF);
      case 'green': return const Color(0xFF55FF55);
      case 'aqua': return const Color(0xFF55FFFF);
      case 'red': return const Color(0xFFFF5555);
      case 'light_purple': return const Color(0xFFFF55FF);
      case 'yellow': return const Color(0xFFFFFF55);
      case 'white': return Colors.white;
    }
    return theme.colorScheme.onSurfaceVariant;
  }

  // --- Screenshots Tab Logic ---

  Future<void> _refreshScreenshots() async {
    if (_isScreenshotsLoading) return;
    setState(() => _isScreenshotsLoading = true);

    final id = widget.item['id']!;
    final directory = widget.item['directory']!;
    final folderPath = p.join(directory, "versions", id, "screenshots");
    final dir = Directory(folderPath);

    if (await dir.exists()) {
      final list = await dir.list().toList();
      _screenshotFiles = list
          .whereType<File>()
          .where((f) => [".png", ".jpg", ".jpeg"].contains(p.extension(f.path).toLowerCase()))
          .toList()
        ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    } else {
      _screenshotFiles = [];
    }

    if (mounted) {
      setState(() => _isScreenshotsLoading = false);
    }
  }

  Future<void> _deleteScreenshots(List<int> indices) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Delete Screenshots".tl),
        content: Text("Are you sure you want to delete %d selected screenshots?".tl.format(indices.length)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text("Cancel".tl)),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text("Delete".tl, style: const TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm == true) {
      indices.sort((a, b) => b.compareTo(a));
      for (var idx in indices) {
        try {
          await _screenshotFiles[idx].delete();
        } catch (_) {}
      }
      showSuccess("Deleted successfully".tl);
      _isScreenshotMultiSelectMode = false;
      _selectedScreenshotIndices.clear();
      _refreshScreenshots();
    }
  }

  Widget _buildScreenshotsView(ThemeData theme) {
    if (_screenshotFiles.isEmpty && !_isScreenshotsLoading) {
      _refreshScreenshots();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildScreenshotsToolbar(theme),
        const SizedBox(height: 20),
        if (_isScreenshotsLoading)
          const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()))
        else if (_screenshotFiles.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 60),
              child: Column(
                children: [
                  Icon(Icons.no_photography_outlined, size: 64, color: theme.colorScheme.outline.withValues(alpha: 0.2)),
                  const SizedBox(height: 16),
                  Text("No screenshots found".tl, style: TextStyle(color: theme.colorScheme.outline)),
                ],
              ),
            ),
          )
        else
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: List.generate(_screenshotFiles.length, (index) {
              final file = _screenshotFiles[index];
              final isSelected = _selectedScreenshotIndices.contains(index);

              return TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: Duration(milliseconds: 300 + (index * 30).clamp(0, 300)),
                curve: Curves.easeOutQuart,
                builder: (context, value, child) {
                  return Opacity(
                    opacity: value,
                    child: Transform.scale(
                      scale: 0.95 + (0.05 * value),
                      child: child,
                    ),
                  );
                },
                child: Container(
                  width: 200,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected 
                        ? theme.colorScheme.primary.withValues(alpha: 0.5) 
                        : theme.dividerColor.withValues(alpha: 0.05),
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      // Image Preview
                      Stack(
                        children: [
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () {
                                if (_isScreenshotMultiSelectMode) {
                                  setState(() {
                                    if (isSelected) _selectedScreenshotIndices.remove(index);
                                    else _selectedScreenshotIndices.add(index);
                                  });
                                } else {
                                  launchUrl(Uri.file(file.path));
                                }
                              },
                              child: AspectRatio(
                                aspectRatio: 16 / 10,
                                child: Image.file(
                                  file,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Center(child: Icon(Icons.broken_image, color: theme.colorScheme.outline)),
                                ),
                              ),
                            ),
                          ),
                          // Selection Animation
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: _isScreenshotMultiSelectMode
                                ? Positioned(
                                    top: 8,
                                    left: 8,
                                    child: Checkbox(
                                      value: isSelected,
                                      visualDensity: VisualDensity.compact,
                                      onChanged: (v) {
                                        setState(() {
                                          if (v == true) _selectedScreenshotIndices.add(index);
                                          else _selectedScreenshotIndices.remove(index);
                                        });
                                      },
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ),
                      // Actions
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _screenshotIconAction(
                              icon: Icons.open_in_new_rounded,
                              tooltip: "Open".tl,
                              onPressed: () => launchUrl(Uri.file(file.path)),
                            ),
                            _screenshotIconAction(
                              icon: Icons.copy_all_rounded,
                              tooltip: "Copy".tl,
                              onPressed: () async {
                                await Pasteboard.writeFiles([file.path]);
                                showSuccess("Image copied to clipboard".tl);
                              },
                            ),
                            _screenshotIconAction(
                              icon: Icons.delete_outline_rounded,
                              tooltip: "Delete".tl,
                              color: Colors.redAccent,
                              onPressed: () => _deleteScreenshots([index]),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
      ],
    );
  }

  Widget _buildScreenshotsToolbar(ThemeData theme) {
    final id = widget.item['id']!;
    final directory = widget.item['directory']!;
    final folderPath = p.join(directory, "versions", id, "screenshots");

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          _toolbarBtn(
            icon: Icons.folder_open_rounded,
            label: "Open Folder".tl,
            onPressed: () => launchUrl(Uri.directory(folderPath)),
          ),
          const SizedBox(width: 8),
          _toolbarBtn(
            icon: Icons.refresh_rounded,
            label: "Refresh".tl,
            onPressed: _refreshScreenshots,
            isLoading: _isScreenshotsLoading,
          ),
          const Spacer(),
          if (_isScreenshotMultiSelectMode) ...[
            Text("${_selectedScreenshotIndices.length} ${"Selected".tl}", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            _toolbarBtn(
              icon: Icons.delete_sweep_rounded,
              label: "Delete".tl,
              onPressed: _selectedScreenshotIndices.isEmpty ? null : () => _deleteScreenshots(_selectedScreenshotIndices.toList()),
              color: Colors.redAccent,
            ),
            const SizedBox(width: 8),
            _toolbarBtn(
              icon: Icons.close_rounded,
              label: "Cancel".tl,
              onPressed: () => setState(() {
                _isScreenshotMultiSelectMode = false;
                _selectedScreenshotIndices.clear();
              }),
            ),
          ] else
            _toolbarBtn(
              icon: Icons.checklist_rounded,
              label: "Select".tl,
              onPressed: _screenshotFiles.isEmpty ? null : () => setState(() => _isScreenshotMultiSelectMode = true),
            ),
        ],
      ),
    );
  }

  Widget _screenshotIconAction({required IconData icon, required String tooltip, required VoidCallback onPressed, Color? color}) {
    return IconButton(
      icon: Icon(icon, size: 18, color: color),
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
    );
  }
  Widget _buildSavesView(ThemeData theme) {
    final id = widget.item['id']!;
    final directory = widget.item['directory']!;
    final folderPath = p.join(directory, "versions", id, "saves");
    final dir = Directory(folderPath);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFolderAction(theme),
        const SizedBox(height: 16),
        TextField(
          controller: _saveSearchController,
          onChanged: (v) => setState(() => _saveSearchQuery = v.trim().toLowerCase()),
          decoration: InputDecoration(
            hintText: "Search worlds...".tl,
            prefixIcon: const Icon(Icons.search),
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          ),
        ),
        const SizedBox(height: 16),
        FutureBuilder<List<FileSystemEntity>>(
          future: dir.exists().then((exists) async {
            if (!exists) return <FileSystemEntity>[];
            final list = await dir.list().toList();
            return list.where((e) {
              if (e is! Directory) return false;
              final name = p.basename(e.path);
              if (name.startsWith(".")) return false;
              if (_saveSearchQuery.isNotEmpty) {
                return name.toLowerCase().contains(_saveSearchQuery);
              }
              return true;
            }).toList();
          }),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()));
            }
            final items = snapshot.data ?? [];
            if (items.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Column(
                    children: [
                      Icon(Icons.landscape_rounded, size: 48, color: theme.colorScheme.outline.withValues(alpha: 0.2)),
                      const SizedBox(height: 12),
                      Text("No worlds found".tl, style: TextStyle(color: theme.colorScheme.outline)),
                    ],
                  ),
                ),
              );
            }

            return ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index] as Directory;
                final name = p.basename(item.path);
                
                return FutureBuilder<bool>(
                  future: MinecraftServerService.isWorldLocked(item.path),
                  builder: (context, lockSnapshot) {
                    final isLocked = lockSnapshot.data ?? false;
                    final iconFile = File(p.join(item.path, "icon.png"));
                    
                    Widget leading = Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.landscape_rounded, color: theme.colorScheme.primary, size: 24),
                    );

                    if (iconFile.existsSync()) {
                      leading = ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(iconFile, width: 52, height: 52, fit: BoxFit.cover),
                      );
                    }

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Container(
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isLocked ? Colors.red.withValues(alpha: 0.3) : theme.dividerColor.withValues(alpha: 0.05),
                            width: isLocked ? 1.5 : 1,
                          ),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => SaveEditView(saveDir: item.path, isInitiallyLocked: isLocked),
                                ),
                              ).then((_) => setState(() {}));
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  leading,
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                                        const SizedBox(height: 4),
                                        if (isLocked)
                                          Text(
                                            "Locked by one Minecraft instance".tl,
                                            style: const TextStyle(fontSize: 11, color: Colors.redAccent, fontWeight: FontWeight.bold),
                                          )
                                        else
                                          Text(
                                            "Last played: ".tl + _getDirectoryLastModified(item),
                                            style: TextStyle(fontSize: 11, color: theme.colorScheme.outline),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    isLocked ? Icons.lock_outline : Icons.chevron_right, 
                                    color: isLocked ? Colors.redAccent : theme.colorScheme.outline.withValues(alpha: 0.5),
                                    size: 18,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }
                );
              },
            );
          },
        ),
      ],
    );
  }

  String _getDirectoryLastModified(Directory dir) {
    try {
      final stat = dir.statSync();
      return DateFormat('yyyy/MM/dd HH:mm').format(stat.modified);
    } catch (_) {
      return "Unknown".tl;
    }
  }


  Widget _buildFolderList(ThemeData theme, String subFolder, IconData genericIcon, {bool isImage = false, bool isSave = false, bool isServerFile = false}) {
    final id = widget.item['id']!;
    final directory = widget.item['directory']!;
    final folderPath = isServerFile 
        ? p.join(directory, "versions", id) 
        : p.join(directory, "versions", id, subFolder);
    final dir = Directory(folderPath);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFolderAction(theme),
        const SizedBox(height: 16),
        FutureBuilder<List<FileSystemEntity>>(
          future: dir.exists().then((exists) async {
            if (!exists) return <FileSystemEntity>[];
            final list = await dir.list().toList();
            if (isServerFile) {
               return list.where((e) => p.basename(e.path) == "servers.dat").toList();
            }
            return list.where((e) => !p.basename(e.path).startsWith(".")).toList();
          }),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()));
            }
            final items = snapshot.data ?? [];
            if (items.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Column(
                    children: [
                      Icon(genericIcon, size: 48, color: theme.colorScheme.outline.withValues(alpha: 0.2)),
                      const SizedBox(height: 12),
                      Text("No items found".tl, style: TextStyle(color: theme.colorScheme.outline)),
                    ],
                  ),
                ),
              );
            }

            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: items.length,
              separatorBuilder: (_, _) => Divider(height: 1, color: theme.dividerColor.withValues(alpha: 0.05)),
              itemBuilder: (context, index) {
                final item = items[index];
                final name = p.basename(item.path);
                final isFile = item is File;

                Widget leading = Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(genericIcon, color: theme.colorScheme.primary, size: 20),
                );

                if (isImage && isFile) {
                  leading = ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      item,
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => leading,
                    ),
                  );
                } else if (isSave && !isFile) {
                  final iconFile = File(p.join(item.path, "icon.png"));
                  if (iconFile.existsSync()) {
                    leading = ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        iconFile,
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                      ),
                    );
                  }
                }

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  leading: leading,
                  title: Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  subtitle: Text(
                    isFile ? _formatFileSize(item) : "Folder".tl,
                    style: TextStyle(fontSize: 11, color: theme.colorScheme.outline),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.folder_open_outlined, size: 18),
                        tooltip: "Show in explorer".tl,
                        onPressed: () => launchUrl(Uri.file(isFile ? p.dirname(item.path) : item.path)),
                      ),
                      if (isFile)
                        IconButton(
                          icon: const Icon(Icons.open_in_new, size: 18),
                          tooltip: "Open file".tl,
                          onPressed: () => launchUrl(Uri.file(item.path)),
                        ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }

  String _formatFileSize(File file) {
    try {
      final size = file.lengthSync();
      if (size < 1024) return "$size B";
      if (size < 1024 * 1024) return "${(size / 1024).toStringAsFixed(1)} KB";
      return "${(size / (1024 * 1024)).toStringAsFixed(1)} MB";
    } catch (_) {
      return "Unknown Size".tl;
    }
  }

  Widget _buildExport(ThemeData theme) {
    final id = widget.item['id']!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSettingsSection(theme, "Basic Information".tl, [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Modpack Name".tl, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      TextField(
                        onChanged: (v) => setState(() => _exportPackName = v),
                        controller: TextEditingController(text: _exportPackName)..selection = TextSelection.fromPosition(TextPosition(offset: _exportPackName.length)),
                        decoration: InputDecoration(
                          hintText: "Enter modpack name".tl,
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Version".tl, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      TextField(
                        onChanged: (v) => setState(() => _exportPackVersion = v),
                        controller: TextEditingController(text: _exportPackVersion)..selection = TextSelection.fromPosition(TextPosition(offset: _exportPackVersion.length)),
                        decoration: InputDecoration(
                          hintText: "1.0.0",
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ]),
        const SizedBox(height: 24),
        Text("Export Content List".tl, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.1)),
          ),
          child: Column(
            children: [
              _buildExportCheckboxRow(
                theme: theme,
                title: "Game Body".tl,
                subtitle: id,
                value: _exportCore,
                onChanged: (v) => setState(() => _exportCore = v!),
              ),
              _buildExportCheckboxRow(
                theme: theme,
                title: "Game Settings".tl,
                subtitle: "Keybinds, volume, video settings, etc.".tl,
                value: _exportSettings,
                onChanged: (v) => setState(() => _exportSettings = v!),
                isSubItem: true,
              ),
              const Divider(height: 1),
              _buildExportCheckboxRow(
                theme: theme,
                title: "Mods".tl,
                subtitle: "Mod files".tl,
                value: _exportMods,
                onChanged: (v) => setState(() => _exportMods = v!),
              ),
              _buildExportCheckboxRow(
                theme: theme,
                title: "Mod Settings".tl,
                subtitle: "Config files".tl,
                value: _exportModConfigs,
                onChanged: (v) => setState(() => _exportModConfigs = v!),
                isSubItem: true,
              ),
              const Divider(height: 1),
              _buildExportCheckboxRow(
                theme: theme,
                title: "Singleplayer Saves".tl,
                subtitle: "Worlds / Maps".tl,
                value: _exportSaves,
                onChanged: (v) => setState(() => _exportSaves = v!),
              ),
              _buildExportCheckboxRow(
                theme: theme,
                title: "Multiplayer Server List".tl,
                subtitle: "servers.dat",
                value: _exportServers,
                onChanged: (v) => setState(() => _exportServers = v!),
              ),
              _buildExportCheckboxRow(
                theme: theme,
                title: "Other Folders".tl,
                subtitle: "Folders not covered by options above".tl,
                value: _exportOthers,
                onChanged: (v) => setState(() => _exportOthers = v!),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          child: BloretButton(
            onPressed: () {
               showInfo("Exporting modpack...".tl);
               // TODO: Implement actual export logic
            },
            text: "Start Exporting".tl,
            icon: Icons.ios_share_rounded,
            height: 50,
          ),
        ),
        const SizedBox(height: 48),
      ],
    );
  }

  Widget _buildExportCheckboxRow({
    required ThemeData theme,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool?> onChanged,
    bool isSubItem = false,
  }) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: EdgeInsets.fromLTRB(isSubItem ? 48 : 16, 12, 16, 12),
        child: Row(
          children: [
            Checkbox(
              value: value,
              onChanged: onChanged,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontWeight: isSubItem ? FontWeight.normal : FontWeight.bold, fontSize: 14)),
                  Text(subtitle, style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModify(ThemeData theme) {
    final id = widget.item['id']!;
    final directory = widget.item['directory']!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Loader Management".tl,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.1)),
          ),
          child: Column(
            children: [
              _buildModifyActionRow(
                theme: theme,
                icon: Icons.auto_fix_high_rounded,
                title: "Repair Configuration".tl,
                subtitle: "Re-download version metadata and fix corrupted files".tl,
                buttonText: "Repair".tl,
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text("Repair Core".tl),
                      content: Text("This will re-verify all core files and repair missing or corrupted ones. Your mods and saves will NOT be affected. Continue?".tl),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: Text("Cancel".tl)),
                        TextButton(onPressed: () => Navigator.pop(context, true), child: Text("Repair".tl)),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    showInfo("Repairing %s...".tl.format(id));
                    await LaunchService.instance.downloadMissingFiles(directory, id);
                    showSuccess("Repair completed".tl);
                  }
                },
              ),
              const Divider(height: 1),
              _buildModifyActionRow(
                theme: theme,
                icon: Icons.published_with_changes_rounded,
                title: "Switch Loader".tl,
                subtitle: "Install or change mod loader (Fabric/Forge/etc.)".tl,
                buttonText: "Switch".tl,
                onPressed: () {
                  _showSwitchLoaderDialog(theme);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text(
          "Important Note".tl,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.orangeAccent),
        ),
        const SizedBox(height: 8),
        Text(
          "Switching loaders will change the core's entry point. Ensure your mods are compatible with the new loader. Version downgrading is not supported here.".tl,
          style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _buildModifyActionRow({
    required ThemeData theme,
    required IconData icon,
    required String title,
    required String subtitle,
    required String buttonText,
    required VoidCallback onPressed,
  }) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: theme.colorScheme.primary, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                Text(subtitle, style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          BloretButton(
            onPressed: onPressed,
            text: buttonText,
            height: 36,
          ),
        ],
      ),
    );
  }

  void _showSwitchLoaderDialog(ThemeData theme) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.8,
        maxChildSize: 0.9,
        minChildSize: 0.5,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text("Switch Loader for %s".tl.format(widget.item['id']), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: VersionLoaderSelector(
                  mcVersion: _getMcVersionOnly(widget.item['id']!),
                  targetDirectory: widget.item['directory']!,
                  customVersionId: widget.item['id']!,
                  onCompleted: () {
                    Navigator.pop(context);
                    _loadMetadata();
                    showSuccess("Loader switched successfully".tl);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getMcVersionOnly(String id) {
    final match = RegExp(r'^\d+\.\d+(\.\d+)?').firstMatch(id);
    return match?.group(0) ?? id;
  }

  Widget _buildSettings(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSettingsSection(theme, "Launch Options".tl, [
          _buildConfigRow(
            theme: theme,
            icon: Icons.title_rounded,
            title: "Game Window Title".tl,
            subtitle: "Customize the title of the game window".tl,
            child: SizedBox(
              width: 200,
              child: TextField(
                onChanged: (v) => _saveConfig('custom_window_title', v),
                controller: TextEditingController(text: _customWindowTitle)..selection = TextSelection.fromPosition(TextPosition(offset: _customWindowTitle.length)),
                decoration: InputDecoration(
                  hintText: "Follow Global Settings".tl,
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                ),
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
          _buildConfigRow(
            theme: theme,
            icon: Icons.info_outline_rounded,
            title: "Custom Information".tl,
            subtitle: "Extra info to show in launcher/RPC".tl,
            child: SizedBox(
              width: 200,
              child: TextField(
                onChanged: (v) => _saveConfig('custom_info', v),
                controller: TextEditingController(text: _customInfo)..selection = TextSelection.fromPosition(TextPosition(offset: _customInfo.length)),
                decoration: InputDecoration(
                  hintText: "Follow Global Settings".tl,
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                ),
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
          _buildConfigRow(
            theme: theme,
            icon: Icons.computer_rounded,
            title: "Game Java".tl,
            subtitle: "Specify Java runtime for this instance".tl,
            child: Win11Dropdown(
              width: 200,
              initialValue: _javaSelection,
              items: [
                Win11DropdownItem(label: "Follow Global".tl, value: "Global"),
                ...JavaConfig.versionList.map((v) => Win11DropdownItem(label: "Java $v", value: v)),
              ],
              onChanged: (v) => _saveConfig('java_selection', v),
            ),
          ),
        ]),

        const SizedBox(height: 20),

        _buildSettingsSection(theme, "Memory Allocation".tl, [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _buildMemoryRadio("Global", "Follow Global".tl),
                    _buildMemoryRadio("Auto", "Auto Config".tl),
                    _buildMemoryRadio("Custom", "Custom".tl),
                  ],
                ),
                if (_memoryMode == "Custom") ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: GoogleSquigglySlider(
                          value: _customMemory,
                          max: _totalRamGb * 1024,
                          hasThumb: true,
                          onChanged: (v) {
                            setState(() => _customMemory = v);
                            _saveConfig('custom_memory', v.toInt());
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        "${(_customMemory / 1024).toStringAsFixed(1)} GiB",
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _AnimatedMemoryText(label: "Used RAM: ".tl, value: _usedRamGb, total: _totalRamGb),
                    Text(
                      "${"Allocated: ".tl}${(_customMemory / 1024).toStringAsFixed(1)} GiB",
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                TweenAnimationBuilder<double>(
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.easeOutCubic,
                  tween: Tween<double>(begin: 0, end: _usedRamGb / _totalRamGb),
                  builder: (context, value, child) {
                    return LinearProgressIndicator(
                      value: value,
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(3),
                      backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    );
                  },
                ),
              ],
            ),
          ),
        ]),

        const SizedBox(height: 20),

        _buildSettingsSection(theme, "Server Settings".tl, [
          _buildConfigRow(
            theme: theme,
            icon: Icons.security_rounded,
            title: "Restriction Mode".tl,
            subtitle: "Auth method restriction".tl,
            child: Win11Dropdown(
              width: 200,
              initialValue: _restrictionMode,
              items: [
                Win11DropdownItem(label: "No Restriction".tl, value: "None"),
                Win11DropdownItem(label: "Microsoft Only".tl, value: "MSA"),
              ],
              onChanged: (v) => _saveConfig('restriction_mode', v),
            ),
          ),
          _buildConfigRow(
            theme: theme,
            icon: Icons.dns_rounded,
            title: "Auto-Join Server".tl,
            subtitle: "Address to join on launch".tl,
            child: SizedBox(
              width: 200,
              child: TextField(
                onChanged: (v) => _saveConfig('auto_join_server', v),
                controller: TextEditingController(text: _autoJoinServer)..selection = TextSelection.fromPosition(TextPosition(offset: _autoJoinServer.length)),
                decoration: InputDecoration(
                  hintText: "Follow Global Settings".tl,
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                ),
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
        ]),

        const SizedBox(height: 20),

        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.1)),
          ),
          child: Theme(
            data: theme.copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              leading: Icon(Icons.settings_suggest_rounded, color: theme.colorScheme.primary),
              title: Text("Advanced Launch Options".tl, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              children: [
                _buildConfigRow(
                  theme: theme,
                  icon: Icons.auto_graph_rounded,
                  title: "Renderer".tl,
                  subtitle: "Graphics rendering engine".tl,
                  child: Win11Dropdown(
                    width: 200,
                    initialValue: _renderer,
                    items: [
                      Win11DropdownItem(label: "Follow Global".tl, value: "Global"),
                      Win11DropdownItem(label: "OpenGL (Legacy Fix)".tl, value: "OpenGL"),
                      Win11DropdownItem(label: "DirectX (Legacy Fix)".tl, value: "DirectX"),
                    ],
                    onChanged: (v) => _saveConfig('renderer', v),
                  ),
                ),
                _buildAdvancedTextRow(theme, "JVM Args Header".tl, "jvm_args_header", "Follow Global Settings".tl, true),
                _buildAdvancedTextRow(theme, "Game Args Tail".tl, "game_args_tail", "Follow Global Settings".tl, false),
                _buildAdvancedTextRow(theme, "Classpath Header".tl, "classpath_header", "", false),
                _buildAdvancedTextRow(theme, "Pre-Launch Command".tl, "pre_launch_command", "", false),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildMemoryRadio(String value, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        RadioGroup(
          groupValue: _memoryMode,
          onChanged: (v) => setState(() => _memoryMode = v!),
          child: Radio<String>(
            value: value,
          ),
        ),
        Text(label, style: const TextStyle(fontSize: 12)),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildAdvancedTextRow(
    ThemeData theme,
    String title,
    String key,
    String hint,
    bool multiLine,
  ) {
    String value = "";
    if (key == "jvm_args_header") {
      value = _jvmArgsHeader;
    } else if (key == "game_args_tail") {
      value = _gameArgsTail;
    }
    else if (key == "classpath_header") {
      value = _classpathHeader;
    }
    else if (key == "pre_launch_command") {
      value = _preLaunchCommand;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          TextField(
            maxLines: multiLine ? 3 : 1,
            onChanged: (v) => _saveConfig(key, v),
            controller: TextEditingController(text: value)..selection = TextSelection.fromPosition(TextPosition(offset: value.length)),
            decoration: InputDecoration(
              hintText: hint,
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
            ),
            style: const TextStyle(fontSize: 11, fontFamily: "Consolas"),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsSection(
    ThemeData theme,
    String title,
    List<Widget> children,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
        ),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.1)),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildOverview(ThemeData theme) {
    final id = widget.item['id']!;
    final uniqueId = widget.item['unique_id'] ?? id;
    final directory = widget.item['directory']!;

    String? extractVersion(String? input) {
      if (input == null) return null;
      final match = RegExp(r'\d+\.\d+(\.\d+)?').firstMatch(input);
      return match?.group(0);
    }

    String mcVersion =
        _mrpackMeta?['minecraft'] ??
        extractVersion(_versionData?['inheritsFrom']) ??
        extractVersion(_versionData?['id']) ??
        _versionData?['assets']?.toString() ??
        "Unknown".tl;

    String loaderName = _mrpackMeta?['loader'] != null 
        ? _mrpackMeta!['loader'].toString().capitalize
        : "Vanilla".tl;
    String loaderVersion = _mrpackMeta?['loader_version'] ?? "";
    final libs = _versionData?['libraries'] as List? ?? [];

    if (loaderVersion.isEmpty) {
      for (var lib in libs) {
        final String name = lib['name']?.toString() ?? "";
        if (name.contains("fabric-loader")) {
          loaderName = "Fabric";
          loaderVersion = name.split(':').last;
          break;
        } else if (name.contains("net.minecraftforge:forge:")) {
          loaderName = "Forge";
          final fullVersion = name.split(':').last;
          loaderVersion = fullVersion.contains('-')
              ? fullVersion.split('-').last
              : fullVersion;
          break;
        } else if (name.contains("net.neoforged:neoforge:")) {
          loaderName = "NeoForge";
          loaderVersion = name.split(':').last;
          break;
        } else if (name.contains("org.quiltmc:quilt-loader")) {
          loaderName = "Quilt";
          loaderVersion = name.split(':').last;
          break;
        }
      }
    }

    final String lastPlayedStr = ConfigService.get('last_played_$id') ?? "Never".tl;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_mrpackMeta != null) ...[
          _buildModpackBanner(theme),
          const SizedBox(height: 16),
        ],
        Row(
          children: [
            Expanded(
              child: _buildInfoCard(
                theme,
                Icons.bolt_rounded,
                "Launch Count".tl,
                _launchCount.toString(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildInfoCard(
                theme,
                Icons.timer_outlined,
                "Play Time".tl,
                _stats != null && _stats!['total'] != null
                    ? StatsService.instance.formatPlayTime(_stats!['total'] as int)
                    : "0s",
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildInfoCard(
                theme,
                Icons.history_rounded,
                "Last Played".tl,
                lastPlayedStr,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildInfoCard(theme, CupertinoIcons.cube, "Minecraft", mcVersion),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildInfoCard(
                theme,
                Icons.auto_awesome_outlined,
                "Mod Loader".tl,
                loaderVersion.isNotEmpty
                    ? "$loaderName $loaderVersion"
                    : loaderName,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        Text(
          "Personalization".tl,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildConfigRow(
                theme: theme,
                icon: Icons.image_outlined,
                title: "Icon".tl,
                subtitle: "Instance display icon".tl,
                child: Win11Dropdown(
                  width: 140,
                  initialValue: _selectedIcon,
                  items: [
                    const Win11DropdownItem(label: "Auto", value: "Auto"),
                    const Win11DropdownItem(
                      label: "Bloret Dark",
                      value: "bloret_dark",
                    ),
                    const Win11DropdownItem(
                      label: "Bloret Light",
                      value: "bloret_light",
                    ),
                    const Win11DropdownItem(label: "Bloriko", value: "bloriko"),
                    const Win11DropdownItem(label: "Fabric", value: "fabric"),
                    const Win11DropdownItem(label: "Forge", value: "forge"),
                    const Win11DropdownItem(
                      label: "NeoForge",
                      value: "neoforge",
                    ),
                    const Win11DropdownItem(label: "Java", value: "java"),
                    const Win11DropdownItem(
                      label: "Minecraft BE",
                      value: "mc_be",
                    ),
                    const Win11DropdownItem(label: "QQ", value: "qq"),
                    const Win11DropdownItem(
                      label: "Resource Editor",
                      value: "resource_editor",
                    ),
                    const Win11DropdownItem(
                      label: "Screen Cap",
                      value: "screen_cap",
                    ),
                    const Win11DropdownItem(label: "Shizuku", value: "shizuku"),
                    const Win11DropdownItem(label: "External", value: "ext"),
                  ],
                  onChanged: (v) {
                    _saveConfig('instance_icon', v);
                  },
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildConfigRow(
                theme: theme,
                icon: Icons.category_outlined,
                title: "Category".tl,
                subtitle: "Organize your instances".tl,
                child: Win11Dropdown(
                  width: 140,
                  initialValue: _selectedCategory,
                  items: [
                    Win11DropdownItem(label: "Standard".tl, value: "Standard"),
                    Win11DropdownItem(label: "Moddable".tl, value: "Moddable"),
                    Win11DropdownItem(
                      label: "Bloret Exclusive".tl,
                      value: "Exclusive",
                    ),
                    Win11DropdownItem(
                      label: "Rarely Used".tl,
                      value: "RarelyUsed",
                    ),
                    Win11DropdownItem(label: "Hidden".tl, value: "Hidden"),
                  ],
                  onChanged: (v) => _saveConfig('instance_category', v),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: BloretButton(
                onPressed: () => _showEditDialog(
                  "Modify Name".tl,
                  _customName ?? id,
                  (v) => _saveConfig('instance_name', v),
                ),
                text: "Modify Name".tl,
                icon: Icons.edit_outlined,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: BloretButton(
                onPressed: () => _showEditDialog(
                  "Modify Description".tl,
                  _customDescription ?? "",
                  (v) => _saveConfig('instance_desc', v),
                ),
                text: "Modify Description".tl,
                icon: Icons.description_outlined,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: BloretButton(
                onPressed: () {
                  setState(() {
                    _isFavorite = !_isFavorite;
                    ConfigService.set('favorite_$uniqueId', _isFavorite);
                  });
                  final coreState = context
                      .findAncestorStateOfType<_CoresPageState>();
                  coreState?.refreshLaunchItems();
                },
                text: _isFavorite ? "In Favorites".tl : "Add to Favorites".tl,
                icon: _isFavorite ? Icons.star : Icons.star_border,
                color: _isFavorite ? theme.colorScheme.primaryContainer : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        Text(
          "Shortcuts".tl,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildShortcutButton(
                theme,
                Icons.folder_open,
                "Instance Folder".tl,
                p.join(directory, "versions", id),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildShortcutButton(
                theme,
                Icons.save_outlined,
                "Saves".tl,
                p.join(directory, "versions", id, "saves"),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildShortcutButton(
                theme,
                Icons.extension_outlined,
                "Mods".tl,
                p.join(directory, "versions", id, "mods"),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        Text(
          "Advanced Management".tl,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            BloretButton(
              onPressed: _exportLaunchScript,
              text: "Export Script".tl,
              icon: Icons.terminal,
            ),
            BloretButton(
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text("Complete Files".tl),
                    content: Text(
                      "This will check and download missing game files. Continue?"
                          .tl,
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
                  showInfo("Downloading missing files...".tl);
                  LaunchService.instance.downloadMissingFiles(directory, id).then((_) {
                    showSuccess("Download complete".tl);
                  });
                }
              },
              text: "Complete Files".tl,
              icon: Icons.build_circle_outlined,
            ),
            BloretButton(
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text("Reset Instance".tl),
                    content: Text(
                      "This will reset instance settings to default. Continue?"
                          .tl,
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text("Cancel".tl),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: Text("Reset".tl),
                      ),
                    ],
                  ),
                );
                if (confirm == true) _resetInstance();
              },
              text: "Reset".tl,
              icon: Icons.restart_alt,
            ),
          ],
        ),
        const SizedBox(height: 12),
        BloretButton(
          onPressed: () async {
            final confirm = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: Text(
                  "Delete Instance".tl,
                  style: const TextStyle(color: Colors.red),
                ),
                content: Text(
                  "Are you sure you want to PERMANENTLY delete this instance? This cannot be undone."
                      .tl,
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text("Cancel".tl),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(
                      "Delete".tl,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
            );
            if (confirm == true) _deleteInstance();
          },
          text: "Delete Instance".tl,
          icon: Icons.delete_forever,
          color: Colors.red.withValues(alpha: 0.1),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Future<void> _exportLaunchScript() async {
    final id = widget.item['id']!;
    final directory = widget.item['directory']!;

    final script = await LaunchService.instance.generateLaunchScript(
      version: id,
      minecraftDir: directory,
    );

    final savePath = await FilePicker.platform.saveFile(
      fileName: 'launch_$id.bat',
      type: FileType.custom,
      allowedExtensions: ['bat'],
    );

    if (savePath != null) {
      await File(savePath).writeAsString(script);
      showSuccess("Launch script exported".tl);
    }
  }

  Future<void> _resetInstance() async {
    final id = widget.item['id']!;
    final uniqueId = widget.item['unique_id'] ?? id;
    ConfigService.set('instance_name_$uniqueId', null);
    ConfigService.set('instance_desc_$uniqueId', null);
    ConfigService.set('instance_icon_$uniqueId', "Auto");
    ConfigService.set('instance_category_$uniqueId', "Standard");
    _loadMetadata();
    showSuccess("Instance reset complete".tl);
  }

  Future<void> _deleteInstance() async {
    final id = widget.item['id']!;
    final directory = widget.item['directory']!;
    final versionDir = Directory(p.join(directory, "versions", id));

    try {
      if (await versionDir.exists()) {
        await versionDir.delete(recursive: true);
      }
      widget.onBack();
      if (!mounted) return;
      final coreState = context.findAncestorStateOfType<_CoresPageState>();
      coreState?.refreshLaunchItems();
      showSuccess("Instance deleted".tl);
    } catch (e) {
      showError("Failed to delete: $e".tl);
    }
  }

  void _showEditDialog(
    String title,
    String initialValue,
    Function(String) onSave,
  ) {
    final controller = TextEditingController(text: initialValue);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Cancel".tl),
          ),
          TextButton(
            onPressed: () {
              onSave(controller.text);
              Navigator.pop(context);
              _loadMetadata();
            },
            child: Text("Save".tl),
          ),
        ],
      ),
    );
  }

  Widget _buildModpackBanner(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.inventory_2_rounded, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _mrpackMeta?['pack_name'] ?? "Modpack",
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Text(
                  "${"Version: ".tl}${_mrpackMeta?['pack_version'] ?? "N/A"}",
                  style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (_mrpackMeta?['imported_at'] != null)
            Text(
              "${"Imported: ".tl}${DateTime.fromMillisecondsSinceEpoch((_mrpackMeta!['imported_at'] as int) * 1000).toString().split(' ').first}",
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(
    ThemeData theme,
    IconData icon,
    String label,
    String value,
  ) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.1)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon, color: theme.colorScheme.primary, size: 24),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    color: theme.colorScheme.outline,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShortcutButton(
    ThemeData theme,
    IconData icon,
    String label,
    String path,
  ) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.1)),
      ),
      child: InkWell(
        onTap: () async {
          final dir = Directory(path);
          if (!await dir.exists()) {
            await dir.create(recursive: true);
          }
          launchUrl(Uri.directory(path));
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          child: Column(
            children: [
              Icon(icon, size: 28, color: theme.colorScheme.primary),
              const SizedBox(height: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFolderAction(ThemeData theme) {
    final id = widget.item['id']!;
    final directory = widget.item['directory']!;
    final String tabName = _tabs[_activeTabIndex].$2;

    String folderName = "";
    if (_activeTabIndex == 5) folderName = "saves";
    if (_activeTabIndex == 6) folderName = "screenshots";
    if (_activeTabIndex == 7) folderName = "mods";
    if (_activeTabIndex == 8) folderName = "resourcepacks";
    if (_activeTabIndex == 9) folderName = "shaderpacks";
    if (_activeTabIndex == 10) folderName = "schematics";
    if (_activeTabIndex == 11) {
      folderName = "servers";
    }

    final folderPath = p.join(directory, "versions", id, folderName);

    return _buildConfigRow(
      theme: theme,
      icon: Icons.folder_open_rounded,
      title: "Open %s Folder".tl.format(tabName),
      subtitle: folderPath,
      child: IconButton(
        icon: const Icon(Icons.open_in_new),
        onPressed: () async {
          final dir = Directory(folderPath);
          if (!await dir.exists()) {
            await dir.create(recursive: true);
          }
          launchUrl(Uri.directory(folderPath));
        },
      ),
    );
  }

  Widget _buildConfigRow({
    required ThemeData theme,
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 4),
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: theme.colorScheme.surfaceContainerLow,
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
            ),
            child: Icon(icon, color: theme.colorScheme.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 10,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          child,
        ],
      ),
    );
  }
}
class SaveEditView extends StatefulWidget {
  final String saveDir;
  final bool isInitiallyLocked;
  const SaveEditView({super.key, required this.saveDir, this.isInitiallyLocked = false});

  @override
  State<SaveEditView> createState() => _SaveEditViewState();
}

class _SaveEditViewState extends State<SaveEditView> {
  bool _isLoading = true;
  bool _isLocked = false;
  Map<String, dynamic>? _worldData;
  
  bool _allowCheats = false;
  String _difficulty = "Normal";
  bool _lockDifficulty = false;
  final TextEditingController _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _isLocked = widget.isInitiallyLocked;
    _loadWorldData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadWorldData() async {
    final lock = await MinecraftServerService.isWorldLocked(widget.saveDir);
    final data = await MinecraftServerService.loadLevelDat(widget.saveDir);
    if (mounted) {
      setState(() {
        _isLocked = lock;
        _worldData = data;
        _isLoading = false;
        if (data != null) {
          _allowCheats = (data['allowCommands'] == 1 || data['allowCommands'] == true);
          _difficulty = _mapDifficulty(data['Difficulty'] ?? 2);
          _lockDifficulty = (data['DifficultyLocked'] == 1 || data['DifficultyLocked'] == true);
          _nameController.text = data['LevelName'] ?? p.basename(widget.saveDir);
        }
      });
    }
  }

  String _mapDifficulty(dynamic d) {
    int val = 2;
    if (d is int) {
      val = d;
    } else {
      val = int.tryParse(d.toString()) ?? 2;
    }
    
    switch (val) {
      case 0: return "Peaceful";
      case 1: return "Easy";
      case 3: return "Hard";
      default: return "Normal";
    }
  }

  String _mapGameMode(dynamic m) {
    int val = 0;
    if (m is int) {
      val = m;
    } else {
      val = int.tryParse(m.toString()) ?? 0;
    }

    switch (val) {
      case 1: return "Creative Mode".tl;
      case 2: return "Adventure Mode".tl;
      case 3: return "Spectator Mode".tl;
      default: return "Survival Mode".tl;
    }
  }

  String _formatPlayTime(dynamic time) {
    if (time == null) return "Unknown".tl;
    int ticks = 0;
    if (time is int) {
      ticks = time;
    } else if (time is double) {
      ticks = time.toInt();
    } else {
      ticks = int.tryParse(time.toString()) ?? 0;
    }
    
    if (ticks <= 0) return "Unknown".tl;

    int seconds = ticks ~/ 20;
    int minutes = seconds ~/ 60;
    int hours = minutes ~/ 60;
    
    if (hours > 0) {
      return "%d h, %d min".tl.format([hours, minutes % 60]);
    }
    return "%d min, %d sec".tl.format([minutes, seconds % 60]);
  }

  dynamic _findDeepValue(Map<String, dynamic>? data, List<String> path) {
    if (data == null) return null;
    dynamic current = data;
    for (var key in path) {
      if (current is Map) {
        final realKey = current.keys.firstWhere(
          (k) => k.toLowerCase() == key.toLowerCase(), 
          orElse: () => ""
        );
        if (realKey.isNotEmpty) {
          current = current[realKey];
        } else {
          return null;
        }
      } else {
        return null;
      }
    }
    return current;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final worldName = _worldData?['LevelName'] ?? p.basename(widget.saveDir);
    
    final seed = _findDeepValue(_worldData, ['WorldGenSettings', 'seed']) ?? 
                 _findDeepValue(_worldData, ['WorldGenSettings', 'seed']) ??
                 _worldData?['RandomSeed'];
                 
    final lastPlayed = _worldData?['LastPlayed'];
    final playTime = _worldData?['Time'] ?? _worldData?['DayTime'];

    return Scaffold(
      appBar: AppBar(
        title: Text("Edit World: %s".tl.format(worldName)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (_isLocked)
            Container(
              margin: const EdgeInsets.only(bottom: 24),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      "This save is currently locked by one Minecraft instance. Saving is disabled to prevent data corruption.".tl,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          _buildSectionTitle(theme, "Save Details".tl),
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.1)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildDetailRow("Save Version".tl, _worldData?['Version']?['Name']?.toString() ?? "N/A"),
                  _buildDetailRow("Save Name".tl, worldName),
                  _buildDetailRow("Seed".tl, seed?.toString() ?? "Unknown".tl),
                  _buildDetailRow("Last Played".tl, lastPlayed != null 
                    ? DateFormat('yyyy/MM/dd HH:mm').format(DateTime.fromMillisecondsSinceEpoch(lastPlayed is int ? lastPlayed : (int.tryParse(lastPlayed.toString()) ?? 0))) 
                    : "Unknown".tl),
                  _buildDetailRow("Spawn Point (X/Y/Z)".tl, "${_worldData?['SpawnX'] ?? 0} / ${_worldData?['SpawnY'] ?? 0} / ${_worldData?['SpawnZ'] ?? 0}"),
                  _buildDetailRow("Game Mode".tl, _mapGameMode(_worldData?['GameType'])),
                  _buildDetailRow("Play Time".tl, _formatPlayTime(playTime)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
          _buildSectionTitle(theme, "Basic Settings".tl),
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.1)),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("World Name".tl, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _nameController,
                        decoration: InputDecoration(
                          hintText: "Enter world name".tl,
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: Text("Allow Cheats".tl, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  subtitle: Text("Enable or disable cheat commands".tl, style: const TextStyle(fontSize: 11)),
                  value: _allowCheats,
                  onChanged: (v) => setState(() => _allowCheats = v),
                ),
                const Divider(height: 1),
                ListTile(
                  title: Text("Game Difficulty".tl, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  subtitle: Text("Current: ".tl + _difficulty.tl, style: const TextStyle(fontSize: 11)),
                  trailing: DropdownButton<String>(
                    value: _difficulty,
                    underline: const SizedBox(),
                    items: ["Peaceful", "Easy", "Normal", "Hard"].map((d) => DropdownMenuItem(value: d, child: Text(d.tl))).toList(),
                    onChanged: (v) => setState(() => _difficulty = v!),
                  ),
                ),
                const Divider(height: 1),
                CheckboxListTile(
                  title: Text("Lock Difficulty".tl, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  subtitle: Text("Prevent difficulty from being changed in-game".tl, style: const TextStyle(fontSize: 11)),
                  value: _lockDifficulty,
                  onChanged: (v) => setState(() => _lockDifficulty = v!),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          _buildSectionTitle(theme, "Game Rules (GameRules)".tl),
          const SizedBox(height: 16),
          _buildGameRulesSection(theme),
          const SizedBox(height: 40),
          BloretButton(
            text: _isLocked ? "Save Disabled (Locked)".tl : "Save Changes".tl,
            icon: _isLocked ? Icons.lock_outline : Icons.save_rounded,
            onPressed: _isLocked ? null : _saveWorldChanges,
            height: 50,
          ),
        ],
      ),
    );
  }

  Widget _buildGameRulesSection(ThemeData theme) {
    if (_worldData == null || _worldData!['GameRules'] == null) return const SizedBox.shrink();
    final rules = _worldData!['GameRules'] as Map<String, dynamic>;

    final commonRules = [
      'keepInventory',
      'mobGriefing',
      'doDaylightCycle',
      'doWeatherCycle',
      'doFireTick',
      'doInsomnia',
    ];

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: commonRules.map((key) {
          if (!rules.containsKey(key)) return const SizedBox.shrink();
          final val = rules[key].toString();
          final bool isBool = val == "true" || val == "false";

          return Column(
            children: [
              if (isBool)
                SwitchListTile(
                  title: Text(key, style: const TextStyle(fontSize: 13, fontFamily: "monospace")),
                  value: val == "true",
                  onChanged: (v) {
                    setState(() {
                      rules[key] = v.toString();
                    });
                  },
                )
              else
                ListTile(
                  title: Text(key, style: const TextStyle(fontSize: 13, fontFamily: "monospace")),
                  trailing: Text(val),
                ),
              if (key != commonRules.last) const Divider(height: 1),
            ],
          );
        }).toList(),
      ),
    );
  }

  Future<void> _saveWorldChanges() async {
    if (_worldData == null) return;

    final isStillLocked = await MinecraftServerService.isWorldLocked(widget.saveDir);
    if (isStillLocked) {
      showError("Save failed: The world is locked by one Minecraft instance.".tl);
      setState(() => _isLocked = true);
      return;
    }

    showInfo("Saving world data...".tl);

    _worldData!['LevelName'] = _nameController.text.trim();
    _worldData!['allowCommands'] = _allowCheats ? 1 : 0;
    _worldData!['Difficulty'] = _unmapDifficulty(_difficulty);
    _worldData!['DifficultyLocked'] = _lockDifficulty ? 1 : 0;

    try {
      await MinecraftServerService.saveLevelDat(widget.saveDir, _worldData!);
      showSuccess("World data saved successfully".tl);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      showError("Failed to save: $e".tl);
    }
  }

  int _unmapDifficulty(String d) {
    switch (d) {
      case 'Peaceful': return 0;
      case 'Easy': return 1;
      case 'Hard': return 3;
      default: return 2;
    }
  }

  Widget _buildSectionTitle(ThemeData theme, String title) {
    return Text(
      title,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey)),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _AnimatedMemoryText extends StatelessWidget {
  final String label;
  final double value;
  final double total;

  const _AnimatedMemoryText({
    required this.label,
    required this.value,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 500),
      tween: Tween<double>(begin: 0, end: value),
      builder: (context, val, child) {
        return Text(
          "$label${val.toStringAsFixed(1)} GiB / ${total.toStringAsFixed(1)} GiB",
          style: const TextStyle(fontSize: 10, color: Colors.grey),
        );
      },
    );
  }
}
