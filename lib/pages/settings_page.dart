import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bloret_launcher/core/ffi_proxy.dart';
import 'package:bloret_launcher/core/i18n.dart';
import 'package:bloret_launcher/core/java_config.dart';
import 'package:bloret_launcher/core/logger.dart';
import 'package:bloret_launcher/main.dart';
import 'package:bloret_launcher/services/config_service.dart';
import 'package:bloret_launcher/services/update_manager.dart';
import 'package:bloret_launcher/tools/isolate.dart';
import 'package:bloret_launcher/widgets/button.dart';
import 'package:bloret_launcher/widgets/google_widgets.dart';
import 'package:bloret_launcher/widgets/hoshivetw_icon.dart';
import 'package:bloret_launcher/widgets/log_viewer.dart';
import 'package:bloret_launcher/widgets/windows_widgets.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher_string.dart';

import '../core/android_bridge.dart';
import '../core/grammer_candy.dart';
import '../services/plugin_service.dart';
import '../models/plugin.dart';
import '../core/theme.dart';
import '../core/theme_manager.dart';
import '../services/bloriko.dart';
import 'fake_3d_editor_page.dart';

enum SettingCategory {
  minecraft,
  home,
  system,
  gamepad,
  notification,
  appearance,
  plugins,
  log,
  network,
  ai,
  bloriko,
  control,
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final PageController _pageController = PageController();
  int _currentPageIndex = 0;
  SettingCategory _selectedCategory = SettingCategory.appearance;

  bool _isCheckingUpdate = false;
  String _hotfixVersion = currentVersion;
  List<String> _minecraftDirs = [];
  List<String> _proxyList = [];
  List<Map<String, String>> _detectedJavaList = [];
  bool _isScanningJava = false;
  List<Win11DropdownItem> _remoteModelItems = [];
  bool _isFetchingAiModels = false;
  final Set<String> _expandedItems = {};
  final TextEditingController _proxyController = TextEditingController();
  String? _hoveredColorKey;

  @override
  void initState() {
    super.initState();
    _loadHotfixVersion();
    _minecraftDirs = List<String>.from(
      ConfigService.get('minecraft_dirs') ?? [],
    );
    _proxyList = List<String>.from(ConfigService.get('proxy_list') ?? []);

    Future.delayed(Duration.zero, () async {
      _detectedJavaList = await parseJavaCache(
        ConfigService.get('detected_java_list'),
      );
      _refreshJavaList();
    });
  }

  static Future<List<dynamic>> jsonDecodeIsolate(String data) async {
    return jsonDecode(data);
  }

