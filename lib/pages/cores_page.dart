import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:bloret_launcher/widgets/google_widgets.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
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
import '../widgets/windows_widgets.dart';
import 'external_app_selector_view.dart';
import 'mods_page.dart';

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
    Future.delayed(const Duration(milliseconds: 100), () {
      refreshLaunchItems();
    });
  }

  @override
  void dispose() {
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
      final favA = (a['bl_favorite'] == 'true' || ConfigService.get('favorite_$idA') == true) ? 1 : 0;
      final favB = (b['bl_favorite'] == 'true' || ConfigService.get('favorite_$idB') == true) ? 1 : 0;
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

    // Grouping logic
    final Map<String, List<Map<String, String>>> groups = {};
    for (var item in launchItems) {
      final id = item['id']!;
      final type = item['type'] ?? "minecraft";

      String category = "Standard";
      if (type == "minecraft") {
        category = item['bl_instance_category'] ?? ConfigService.get('instance_category_$id') ?? "Standard";
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
    final type = item['type'] ?? "minecraft";
    final appId = item['appId'];

    String displayName = id;
    String displayDesc = item['directory']!;
    String category = "Standard";
    bool isFavorite = false;

    if (type == "minecraft") {
      displayName = item['bl_instance_name'] ?? ConfigService.get('instance_name_$id') ?? id;
      displayDesc =
          item['bl_instance_desc'] ?? ConfigService.get('instance_desc_$id') ?? item['directory']!;
      category = item['bl_instance_category'] ?? ConfigService.get('instance_category_$id') ?? "Standard";
      isFavorite = item['bl_favorite'] == 'true' || ConfigService.get('favorite_$id') == true;
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
                  _buildCoreIcon(theme, item),
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

  Widget _buildCoreIcon(
    ThemeData theme,
    Map<String, String> item, {
    double size = 48,
  }) {
    final id = item['id']!;
    final directory = item['directory']!;
    final type = item['type'] ?? "minecraft";

    final String selectedIcon =
        item['bl_instance_icon'] ?? ConfigService.get('instance_icon_$id') ?? "Auto";
    final String category =
        item['bl_instance_category'] ?? ConfigService.get('instance_category_$id') ?? "Standard";

    if (selectedIcon != "Auto") {
      return _buildAssetIcon(selectedIcon, size);
    }

    if (type == "minecraft") {
      final iconPath = p.join(directory, "versions", id, "icon.png");
      final iconFile = File(iconPath);
      if (iconFile.existsSync()) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(size * 0.2),
          child: Image.file(
            iconFile,
            fit: BoxFit.cover,
            width: size,
            height: size,
          ),
        );
      }
    } else if (type == "custom_app") {
      final icon = item['icon'];
      if (icon != null && icon.isNotEmpty && File(icon).existsSync()) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(size * 0.2),
          child: Image.file(
            File(icon),
            fit: BoxFit.cover,
            width: size,
            height: size,
          ),
        );
      }
    }

    final lowerId = id.toLowerCase();
    if (lowerId.contains("fabric")) return _buildAssetIcon("fabric", size);
    if (lowerId.contains("neoforge")) return _buildAssetIcon("neoforge", size);
    if (lowerId.contains("forge")) return _buildAssetIcon("forge", size);
    if (lowerId.contains("quilt")) {
      return _buildGenericIcon(Icons.grid_view, Colors.purple, size);
    }

    return _buildCategoryIcon(theme, category, size);
  }

  Widget _buildGenericIcon(
    IconData icon,
    Color color,
    double size, {
    Key? key,
  }) {
    return Container(
      key: key,
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(size * 0.2),
      ),
      child: Center(
        child: Icon(icon, color: color, size: size * 0.6),
      ),
    );
  }

  Widget _buildAssetIcon(String iconKey, double size) {
    String assetPath;
    switch (iconKey) {
      case "bloret_dark":
        assetPath = "assets/bloret_dark.png";
        break;
      case "bloret_light":
        assetPath = "assets/bloret_light.png";
        break;
      case "bloriko":
        assetPath = "assets/bloriko.png";
        break;
      default:
        assetPath = "assets/icons/$iconKey.png";
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.2),
        image: DecorationImage(image: AssetImage(assetPath), fit: BoxFit.cover),
      ),
    );
  }

  Widget _buildCategoryIcon(ThemeData theme, String category, double size) {
    Widget iconWidget;
    switch (category) {
      case "Exclusive":
        iconWidget = CustomPaint(
          size: Size(size * 0.7, size * 0.7),
          painter: BloretIcon(color: theme.colorScheme.primary),
        );
        break;
      case "Moddable":
        iconWidget = Icon(
          Icons.extension,
          color: theme.colorScheme.primary,
          size: size * 0.6,
        );
        break;
      case "RarelyUsed":
        iconWidget = Icon(
          Icons.archive_outlined,
          color: theme.colorScheme.primary,
          size: size * 0.6,
        );
        break;
      case "Hidden":
        iconWidget = Icon(
          Icons.visibility_off_outlined,
          color: theme.colorScheme.primary,
          size: size * 0.6,
        );
        break;
      default:
        iconWidget = Icon(
          Icons.apps,
          color: theme.colorScheme.primary,
          size: size * 0.6,
        );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(size * 0.2),
      ),
      child: Center(child: iconWidget),
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
  bool _defaultWindowTitle = false;
  String _windowTitleMode = "Global";
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

  double _totalRamGb = 16.0;
  double _usedRamGb = 8.0;
  Timer? _memoryTimer;

  @override
  void initState() {
    super.initState();
    _loadMetadata();
    _startMemoryMonitoring();
  }

  @override
  void dispose() {
    _memoryTimer?.cancel();
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
      final legacy = ConfigService.get('${key}_$id');
      if (legacy != null) {
        // Migrate immediately
        _saveConfig(key, legacy);
        return legacy as T;
      }
      return defaultValue;
    }

    _launchCount = _stats?['sessions'] ?? ConfigService.get('launch_count_$id') ?? 0;
    _isFavorite = getVal('favorite', false);

    _customName = getVal('instance_name', null);
    _customDescription = getVal('instance_desc', null);
    _selectedIcon = getVal('instance_icon', "Auto");
    _selectedCategory = getVal('instance_category', "Standard");

    _memoryMode = getVal('memory_mode', "Global");
    _customMemory = (getVal('custom_memory', 4096)).toDouble();
    _windowTitleMode = getVal('window_title_mode', "Global");
    _customWindowTitle = getVal('custom_window_title', "");
    _defaultWindowTitle = getVal('default_window_title', false);
    _customInfo = getVal('custom_info', "");
    _javaSelection = getVal('java_selection', "Global");
    _restrictionMode = getVal('restriction_mode', "None");
    _autoJoinServer = getVal('auto_join_server', "");
    _renderer = getVal('renderer', "Global");
    _jvmArgsHeader = getVal('jvm_args_header', "");
    _gameArgsTail = getVal('game_args_tail', "");
    _classpathHeader = getVal('classpath_header', "");
    _preLaunchCommand = getVal('pre_launch_command', "");

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
    if (key == 'window_title_mode') _windowTitleMode = value;
    if (key == 'custom_window_title') _customWindowTitle = value;
    if (key == 'default_window_title') _defaultWindowTitle = value;
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
            child: _buildDetailIcon(theme, widget.item, size: 80),
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

  Widget _buildDetailIcon(
    ThemeData theme,
    Map<String, String> item, {
    double size = 48,
  }) {
    final id = item['id']!;
    final directory = item['directory']!;
    final type = item['type'] ?? "minecraft";

    if (_selectedIcon != "Auto") {
      return _buildAssetIcon(
        _selectedIcon,
        size,
        key: ValueKey("custom_$_selectedIcon"),
      );
    }

    if (type == "minecraft") {
      final iconPath = p.join(directory, "versions", id, "icon.png");
      final iconFile = File(iconPath);
      if (iconFile.existsSync()) {
        return ClipRRect(
          key: ValueKey("local_$id"),
          borderRadius: BorderRadius.circular(12),
          child: Image.file(
            iconFile,
            fit: BoxFit.cover,
            width: size,
            height: size,
          ),
        );
      }
    }

    final libs = _versionData?['libraries'] as List? ?? [];
    if (libs.any((l) => l['name'].toString().contains("fabric-loader"))) {
      return _buildAssetIcon(
        "fabric",
        size,
        key: const ValueKey("loader_fabric"),
      );
    } else if (libs.any((l) => l['name'].toString().contains("neoforge"))) {
      return _buildAssetIcon(
        "neoforge",
        size,
        key: const ValueKey("loader_neoforge"),
      );
    } else if (libs.any((l) => l['name'].toString().contains("forge"))) {
      return _buildAssetIcon(
        "forge",
        size,
        key: const ValueKey("loader_forge"),
      );
    } else if (libs.any((l) => l['name'].toString().contains("quilt-loader"))) {
      return _buildGenericIcon(
        Icons.grid_view,
        Colors.purple,
        size,
        key: const ValueKey("loader_quilt"),
      );
    }

    return _buildCategoryIcon(
      theme,
      _selectedCategory,
      size,
      key: ValueKey("cat_$_selectedCategory"),
    );
  }

  Widget _buildAssetIcon(String iconKey, double size, {Key? key}) {
    String assetPath;
    switch (iconKey) {
      case "bloret_dark":
        assetPath = "assets/bloret_dark.png";
        break;
      case "bloret_light":
        assetPath = "assets/bloret_light.png";
        break;
      case "bloriko":
        assetPath = "assets/bloriko.png";
        break;
      default:
        assetPath = "assets/icons/$iconKey.png";
    }
    return Container(
      key: key,
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.2),
        image: DecorationImage(image: AssetImage(assetPath), fit: BoxFit.cover),
      ),
    );
  }

  Widget _buildCategoryIcon(
    ThemeData theme,
    String category,
    double size, {
    Key? key,
  }) {
    Widget iconWidget;
    switch (category) {
      case "Exclusive":
        iconWidget = CustomPaint(
          size: Size(size * 0.7, size * 0.7),
          painter: BloretIcon(color: theme.colorScheme.primary),
        );
        break;
      case "Moddable":
        iconWidget = Icon(
          Icons.extension,
          color: theme.colorScheme.primary,
          size: size * 0.6,
        );
        break;
      case "RarelyUsed":
        iconWidget = Icon(
          Icons.archive_outlined,
          color: theme.colorScheme.primary,
          size: size * 0.6,
        );
        break;
      case "Hidden":
        iconWidget = Icon(
          Icons.visibility_off_outlined,
          color: theme.colorScheme.primary,
          size: size * 0.6,
        );
        break;
      default:
        iconWidget = Icon(
          Icons.apps,
          color: theme.colorScheme.primary,
          size: size * 0.6,
        );
    }

    return Container(
      key: key,
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(size * 0.2),
      ),
      child: Center(child: iconWidget),
    );
  }

  Widget _buildGenericIcon(
    IconData icon,
    Color color,
    double size, {
    Key? key,
  }) {
    return Container(
      key: key,
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(size * 0.2),
      ),
      child: Center(
        child: Icon(icon, color: color, size: size * 0.6),
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
      default:
        return _buildFolderAction(theme);
    }
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
    if (key == "jvm_args_header") value = _jvmArgsHeader;
    else if (key == "game_args_tail") value = _gameArgsTail;
    else if (key == "classpath_header") value = _classpathHeader;
    else if (key == "pre_launch_command") value = _preLaunchCommand;

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
                    ConfigService.set('favorite_$id', _isFavorite);
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
    ConfigService.set('instance_name_$id', null);
    ConfigService.set('instance_desc_$id', null);
    ConfigService.set('instance_icon_$id', "Auto");
    ConfigService.set('instance_category_$id', "Standard");
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

class GoogleWavySlider extends StatefulWidget {
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  const GoogleWavySlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  State<GoogleWavySlider> createState() => _GoogleWavySliderState();
}

class _GoogleWavySliderState extends State<GoogleWavySlider>
    with SingleTickerProviderStateMixin {
  late AnimationController _waveController;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _waveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onPanUpdate: (details) {
        final box = context.findRenderObject() as RenderBox;
        final localPos = box.globalToLocal(details.globalPosition);
        final percent = (localPos.dx / box.size.width).clamp(0.0, 1.0);
        widget.onChanged(widget.min + (widget.max - widget.min) * percent);
      },
      child: AnimatedBuilder(
        animation: _waveController,
        builder: (context, child) {
          return CustomPaint(
            size: const Size(double.infinity, 32),
            painter: _WavySliderPainter(
              value: (widget.value - widget.min) / (widget.max - widget.min),
              phase: _waveController.value,
              color: theme.colorScheme.primary,
              trackColor: theme.colorScheme.surfaceContainerHighest,
            ),
          );
        },
      ),
    );
  }
}

class _WavySliderPainter extends CustomPainter {
  final double value;
  final double phase;
  final Color color;
  final Color trackColor;

  _WavySliderPainter({
    required this.value,
    required this.phase,
    required this.color,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final trackPaint = Paint()
      ..color = trackColor
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final centerY = size.height / 2;
    final width = size.width;
    final activeWidth = width * value;

    canvas.drawLine(
      Offset(activeWidth, centerY),
      Offset(width, centerY),
      trackPaint,
    );

    final path = Path();
    path.moveTo(0, centerY);

    const double waveHeight = 4.0;
    const double waveLength = 40.0;

    for (double i = 0; i <= activeWidth; i++) {
      final y =
          centerY +
          waveHeight *
              (1.0 - (activeWidth - i) / 50).clamp(0.0, 1.0) *
              math.sin((i / waveLength + phase * 2 * math.pi));
      path.lineTo(i, y);
    }
    canvas.drawPath(path, paint);

    final handlePaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(activeWidth, centerY), 8, handlePaint);
  }

  @override
  bool shouldRepaint(covariant _WavySliderPainter oldDelegate) => true;
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