  static Future<List<Map<String, String>>> parseJavaCache(
    dynamic cachedData,
  ) async {
    final cachedJava = ConfigService.get('detected_java_list');
    if (cachedJava == null) return [];
    try {
      final List list = cachedData is String
          ? await runIsolate(jsonDecodeIsolate, cachedData)
          : cachedData;
      return list.map((e) => Map<String, String>.from(e)).toList();
    } catch (_) {
      return [];
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _proxyController.dispose();
    super.dispose();
  }

  void _goBackToHub() {
    _pageController.animateToPage(
      0,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOutCubic,
    );
    setState(() => _currentPageIndex = 0);
  }

  void _navigateToCategory(SettingCategory category) async {
    setState(() {
      _selectedCategory = category;
      _currentPageIndex = 1;
    });
    await Future.delayed(const Duration(milliseconds: 50));
    if (category == SettingCategory.ai) _fetchRemoteAiModels();
    _pageController.animateToPage(
      1,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOutCubic,
    );
  }

  Future<void> _refreshJavaList() async {
    if (_isScanningJava) return;
    setState(() {
      _isScanningJava = true;
      _detectedJavaList = [];
    });

    try {
      await for (final java in JavaConfig.detectJava()) {
        if (!mounted) return;
        setState(() {
          if (!_detectedJavaList.any((e) => e['path'] == java['path'])) {
            _detectedJavaList.add(java);
          }
        });
      }
      if (mounted) {
        setState(() => _isScanningJava = false);
        await ConfigService.set(
          'detected_java_list',
          jsonEncode(_detectedJavaList),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _isScanningJava = false);
    }
  }

  Future<void> _loadHotfixVersion() async {
    final v = await UpdateManager.instance.getLocalVersion();
    if (mounted) setState(() => _hotfixVersion = v);
  }

  Future<void> _fetchRemoteAiModels() async {
    final provider = ConfigService.get('ai_provider') ?? 'bloret_passport';
    if (provider != 'google_ai_studio' && provider != 'custom_api') return;

    final key = provider == 'google_ai_studio'
        ? 'google_ai_key'
        : 'custom_ai_key';
    final apiKey = ConfigService.get(key);
    if (apiKey == null || apiKey.isEmpty) {
      setState(() {
        _remoteModelItems = [
          Win11DropdownItem(
            label: "Please configure API Key first".tl,
            value: "none",
          ),
        ];
      });
      return;
    }

    setState(() {
      _isFetchingAiModels = true;
      _remoteModelItems = [];
    });

    try {
      final response = await Bloriko.client.models.list();
      final List<Win11DropdownItem> items = [];

      for (var model in response.data) {
        if (provider == 'google_ai_studio' && !model.id.contains('gemini')) {
          continue;
        }

        String rawName = model.id.replaceAll('models/', '');
        String formattedName = rawName
            .split('-')
            .map((word) {
              if (word.isEmpty) return word;
              return word[0].toUpperCase() + word.substring(1);
            })
            .join(' ');

        items.add(Win11DropdownItem(label: formattedName, value: model.id));
      }

      if (mounted) {
        setState(() {
          _remoteModelItems = items;
          _isFetchingAiModels = false;
        });

        final currentModel = ConfigService.get('ai_model');
        if (items.isNotEmpty && !items.any((e) => e.value == currentModel)) {
          await ConfigService.set('ai_model', items.first.value);
          setState(() {});
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _remoteModelItems = [
            Win11DropdownItem(
              label: "Failed to fetch models".tl,
              value: "error",
            ),
          ];
          _isFetchingAiModels = false;
        });
      }
    }
  }

  final List<Map<String, dynamic>> _categories = [
    {
      "id": SettingCategory.minecraft,
      "title": "Minecraft & Java".tl,
      "desc": "Java, game directories and download sources".tl,
      "icon": CupertinoIcons.cube,
    },
    {
      "id": SettingCategory.home,
      "title": "Home".tl,
      "desc": "Account display, tray and multi-instance".tl,
      "icon": Icons.home,
    },
    {
      "id": SettingCategory.system,
      "title": "System".tl,
      "desc": "Close and restart program".tl,
      "icon": Icons.power_settings_new,
    },
    {
      "id": SettingCategory.gamepad,
      "title": "Virtual Gamepad".tl,
      "desc": "COMING SOON",
      "icon": Icons.videogame_asset,
    },
    {
      "id": SettingCategory.notification,
      "title": "Notifications".tl,
      "desc": "Manage system notifications".tl,
      "icon": Icons.notifications,
    },
    {
      "id": SettingCategory.appearance,
      "title": "Appearance".tl,
      "desc": "Language and Theme".tl,
      "icon": Icons.color_lens,
    },
    {
      "id": SettingCategory.plugins,
      "title": "Plugins".tl,
      "desc": "Manage launcher extensions".tl,
      "icon": Icons.extension,
    },
    {
      "id": SettingCategory.log,
      "title": "Logs".tl,
      "desc": "Open or clear log files".tl,
      "icon": Icons.list_alt,
    },
    {
      "id": SettingCategory.network,
      "title": "Network".tl,
      "desc": "HTTP / SOCKS5 Proxy".tl,
      "icon": Icons.language,
    },
    {
      "id": SettingCategory.ai,
      "title": "AI Providers".tl,
      "desc": "Default models and custom providers".tl,
      "icon": Icons.smart_toy,
    },
    {
      "id": SettingCategory.bloriko,
      "title": "Blora Agent".tl,
      "desc": "AI settings and message connector management".tl,
      "icon": Icons.chat_bubble_outline,
    },
    {
      "id": SettingCategory.control,
      "title": "App Control".tl,
      "desc": "Hot updates and advanced debugging".tl,
      "icon": Icons.build,
    },
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: PopScope(
        canPop: _currentPageIndex == 0,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          if (_currentPageIndex != 0) {
            _goBackToHub();
          }
        },
        child: PageView(
          controller: _pageController,
          physics: const NeverScrollableScrollPhysics(),
          children: [_buildHub(theme), _buildDetail(theme)],
        ),
      ),
    );
  }

  Widget _buildHub(ThemeData theme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double availableWidth = constraints.maxWidth - 48;
        int columns = (availableWidth / 300).floor().clamp(1, 4);
        final double spacing = columns > 1 ? 12.0 : 0.0;
        final double itemWidth =
            (availableWidth - (columns - 1) * spacing) / columns;

        return ListView(
          key: const ValueKey("hub"),
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              "Settings".tl,
              style: theme.textTheme.headlineLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            FluentCard(
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 28),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Current Version".tl,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text("$name Launcher"),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "0.0.1",
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (_hotfixVersion != "0.0.0")
                        Text(
                          "Hotfix $_hotfixVersion",
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.grey,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              "Select a category to manage related settings".tl,
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: spacing,
              runSpacing: 12,
              children: _categories.map((cat) {
                final bool isComingSoon = cat["desc"] == "COMING SOON";
                return SizedBox(
                  width: itemWidth,
                  child: InkWell(
                    onTap: isComingSoon
                        ? null
                        : () => _navigateToCategory(cat["id"]),
                    borderRadius: BorderRadius.circular(8),
                    splashColor: theme.colorScheme.primary.withValues(
                      alpha: 0.03,
                    ),
                    highlightColor: theme.colorScheme.primary.withValues(
                      alpha: 0.01,
                    ),
                    hoverColor: theme.colorScheme.onSurface.withValues(
                      alpha: 0.05,
                    ),
                    splashFactory: InkRipple.splashFactory,
                    child: Opacity(
                      opacity: isComingSoon ? 0.6 : 1.0,
                      child: FluentCard(
                        child: Row(
                          children: [
                            Icon(cat["icon"], size: 28),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    cat["title"],
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                  Text(
                                    cat["desc"],
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (!isComingSoon)
                              const Icon(
                                Icons.chevron_right,
                                size: 16,
                                color: Colors.grey,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDetail(ThemeData theme) {
    final cat = _categories.firstWhere(
      (element) => element["id"] == _selectedCategory,
    );
    final brightness = MediaQuery.platformBrightnessOf(context);
    return ListView(
      key: ValueKey("detail_${_selectedCategory.name}"),
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            IconButton(
              onPressed: _goBackToHub,
              icon: const Icon(Icons.arrow_back),
            ),
            const SizedBox(width: 8),
            Text(
              "${"Settings".tl} · ${cat["title"]}",
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (_selectedCategory == SettingCategory.appearance) ...[
          _buildSettingItem(
            "Language".tl,
            "Adjust language settings".tl,
            Icons.language,
            dropdown: Win11Dropdown(
              items: [
                Win11DropdownItem(label: "English (US)", value: "en_us"),
                Win11DropdownItem(label: "简体中文", value: "zh_cn"),
                Win11DropdownItem(label: "繁體中文", value: "zh_tw"),
                Win11DropdownItem(label: "范式中文", value: "zh_ac"),
                Win11DropdownItem(label: "日本語", value: "ja_jp"),
                Win11DropdownItem(label: "Русский", value: "ru_ru"),
              ],
              initialValue: ConfigService.getLanguage(),
              onChanged: (v) async {
                await ConfigService.setLanguage(v ?? "zh_cn");
              },
            ),
          ),
          _buildSettingItem(
            "Theme".tl,
            "Choose interface color mode".tl,
            switch (ConfigService.get("theme_mode") ?? "Auto") {
              "Light" => Icons.wb_sunny,
              "Dark" => Icons.dark_mode,
              _ => Icons.desktop_windows_rounded,
            },
            dropdown: Win11Dropdown(
              items: [
                Win11DropdownItem(label: "Auto".tl, value: "Auto"),
                Win11DropdownItem(label: "Light".tl, value: "Light"),
                Win11DropdownItem(label: "Dark".tl, value: "Dark"),
              ],
              initialValue: ConfigService.get("theme_mode") ?? "Auto",
              onChanged: (v) async {
                await ConfigService.set("theme_mode", v);
                ThemeManager.instance.updateTheme();
                setState(() {});
              },
            ),
          ),
          // if (Platform.isWindows)
          //   _buildSettingItem(
          //     "Acrylic Blur".tl,
          //     "Enable Windows 11 Acrylic blur effect".tl,
          //     Icons.blur_on,
          //     trailing: Switch(
          //       value: ConfigService.get("enable_acrylic") ?? false,
          //       onChanged: (v) async {
          //         await ConfigService.set("enable_acrylic", v);
          //         WinWindow.setAcrylic(v);
          //         setState(() {});
          //       },
          //     ),
          //   ),
          _buildSettingItem(
            "Theme Color".tl,
            "Select a seed color for the interface".tl,
            Icons.palette,
            itemKey: "theme_color",
            expandedChild: SizedBox(
              height: 48,
              child: Stack(
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      ...appThemeColors.entries.map((e) {
                        final bool isHovered = _hoveredColorKey == e.key;
                        return Tooltip(
                          message: e.key.tl,
                          child: MouseRegion(
                            onEnter: (_) =>
                                setState(() => _hoveredColorKey = e.key),
                            onExit: (_) =>
                                setState(() => _hoveredColorKey = null),
                            cursor: SystemMouseCursors.click,
                            child: GestureDetector(
                              onTap: () async {
                                await ConfigService.set(
                                  "theme_color_key",
                                  e.key,
                                );
                                await ConfigService.set(
                                  "theme_seed_color",
                                  null,
                                );
                                setState(() {});

                                Future.delayed(
                                  const Duration(milliseconds: 400),
                                  () {
                                    if (mounted) {
                                      ThemeManager.instance.updateTheme();
                                    }
                                  },
                                );
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: isHovered
                                      ? e.value.withValues(alpha: 0.8)
                                      : e.value,
                                  shape: BoxShape.circle,
                                  boxShadow: isHovered
                                      ? [
                                          BoxShadow(
                                            color: e.value.withValues(
                                              alpha: 0.4,
                                            ),
                                            blurRadius: 8,
                                            spreadRadius: 2,
                                          ),
                                        ]
                                      : null,
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                      Tooltip(
                        message: "Custom Color".tl,
                        child: MouseRegion(
                          onEnter: (_) =>
                              setState(() => _hoveredColorKey = "custom"),
                          onExit: (_) =>
                              setState(() => _hoveredColorKey = null),
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: () => _showColorPickerDialog(context),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Colors.red,
                                    Colors.yellow,
                                    Colors.green,
                                    Colors.blue,
                                  ],
                                ),
                                boxShadow: _hoveredColorKey == "custom"
                                    ? [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: 0.2,
                                          ),
                                          blurRadius: 8,
                                          spreadRadius: 2,
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Opacity(
                                opacity: 0.4,
                                child: GridView.count(
                                  crossAxisCount: 2,
                                  physics: const NeverScrollableScrollPhysics(),
                                  padding: const EdgeInsets.all(4),
                                  children: [
                                    Container(
                                      margin: const EdgeInsets.all(2),
                                      decoration: const BoxDecoration(
                                        color: Colors.white,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    Container(
                                      margin: const EdgeInsets.all(2),
                                      decoration: const BoxDecoration(
                                        color: Colors.white,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    Container(
                                      margin: const EdgeInsets.all(2),
                                      decoration: const BoxDecoration(
                                        color: Colors.white,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    Container(
                                      margin: const EdgeInsets.all(2),
                                      decoration: const BoxDecoration(
                                        color: Colors.white,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Builder(
                    builder: (context) {
                      final selectedKey =
                          ConfigService.get("theme_color_key") ??
                          "classic_blue";
                      final customColor = ConfigService.get("theme_seed_color");

                      int index;
                      bool isCustom = false;
                      if (customColor != null) {
                        index = appThemeColors.length;
                        isCustom = true;
                      } else {
                        index = appThemeColors.keys.toList().indexOf(
                          selectedKey,
                        );
                      }

                      if (index == -1) return const SizedBox.shrink();

                      return AnimatedPositioned(
                        duration: const Duration(milliseconds: 350),
                        curve: Curves.easeOutCubic,
                        left: index * (40 + 12).toDouble(),
                        top: 0,
                        child: IgnorePointer(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(
                                isCustom ? 8 : 20,
                              ),
                              border: Border.all(
                                color: Colors.white,
                                width: 2.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  blurRadius: 10,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.check,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          if (Platform.isAndroid)
            _buildSettingItem(
              "App Icon".tl,
              "Select app icon type".tl,
              Icons.app_registration,
              dropdown: Win11Dropdown(
                items: [
                  Win11DropdownItem(label: "Light".tl, value: "light"),
                  Win11DropdownItem(label: "Dark".tl, value: "dark"),
                  Win11DropdownItem(label: "System".tl, value: "system"),
                ],
                initialValue: ConfigService.get("icon_theme") ?? "system",
                onChanged: (v) async {
                  await ConfigService.set("icon_theme", v);
                  final systemDark = brightness == Brightness.dark;
                  final isNight = switch (v) {
                    "light" => false,
                    "dark" => true,
                    "system" => systemDark,
                    _ => systemDark,
                  };

                  await setNightIcon(isNight);
                },
              ),
            ),
        ],
        if (_selectedCategory == SettingCategory.minecraft) ...[
          _buildSettingItem(
            "Java Selection Mode".tl,
            (ConfigService.get("java_selection_mode") ?? "auto") == "auto"
                ? "Automatically match the best Java version based on your Minecraft version (e.g., Java 21 for 1.20.5+)"
                      .tl
                : "${"Fixed path mode".tl}: ${ConfigService.get("java_path") ?? "Not set".tl}",
            Icons.code,
            itemKey: "java_main",
            expandedChild: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(width: 5),
                    Win11Dropdown(
                      items: [
                        Win11DropdownItem(
                          label: "Auto Selection (Recommended)".tl,
                          value: "auto",
                        ),
                        Win11DropdownItem(
                          label: "Fixed Java".tl,
                          value: "fixed",
                        ),
                      ],
                      initialValue:
                          ConfigService.get("java_selection_mode") ?? "auto",
                      onChanged: (v) {
                        setState(() {
                          ConfigService.set("java_selection_mode", v);
                          if (v == "fixed") {
                            _expandedItems.add("java_list");
                          } else {
                            _expandedItems.remove("java_list");
                          }
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildSettingItem(
                  (ConfigService.get("java_selection_mode") ?? "auto") == "auto"
                      ? "Available Java Environments".tl
                      : "Select Java Path".tl,
                  "Click to view or change Java".tl,
                  Icons.manage_search,
                  itemKey: "java_list",
                  trailing: _isScanningJava
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : IconButton(
                          icon: const Icon(Icons.refresh, size: 18),
                          onPressed: _refreshJavaList,
                          visualDensity: VisualDensity.compact,
                        ),
                  expandedChild: Column(
                    children: [
                      if (_detectedJavaList.isEmpty && !_isScanningJava)
                        Text(
                          "No valid Java installation detected".tl,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.redAccent,
                          ),
                        )
                      else
                        ..._detectedJavaList.map((java) {
                          final bool isSelected =
                              ConfigService.get("java_path") == java['path'];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: InkWell(
                              onTap: () async {
                                await ConfigService.set(
                                  "java_path",
                                  java['path'],
                                );
                                await ConfigService.set(
                                  "java_version",
                                  java['version'],
                                );
                                setState(() {});
                              },
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? theme.colorScheme.primary.withValues(
                                          alpha: 0.1,
                                        )
                                      : theme
                                            .colorScheme
                                            .surfaceContainerHighest
                                            .withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(6),
                                  border: isSelected
                                      ? Border.all(
                                          color: theme.colorScheme.primary
                                              .withValues(alpha: 0.5),
                                        )
                                      : null,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.code,
                                      size: 16,
                                      color: isSelected
                                          ? theme.colorScheme.primary
                                          : null,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            java['detail'] ??
                                                "Java ${java['version']}",
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                              color: isSelected
                                                  ? theme.colorScheme.primary
                                                  : null,
                                            ),
                                          ),
                                          Text(
                                            java['path'] ?? "",
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey,
                                              fontFamily: 'monospace',
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (isSelected)
                                      Icon(
                                        Icons.check_circle,
                                        size: 16,
                                        color: theme.colorScheme.primary,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _buildSettingItem(
            "Minecraft Folder Locations".tl,
            "${"Manage game file storage paths".tl} (${_minecraftDirs.length})",
            Icons.folder,
            itemKey: "mc_dirs",
            expandedChild: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ..._minecraftDirs.asMap().entries.map((entry) {
                  int index = entry.key;
                  String path = entry.value;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: theme.dividerColor.withValues(alpha: 0.1),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.folder,
                            size: 20,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              path,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                fontFamily: 'monospace',
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            onPressed: () {
                              setState(() {
                                _minecraftDirs.removeAt(index);
                                ConfigService.set(
                                  "minecraft_dirs",
                                  _minecraftDirs,
                                );
                              });
                            },
                            icon: const Icon(
                              Icons.remove_circle_outline,
                              size: 20,
                              color: Colors.red,
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: BloretButton(
                    text: "Add Folder".tl,
                    onPressed: () async {
                      String? selectedDirectory = await FilePicker.platform
                          .getDirectoryPath();
                      if (selectedDirectory != null) {
                        setState(() {
                          if (!_minecraftDirs.contains(selectedDirectory)) {
                            _minecraftDirs.add(selectedDirectory);
                            ConfigService.set("minecraft_dirs", _minecraftDirs);
                          }
                        });
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          _buildSettingItem(
            "Download Source".tl,
            "Select download source".tl,
            Icons.cloud_download,
            dropdown: Win11Dropdown(
              items: [
                Win11DropdownItem(label: "Bloret", value: "gitcode"),
                Win11DropdownItem(label: "Mojang", value: "official"),
                Win11DropdownItem(label: "BMCLAPI", value: "bmclapi"),
              ],
              initialValue: ConfigService.get("download_source") ?? "gitcode",
              onChanged: (v) => ConfigService.set("download_source", v),
            ),
          ),
          _buildSettingItem(
            "Strongly Attached Process".tl,
            "Automatically terminate Minecraft when Blora Launcher is closed. (Recommended for portable use)"
                .tl,
            Icons.link_rounded,
            switchValue: ConfigService.get("minecraft_kill_on_exit") ?? false,
            onSwitchChanged: (v) async {
              await ConfigService.set("minecraft_kill_on_exit", v);
              setState(() {});
            },
          ),
        ],
        if (_selectedCategory == SettingCategory.home) ...[
          _buildSettingItem(
            "Show Account Info".tl,
            "Show account details on home page".tl,
            Icons.person,
            dropdown: Win11Dropdown(
              items: [
                Win11DropdownItem(label: "Compact".tl, value: "compact"),
                Win11DropdownItem(label: "Full".tl, value: "full"),
                Win11DropdownItem(label: "Hidden".tl, value: "hidden"),
              ],
              initialValue: ConfigService.get("home_account_mode") ?? "compact",
              onChanged: (v) => ConfigService.set("home_account_mode", v),
            ),
          ),
          _buildSettingItem(
            "Close Button Action".tl,
            "Minimize to tray or exit directly".tl,
            Icons.close,
            dropdown: Win11Dropdown(
              items: [
                Win11DropdownItem(label: "Minimize to Tray".tl, value: "hide"),
                Win11DropdownItem(label: "Exit Directly".tl, value: "exit"),
              ],
              initialValue: ConfigService.getExitBehavior() == "ask"
                  ? "exit"
                  : ConfigService.getExitBehavior(),
              onChanged: (v) {
                if (v != null) ConfigService.setExitBehavior(v);
              },
            ),
          ),
        ],
        if (_selectedCategory == SettingCategory.system) ...[
          _buildSettingItem(
            "${"3D Model Editor".tl} (WIP)",
            "Internal 3D scene preview and model editor".tl,
            Icons.view_in_ar_rounded,
            trailing: BloretButton(
              text: "Open Editor".tl,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const Fake3DEditorPage()),
                );
              },
            ),
          ),
          _buildSettingItem(
            "Close Program".tl,
            "Completely exit Blora Launcher".tl,
            Icons.power_settings_new,
            trailing: BloretButton(
              text: "Close".tl,
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text("Confirm Close".tl),
                    content: Text(
                      "Are you sure you want to completely exit Blora Launcher?"
                          .tl,
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text("Cancel".tl),
                      ),
                      TextButton(
                        onPressed: () => terminateProcess(),
                        child: Text("Exit".tl),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          if (!Platform.isAndroid)
            _buildSettingItem(
              "Restart Program".tl,
              "Restart app".tl,
              Icons.refresh,
              trailing: BloretButton(
                text: "Restart".tl,
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text("Confirm Restart".tl),
                      content: Text(
                        "Are you sure you want to restart Blora Launcher?".tl,
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text("Cancel".tl),
                        ),
                        TextButton(
                          onPressed: () async {
                            Navigator.pop(context);
                            if (Platform.isWindows) {
                              await Process.start("cmd", [
                                "/c",
                                "start",
                                "",
                                Platform.resolvedExecutable,
                              ]);
                            } else {
                              await Process.start("sh", [
                                "-c",
                                "${Platform.resolvedExecutable} &",
                              ]);
                            }
                            exit(0);
                          },
                          child: Text("Restart".tl),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
        if (_selectedCategory == SettingCategory.gamepad) ...[
          Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text("Feature not enabled yet".tl),
            ),
          ),
        ],
        if (_selectedCategory == SettingCategory.notification) ...[
          _buildSettingItem(
            "Enable System Notifications".tl,
            "Master Switch".tl,
            Icons.notifications_active,
            switchValue: true,
            onSwitchChanged: (v) {},
          ),
          _buildSettingItem(
            "Game Launch Completed".tl,
            "Notification after Minecraft successfully enters".tl,
            Icons.check_circle,
            switchValue: true,
            onSwitchChanged: (v) {},
          ),
          _buildSettingItem(
            "Update Reminders".tl,
            "Notification when there is a new patch".tl,
            Icons.update,
            switchValue: true,
            onSwitchChanged: (v) {},
          ),
          _buildSettingItem(
            "Test Notifications".tl,
            "Show test notifications".tl,
            Icons.notifications_active,
            trailing: BloretButton(
              text: "Show".tl,
              onPressed: () {
                WinSystem.showNotification("Test Notification".tl, "Test Message");
              },
            )
          ),
        ],
        if (_selectedCategory == SettingCategory.plugins) ...[
          _buildPluginList(),
        ],
        if (_selectedCategory == SettingCategory.log) ...[
          _buildSettingItem(
            "View Logs".tl,
            "View launcher runtime logs in real-time".tl,
            Icons.list,
            trailing: IconButton(
              icon: const Icon(Icons.arrow_forward),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const Scaffold(body: AdvancedLogViewer(canPop: true)),
                  ),
                );
              },
            ),
            hoshivetw: true,
          ),
          _buildSettingItem(
            "Log Folder Location".tl,
            (Platform.isWindows || Platform.isLinux)
                ? p.dirname(Platform.resolvedExecutable)
                : "App Data Directory".tl,
            Icons.folder,
            trailing: IconButton(
              icon: const Icon(Icons.open_in_new),
              onPressed: () async {
                final logPath = p.join(
                  p.dirname(Platform.resolvedExecutable),
                  'app_log.json',
                );

                await Process.run('explorer.exe', ['/select,$logPath']);
              },
            ),
          ),
          _buildSettingItem(
            "Clear Logs".tl,
            "Delete all local log records".tl,
            Icons.delete_sweep,
            trailing: BloretButton(
              text: "Clear".tl,
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text("Confirm Clear".tl),
                    content: Text(
                      "Are you sure you want to delete all local log records? This action is irreversible."
                          .tl,
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text("Cancel".tl),
                      ),
                      TextButton(
                        onPressed: () async {
                          Navigator.pop(context);
                          await logger.clearLogs();
                          if (context.mounted) {
                            showSuccess("Logs cleared".tl);
                          }
                        },
                        child: Text(
                          "Clear".tl,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
        if (_selectedCategory == SettingCategory.network) ...[
          _buildSettingItem(
            "Network Proxy".tl,
            ConfigService.get("proxy") == null ||
                    ConfigService.get("proxy").isEmpty
                ? "Proxy disabled".tl
                : "${"Current proxy".tl}: ${ConfigService.get("proxy")}",
            Icons.language,
            itemKey: "proxy",
            expandedChild: RadioGroup<String>(
              groupValue: ConfigService.get("proxy") ?? "",
              onChanged: (v) async {
                if (v != null) {
                  await ConfigService.set("proxy", v);
                  setState(() {});
                }
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RadioListTile<String>(
                    title: Text(
                      "Not configured".tl,
                      style: const TextStyle(fontSize: 14),
                    ),
                    value: "",
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                  ..._proxyList.asMap().entries.map((entry) {
                    int index = entry.key;
                    String proxy = entry.value;
                    return Row(
                      children: [
                        Expanded(
                          child: RadioListTile<String>(
                            title: Text(
                              proxy,
                              style: const TextStyle(
                                fontSize: 14,
                                fontFamily: 'monospace',
                              ),
                            ),
                            value: proxy,
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                          ),
                        ),
                        IconButton(
                          onPressed: () {
                            setState(() {
                              _proxyList.removeAt(index);
                              ConfigService.set("proxy_list", _proxyList);
                              if (ConfigService.get("proxy") == proxy) {
                                ConfigService.set("proxy", "");
                              }
                            });
                          },
                          icon: const Icon(
                            Icons.remove_circle_outline,
                            size: 20,
                            color: Colors.red,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    );
                  }),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: theme.dividerColor.withValues(alpha: 0.1),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.add_link,
                          size: 20,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _proxyController,
                            decoration: const InputDecoration(
                              hintText: "http://127.0.0.1:10808",
                              border: InputBorder.none,
                              isDense: true,
                            ),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'monospace',
                            ),
                            onSubmitted: (v) async {
                              final val = v.trim();
                              if (val.isNotEmpty) {
                                if (!_proxyList.contains(val)) {
                                  setState(() {
                                    _proxyList.add(val);
                                    ConfigService.set("proxy_list", _proxyList);
                                    _proxyController.clear();
                                  });
                                  if (mounted) {
                                    showSuccess("Proxy address added".tl);
                                  }
                                } else {
                                  if (mounted) {
                                    showWarning(
                                      "This address is already in the list".tl,
                                    );
                                  }
                                }
                              }
                            },
                          ),
                        ),
                        IconButton(
                          onPressed: () async {
                            final v = _proxyController.text.trim();
                            if (v.isNotEmpty) {
                              if (!_proxyList.contains(v)) {
                                setState(() {
                                  _proxyList.add(v);
                                  ConfigService.set("proxy_list", _proxyList);
                                  _proxyController.clear();
                                });
                                if (mounted) {
                                  showSuccess("Proxy address added".tl);
                                }
                              } else {
                                if (mounted) {
                                  showWarning(
                                    "This address is already in the list".tl,
                                  );
                                }
                              }
                            }
                          },
                          icon: const Icon(Icons.add, size: 20),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (_selectedCategory == SettingCategory.bloriko) ...[
          _buildSettingItem(
            "Current Character Type".tl,
            "Switch AI processing logic".tl,
            Icons.face,
            dropdown: Win11Dropdown(
              initialValue: Bloriko.type,
              items: [
                Win11DropdownItem(label: "Default".tl, value: "default"),
                Win11DropdownItem(label: "Bloriko".tl, value: "bloriko"),
                if (ConfigService.get("develop_mode") ?? false)
                  Win11DropdownItem(
                    label: "Bloriko (R18)".tl,
                    value: "bloriko_r18",
                  ),
              ],
              onChanged: (value) async {
                if (value != null) {
                  Bloriko.setType(value);
                  setState(() {});
                }
              },
            ),
          ),
          _buildSettingItem(
            "Planning Mode".tl,
            "AI behavior mode".tl,
            Icons.psychology,
            dropdown: Win11Dropdown(
              initialValue: Bloriko.mode,
              items: [
                Win11DropdownItem(label: "Auto Mode".tl, value: "auto"),
                Win11DropdownItem(label: "Assist Click".tl, value: "help"),
                Win11DropdownItem(label: "Planning Mode".tl, value: "plan"),
              ],
              onChanged: (value) {
                if (value != null) {
                  Bloriko.setMode(value);
                  setState(() {});
                }
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            child: Text(
              "Message Connectors".tl,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          _buildSettingItem(
            "WeChat Connector".tl,
            "Scan code to login WeChat for interaction".tl,
            Icons.wechat,
            trailing: BloretButton(text: "WIP".tl, onPressed: null),
          ),
        ],
        if (_selectedCategory == SettingCategory.ai) ...[
          _buildSettingItem(
            "Current Provider".tl,
            "Switch backend interface source".tl,
            Icons.hub,
            dropdown: Win11Dropdown(
              initialValue:
                  ConfigService.get('ai_provider') ?? 'bloret_passport',
              items: [
                Win11DropdownItem(
                  label: "Bloret PassPort",
                  value: "bloret_passport",
                ),
                Win11DropdownItem(label: "OpenCode Zen", value: "opencode_zen"),
                Win11DropdownItem(
                  label: "Google AI Studio",
                  value: "google_ai_studio",
                ),
                Win11DropdownItem(label: "Custom API", value: "custom_api"),
              ],
              onChanged: (p) async {
                if (p != null) {
                  await ConfigService.set('ai_provider', p);
                  setState(() {});
                  if (p == 'google_ai_studio' || p == 'custom_api') {
                    _fetchRemoteAiModels();
                  }
                }
              },
            ),
          ),
          Builder(
            builder: (context) {
              final provider =
                  ConfigService.get('ai_provider') ?? 'bloret_passport';

              if (provider == 'google_ai_studio' || provider == 'custom_api') {
                return _buildSettingItem(
                  "Default Model".tl,
                  "Select the preferred model for this provider".tl,
                  Icons.model_training,
                  dropdown: _isFetchingAiModels
                      ? Align(
                          alignment: Alignment.centerRight,
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: theme.dividerColor.withValues(
                                  alpha: 0.1,
                                ),
                              ),
                            ),
                            padding: const EdgeInsets.all(8),
                            child: const CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          ),
                        )
                      : Win11Dropdown(
                          initialValue: ConfigService.get('ai_model'),
                          items: _remoteModelItems.isEmpty
                              ? [
                                  Win11DropdownItem(
                                    label: "No models fetched".tl,
                                    value: "none",
                                  ),
                                ]
                              : _remoteModelItems,
                          onChanged: (m) async {
                            if (m != null && m != "none" && m != "error") {
                              await ConfigService.set('ai_model', m);
                              setState(() {});
                            }
                          },
                        ),
                );
              }

              final List<Win11DropdownItem> modelItems = switch (provider) {
                "bloret_passport" => [
                  Win11DropdownItem(label: "Claude Fable 5", value: "default"),
                ],
                "opencode_zen" => [
                  Win11DropdownItem(
                    label: "DeepSeek V4 Flash (Free)",
                    value: "deepseek-v4-flash-free",
                  ),
                  Win11DropdownItem(
                    label: "Mimo V2.5 (Free)",
                    value: "mimo-v2.5-free",
                  ),
                  Win11DropdownItem(
                    label: "Qwen 3.6 Plus (Free)",
                    value: "qwen3.6-plus-free",
                  ),
                  Win11DropdownItem(
                    label: "MiniMax M2.5 (Free)",
                    value: "minimax-m2.5-free",
                  ),
                  Win11DropdownItem(
                    label: "Nemotron 3 Super (Free)",
                    value: "nemotron-3-super-free",
                  ),
                ],
                _ => [
                  Win11DropdownItem(
                    label: ConfigService.get("custom_ai_model") ?? "gpt-4o",
                    value: ConfigService.get("custom_ai_model") ?? "gpt-4o",
                  ),
                ],
              };

              return _buildSettingItem(
                "Default Model".tl,
                "Select the preferred model for this provider".tl,
                Icons.model_training,
                dropdown: Win11Dropdown(
                  initialValue:
                      ConfigService.get('ai_model') ?? modelItems.first.value,
                  items: modelItems,
                  onChanged: (m) async {
                    if (m != null) {
                      await ConfigService.set('ai_model', m);
                      setState(() {});
                    }
                  },
                ),
              );
            },
          ),
          _buildSettingItem(
            "Interface Config".tl,
            "Manage API Key and address".tl,
            Icons.settings,
            trailing: BloretButton(
              text: "Configure".tl,
              onPressed: () {
                _showAiConfigDialog(context);
              },
            ),
          ),
        ],
        if (_selectedCategory == SettingCategory.control) ...[
          if (Platform.isWindows)
            _buildSettingItem(
              "Check for Updates".tl,
              "${"Check and install hot update patches".tl} (${"Current".tl}: $_hotfixVersion)",
              Icons.update,
              trailing: _isCheckingUpdate
                  ? const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: () async {
                        setState(() => _isCheckingUpdate = true);
                        try {
                          final update = await UpdateManager.instance
                              .checkUpdate();
                          if (mounted) {
                            if (update != null) {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: Text("New Patch Found".tl),
                                  content: Text(
                                    "${"Version".tl}: ${update.version}\n${"Download and apply now?".tl}\n${"(Note: Requires app restart after application)".tl}",
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, false),
                                      child: Text("Cancel".tl),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, true),
                                      child: Text("Install".tl),
                                    ),
                                  ],
                                ),
                              );

                              if (confirm == true) {
                                final progressController =
                                    StreamController<double>();

                                if (mounted) {
                                  showDialog(
                                    context: context,
                                    barrierDismissible: false,
                                    builder: (context) => StreamBuilder<double>(
                                      stream: progressController.stream,
                                      initialData: 0,
                                      builder: (context, snapshot) {
                                        final p = snapshot.data ?? 0;
                                        final bool isIndeterminate = p > 1.0;
                                        final String percentText =
                                            isIndeterminate
                                            ? "${(p - 1.0).toStringAsFixed(1)} MB"
                                            : "${(p * 100).toInt()}%";

                                        return AlertDialog(
                                          title: Text("Updating patch".tl),
                                          content: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const SizedBox(height: 8),
                                              if (isIndeterminate)
                                                const LinearProgressIndicator()
                                              else
                                                GoogleSquigglySlider(
                                                  value: p * 100,
                                                  max: 100,
                                                ),
                                              const SizedBox(height: 12),
                                              Text(
                                                percentText,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              Text(
                                                "Downloading and applying, please do not close the app..."
                                                    .tl,
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey,
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  );
                                }

                                try {
                                  final result = await UpdateManager.instance
                                      .checkAndApplyUpdate(
                                        context: context.mounted
                                            ? context
                                            : null,
                                        onProgress: (p) =>
                                            progressController.add(p),
                                      );
                                  if (mounted) Navigator.pop(context);
                                  if (!result) return;
                                  await _loadHotfixVersion();
                                  if (mounted) {
                                    showSuccess(
                                      "Patch installed, restart app to take effect."
                                          .tl,
                                    );
                                  }
                                } catch (e) {
                                  if (mounted) Navigator.pop(context);
                                  logger.error(
                                    "[Update] Apply failed: $e",
                                    LogSource.system,
                                  );
                                } finally {
                                  progressController.close();
                                }
                              }
                            } else {
                              showInfo(
                                "You are already on the latest patch version."
                                    .tl,
                              );
                            }
                          }
                        } catch (e) {
                          if (mounted) {
                            showError("${"Check error".tl}: $e");
                          }
                        } finally {
                          if (mounted) {
                            setState(() => _isCheckingUpdate = false);
                          }
                        }
                      },
                    ),
            ),
          _buildSettingItem(
            "Notifications".tl,
            "Show a test notification".tl,
            Icons.notifications_active,
            trailing: BloretButton(
              text: "Show".tl,
              onPressed: () {
                showInfo("This is a test notification".tl);
              },
            ),
          ),
          _buildSettingItem(
            "Notifications Success".tl,
            "Show a test notification".tl,
            Icons.notifications_active,
            trailing: BloretButton(
              text: "Show".tl,
              onPressed: () {
                showSuccess("This is a test notification".tl);
              },
            ),
          ),
          _buildSettingItem(
            "Notifications Warning".tl,
            "Show a test notification".tl,
            Icons.notifications_active,
            trailing: BloretButton(
              text: "Show".tl,
              onPressed: () {
                showWarning("This is a test notification".tl);
              },
            ),
          ),
          _buildSettingItem(
            "Notifications Error".tl,
            "Show a test notification".tl,
            Icons.notifications_active,
            trailing: BloretButton(
              text: "Show".tl,
              onPressed: () {
                showError("This is a test notification".tl);
              },
            ),
          ),
        ],
        const SizedBox(height: 24),
        Text(
          "Most settings require an app restart to take effect.".tl,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }

  Future<void> _showColorPickerDialog(BuildContext context) async {
    Color selectedColor = ThemeManager.instance.seedColor;
    HSVColor hsvColor = HSVColor.fromColor(selectedColor);
    final TextEditingController hexController = TextEditingController(
      text: selectedColor
          .toARGB32()
          .toRadixString(16)
          .substring(2)
          .toUpperCase(),
    );

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text("Custom Theme Color".tl),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    child: Container(
                      height: 180,
                      width: 240,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        gradient: LinearGradient(
                          colors: [
                            Colors.white,
                            hsvColor.withSaturation(1).withValue(1).toColor(),
                          ],
                        ),
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          gradient: const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Colors.black],
                          ),
                        ),
                        child: Stack(
                          children: [
                            Positioned(
                              left: hsvColor.saturation * 240 - 8,
                              top: (1 - hsvColor.value) * 180 - 8,
                              child: Container(
                                width: 16,
                                height: 16,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2,
                                  ),
                                  boxShadow: [
                                    const BoxShadow(
                                      blurRadius: 4,
                                      color: Colors.black26,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Positioned.fill(
                              child: GestureDetector(
                                onTapDown: (details) {
                                  setDialogState(() {
                                    final s = (details.localPosition.dx / 240)
                                        .clamp(0.0, 1.0);
                                    final v =
                                        (1 - (details.localPosition.dy / 180))
                                            .clamp(0.0, 1.0);
                                    hsvColor = hsvColor
                                        .withSaturation(s)
                                        .withValue(v);
                                    selectedColor = hsvColor.toColor();
                                    hexController.text = selectedColor
                                        .toARGB32()
                                        .toRadixString(16)
                                        .substring(2)
                                        .toUpperCase();
                                  });
                                },
                                onPanUpdate: (details) {
                                  setDialogState(() {
                                    final s = (details.localPosition.dx / 240)
                                        .clamp(0.0, 1.0);
                                    final v =
                                        (1 - (details.localPosition.dy / 180))
                                            .clamp(0.0, 1.0);
                                    hsvColor = hsvColor
                                        .withSaturation(s)
                                        .withValue(v);
                                    selectedColor = hsvColor.toColor();
                                    hexController.text = selectedColor
                                        .toARGB32()
                                        .toRadixString(16)
                                        .substring(2)
                                        .toUpperCase();
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    height: 12,
                    width: 240,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFFFF0000),
                          Color(0xFFFFFF00),
                          Color(0xFF00FF00),
                          Color(0xFF00FFFF),
                          Color(0xFF0000FF),
                          Color(0xFFFF00FF),
                          Color(0xFFFF0000),
                        ],
                      ),
                    ),
                    child: Stack(
                      children: [
                        Positioned(
                          left: (hsvColor.hue / 360) * 240 - 6,
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.black26),
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: GestureDetector(
                            onPanUpdate: (details) {
                              setDialogState(() {
                                final h =
                                    (details.localPosition.dx / 240).clamp(
                                      0.0,
                                      1.0,
                                    ) *
                                    360;
                                hsvColor = hsvColor.withHue(h);
                                selectedColor = hsvColor.toColor();
                                hexController.text = selectedColor
                                    .toARGB32()
                                    .toRadixString(16)
                                    .substring(2)
                                    .toUpperCase();
                              });
                            },
                            onTapDown: (details) {
                              setDialogState(() {
                                final h =
                                    (details.localPosition.dx / 240).clamp(
                                      0.0,
                                      1.0,
                                    ) *
                                    360;
                                hsvColor = hsvColor.withHue(h);
                                selectedColor = hsvColor.toColor();
                                hexController.text = selectedColor
                                    .toARGB32()
                                    .toRadixString(16)
                                    .substring(2)
                                    .toUpperCase();
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: selectedColor,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.grey.withValues(alpha: 0.3),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: hexController,
                          decoration: InputDecoration(
                            prefixText: "# ",
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 10,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.bold,
                          ),
                          onChanged: (v) {
                            if (v.length == 6) {
                              try {
                                final color = Color(
                                  int.parse("FF$v", radix: 16),
                                );
                                setDialogState(() {
                                  selectedColor = color;
                                  hsvColor = HSVColor.fromColor(color);
                                });
                              } catch (_) {}
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text("Cancel".tl),
              ),
              TextButton(
                onPressed: () async {
                  await ThemeManager.instance.setCustomSeedColor(selectedColor);
                  if (context.mounted) {
                    Navigator.pop(context);
                    setState(() {});
                    Future.delayed(const Duration(milliseconds: 400), () {
                      if (mounted) ThemeManager.instance.updateTheme();
                    });
                  }
                },
                child: Text("Apply".tl),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showAiConfigDialog(BuildContext context) async {
    final provider = ConfigService.get('ai_provider') ?? 'bloret_passport';
    final urlController = TextEditingController(
      text:
          ConfigService.get("custom_ai_base_url") ??
          "https://api.openai.com/v1",
    );
    final keyController = TextEditingController(
      text: ConfigService.get("custom_ai_key") ?? "",
    );
    final modelController = TextEditingController(
      text: ConfigService.get("custom_ai_model") ?? "gpt-4o",
    );

    final isGoogle = provider == 'google_ai_studio';
    if (isGoogle) {
      keyController.text = ConfigService.get("google_ai_key") ?? "";
    }

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          isGoogle
              ? "Configure Google AI Studio".tl
              : "Configure Custom API".tl,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isGoogle)
              TextField(
                controller: urlController,
                decoration: InputDecoration(
                  labelText: "Base URL".tl,
                  hintText: "https://api.example.com/v1",
                ),
              ),
            TextField(
              controller: keyController,
              decoration: InputDecoration(
                labelText: "API Key".tl,
                hintText: "AQ.xxxxxx",
              ),
              obscureText: true,
            ),
            if (!isGoogle)
              TextField(
                controller: modelController,
                decoration: InputDecoration(
                  labelText: "Default Model ID".tl,
                  hintText: "gpt-4o",
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Cancel".tl),
          ),
          TextButton(
            onPressed: () async {
              if (isGoogle) {
                await ConfigService.set("google_ai_key", keyController.text);
              } else {
                await ConfigService.set(
                  "custom_ai_base_url",
                  urlController.text,
                );
                await ConfigService.set("custom_ai_key", keyController.text);
                await ConfigService.set(
                  "custom_ai_model",
                  modelController.text,
                );
                await ConfigService.set("ai_model", modelController.text);
              }
              if (context.mounted) {
                Navigator.pop(context);
              }
            },
            child: Text("Save".tl),
          ),
        ],
      ),
    );
  }

  Widget _buildPluginList() {
    final service = PluginService.instance;

    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final plugins = service.plugins;

        return Column(
          children: [
            _buildPluginActionBar(),
            const SizedBox(height: 12),
            _buildSettingItem(
              "Hot Reload (Dev)".tl,
              "Automatically reload plugins when files change".tl,
              Icons.bolt,
              switchValue: service.isHotReloadEnabled,
              onSwitchChanged: (v) => service.setHotReload(v),
            ),
            const SizedBox(height: 12),
            if (plugins.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.extension_off, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      Text("No plugins installed".tl, style: const TextStyle(color: Colors.grey)),
                      const SizedBox(height: 8),
                      Text(
                        "Place plugin folders in your data/plugins directory".tl,
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Text(
                      "Installed Plugins".tl,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              ...plugins.map((plugin) => _buildPluginItem(plugin)),
            ],
          ],
        );
      },
    );
  }

  Widget _buildPluginActionBar() {
    final service = PluginService.instance;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, bottom: 8),
          child: Text(
            "Management".tl,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
        ),
        SizedBox(
          width: double.infinity,
          child: FluentCard(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                BloretButton(
                  icon: Icons.folder_open,
                  text: "Open Folder".tl,
                  onPressed: () async {
                    final dir = await service.getPluginsDir();
                    launchUrlString(dir.path);
                  },
                ),
                BloretButton(
                  icon: Icons.refresh,
                  text: "Rescan".tl,
                  onPressed: () => service.scanPlugins(),
                ),
                BloretButton(
                  icon: Icons.language,
                  text: "Marketplace".tl,
                  onPressed: () => launchUrlString("https://launcher.bloret.net/apps"),
                ),
                BloretButton(
                  icon: Icons.delete_sweep,
                  text: "Delete All".tl,
                  onPressed: () => _showBatchDeleteConfirm(),
                  color: Colors.redAccent,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showBatchDeleteConfirm() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Batch Delete".tl),
        content: Text("Are you sure you want to delete all plugins? This action is irreversible.".tl),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text("Cancel".tl)),
          TextButton(
            onPressed: () {
              PluginService.instance.deleteAllPlugins();
              Navigator.pop(context);
              showSuccess("All plugins deleted".tl);
            },
            child: Text("Delete".tl, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildPluginItem(BloretPlugin plugin) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4.0),
      child: FluentCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.extension, size: 32),
              title: Text(plugin.translate(plugin.name), style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text("${plugin.version} | ${plugin.author}"),
              trailing: Switch(
                value: plugin.isEnabled,
                onChanged: (v) => PluginService.instance.togglePlugin(plugin.id, v),
              ),
            ),
            if (plugin.description.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    plugin.translate(plugin.description),
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              ),
            _buildPluginSettings(plugin),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: _buildSettingItem(
                "Permissions".tl,
                "${"Granted".tl}: ${plugin.grantedPermissions.length}/${plugin.requestedPermissions.length}",
                Icons.security,
                itemKey: "plugin_perms_${plugin.id}",
                expandedChild: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ...plugin.requestedPermissions.map((permId) {
                      final bool isGranted = plugin.grantedPermissions.contains(permId);
                      final risk = PluginPermissions.getRisk(permId);
                      return CheckboxListTile(
                        title: Text(PluginPermissions.getLabel(permId)),
                        subtitle: Text(
                          permId,
                          style: TextStyle(
                            fontSize: 10,
                            color: risk == PermissionRisk.high ? Colors.redAccent : Colors.grey,
                          ),
                        ),
                        value: isGranted,
                        dense: true,
                        onChanged: (v) {
                          List<String> newPerms = List.from(plugin.grantedPermissions);
                          if (v == true) {
                            newPerms.add(permId);
                          } else {
                            newPerms.remove(permId);
                          }
                          PluginService.instance.updatePermissions(plugin.id, newPerms);
                        },
                      );
                    }),
                  ],
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildPluginSettings(BloretPlugin plugin) {
    if (plugin.settingsSchema.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: _buildSettingItem(
        "Settings".tl,
        "Configure plugin specific options".tl,
        Icons.settings_applications,
        itemKey: "plugin_settings_${plugin.id}",
        expandedChild: Column(
          children: plugin.settingsSchema.entries.map((e) {
            final key = e.key;
            final schema = e.value as Map<String, dynamic>;
            final defaultValue = schema['default'];
            final currentVal = plugin.pluginSettingsValues[key] ?? defaultValue;

            return _buildPluginSettingControl(plugin, key, schema, currentVal);
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildPluginSettingControl(BloretPlugin plugin, String key, Map<String, dynamic> schema, dynamic value) {
    final title = plugin.translate(key);
    final desc = plugin.translate(schema['description'] ?? "");
    final iconStr = schema['icon']?.toString() ?? "";
    final icon = _getIconData(iconStr);

    if (value is bool) {
      return _buildSettingItem(
        title,
        desc,
        icon,
        switchValue: value,
        onSwitchChanged: (v) {
          final newSettings = Map<String, dynamic>.from(plugin.pluginSettingsValues);
          newSettings[key] = v;
          PluginService.instance.updatePluginSettings(plugin.id, newSettings);
        },
      );
    } else if (value is num) {
      final double minVal = (schema['min'] ?? 0).toDouble();
      final double maxVal = (schema['max'] ?? 100).toDouble();
      return _buildSettingItem(
        title,
        desc.isEmpty ? value.toString() : "$desc (${value.toInt()})",
        icon,
        sliderValue: value.toDouble().clamp(minVal, maxVal),
        sliderMin: minVal,
        sliderMax: maxVal,
        onSliderChanged: (v) {
          final newSettings = Map<String, dynamic>.from(plugin.pluginSettingsValues);
          newSettings[key] = v.toInt();
          PluginService.instance.updatePluginSettings(plugin.id, newSettings);
        },
      );
    }

    return const SizedBox.shrink();
  }

  IconData _getIconData(String key) {
    switch (key.toLowerCase()) {
      case "count": return Icons.numbers;
      case "list": return Icons.list;
      case "image": return Icons.image;
      case "network": return Icons.network_check;
      case "timer": return Icons.timer;
      case "person": return Icons.person;
      case "visibility": return Icons.visibility;
      case "eye": return Icons.visibility;
      default: return Icons.settings;
    }
  }

  Widget _buildSettingItem(
    String title,
    String desc,
    IconData icon, {
    Widget? trailing,
    bool? switchValue,
    ValueChanged<bool>? onSwitchChanged,
    double? sliderValue,
    double? sliderMin,
    double? sliderMax,
    ValueChanged<double>? onSliderChanged,
    Widget? dropdown,
    Widget? expandedChild,
    String? itemKey,
    bool? hoshivetw,
  }) {
    final bool isExpanded = itemKey != null && _expandedItems.contains(itemKey);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: FluentCard(
        padding: EdgeInsets.zero,
        child: hoshivetw == true
            ? Stack(
                children: [
                  Align(
                    alignment: .centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 6, top: 4),
                      child: HoshivetwIcon(noShade: true, size: 64, noAnim: true, color: Colors.white.withOpacityEx(0.25),),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(
                        onTap: expandedChild != null
                            ? () {
                                setState(() {
                                  if (isExpanded) {
                                    _expandedItems.remove(itemKey);
                                  } else {
                                    _expandedItems.add(itemKey!);
                                  }
                                });
                              }
                            : null,
                        borderRadius: BorderRadius.circular(8),
                        splashColor: theme.colorScheme.primary.withValues(
                          alpha: 0.03,
                        ),
                        highlightColor: theme.colorScheme.primary.withValues(
                          alpha: 0.01,
                        ),
                        hoverColor: theme.colorScheme.onSurface.withValues(
                          alpha: 0.02,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Row(
                            children: [
                              Icon(
                                icon,
                                size: 20,
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.8,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                    Text(
                                      desc,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: theme.colorScheme.onSurface
                                            .withValues(alpha: 0.5),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (switchValue != null)
                                Switch(
                                  value: switchValue,
                                  onChanged: onSwitchChanged,
                                ),
                              if (sliderValue != null)
                                SizedBox(
                                  width: 150,
                                  child: Slider(
                                    value: sliderValue,
                                    min: sliderMin ?? 0.0,
                                    max: sliderMax ?? 1.0,
                                    onChanged: onSliderChanged ?? (_) {},
                                  ),
                                ),
                              if (dropdown != null)
                                SizedBox(width: 120, child: dropdown),
                              if (trailing != null &&
                                  switchValue == null &&
                                  sliderValue == null &&
                                  dropdown == null)
                                trailing,
                              if (expandedChild != null)
                                Padding(
                                  padding: const EdgeInsets.only(left: 8),
                                  child: AnimatedRotation(
                                    turns: isExpanded ? 0.5 : 0,
                                    duration: const Duration(milliseconds: 200),
                                    child: Icon(
                                      Icons.expand_more,
                                      size: 20,
                                      color: theme.colorScheme.onSurface
                                          .withValues(alpha: 0.4),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      AnimatedCrossFade(
                        firstChild: const SizedBox(width: double.infinity),
                        secondChild: Column(
                          children: [
                            Divider(
                              height: 1,
                              color: theme.dividerColor.withValues(alpha: 0.05),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: expandedChild ?? const SizedBox.shrink(),
                            ),
                          ],
                        ),
                        crossFadeState: isExpanded
                            ? CrossFadeState.showSecond
                            : CrossFadeState.showFirst,
                        duration: const Duration(milliseconds: 300),
                        sizeCurve: Curves.easeInOutCubic,
                      ),
                    ],
                  ),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: expandedChild != null
                        ? () {
                            setState(() {
                              if (isExpanded) {
                                _expandedItems.remove(itemKey);
                              } else {
                                _expandedItems.add(itemKey!);
                              }
                            });
                          }
                        : null,
                    borderRadius: BorderRadius.circular(8),
                    splashColor: theme.colorScheme.primary.withValues(
                      alpha: 0.03,
                    ),
                    highlightColor: theme.colorScheme.primary.withValues(
                      alpha: 0.01,
                    ),
                    hoverColor: theme.colorScheme.onSurface.withValues(
                      alpha: 0.02,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          Icon(
                            icon,
                            size: 20,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.8,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                Text(
                                  desc,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.5),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (switchValue != null)
                            Switch(
                              value: switchValue,
                              onChanged: onSwitchChanged,
                            ),
                          if (sliderValue != null)
                            SizedBox(
                              width: 150,
                              child: Slider(
                                value: sliderValue,
                                min: sliderMin ?? 0.0,
                                max: sliderMax ?? 1.0,
                                onChanged: onSliderChanged ?? (_) {},
                              ),
                            ),
                          if (dropdown != null)
                            SizedBox(width: 120, child: dropdown),
                          if (trailing != null &&
                              switchValue == null &&
                              sliderValue == null &&
                              dropdown == null)
                            trailing,
                          if (expandedChild != null)
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: AnimatedRotation(
                                turns: isExpanded ? 0.5 : 0,
                                duration: const Duration(milliseconds: 200),
                                child: Icon(
                                  Icons.expand_more,
                                  size: 20,
                                  color: theme.colorScheme.onSurface.withValues(
                                    alpha: 0.4,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  AnimatedCrossFade(
                    firstChild: const SizedBox(width: double.infinity),
                    secondChild: Column(
                      children: [
                        Divider(
                          height: 1,
                          color: theme.dividerColor.withValues(alpha: 0.05),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: expandedChild ?? const SizedBox.shrink(),
                        ),
                      ],
                    ),
                    crossFadeState: isExpanded
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                    duration: const Duration(milliseconds: 300),
                    sizeCurve: Curves.easeInOutCubic,
                  ),
                ],
              ),
      ),
    );
  }
}
