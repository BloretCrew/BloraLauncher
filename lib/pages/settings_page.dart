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
import 'package:bloret_launcher/widgets/button.dart';
import 'package:bloret_launcher/widgets/google_widgets.dart';
import 'package:bloret_launcher/widgets/log_viewer.dart';
import 'package:bloret_launcher/widgets/windows_widgets.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../core/android_bridge.dart';
import '../services/bloriko.dart';
import '../core/grammer_candy.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _currentCategory = "";
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

  @override
  void initState() {
    super.initState();
    _loadHotfixVersion();
    _minecraftDirs = List<String>.from(ConfigService.get('minecraft_dirs') ?? []);
    _proxyList = List<String>.from(ConfigService.get('proxy_list') ?? []);

    final cachedJava = ConfigService.get('detected_java_list');
    if (cachedJava != null) {
      try {
        _detectedJavaList = (jsonDecode(cachedJava) as List)
            .map((e) => Map<String, String>.from(e))
            .toList();
      } catch (_) {}
    }

    _refreshJavaList();
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
        await ConfigService.set('detected_java_list', jsonEncode(_detectedJavaList));
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

    final key = provider == 'google_ai_studio' ? 'google_ai_key' : 'custom_ai_key';
    final apiKey = ConfigService.get(key);
    if (apiKey == null || apiKey.isEmpty) {
      setState(() {
        _remoteModelItems = [Win11DropdownItem(label: "Please configure API Key first".tl, value: "none")];
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
        if (provider == 'google_ai_studio' && !model.id.contains('gemini')) continue;

        String rawName = model.id.replaceAll('models/', '');
        String formattedName = rawName.split('-').map((word) {
          if (word.isEmpty) return word;
          return word[0].toUpperCase() + word.substring(1);
        }).join(' ');

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
          _remoteModelItems = [Win11DropdownItem(label: "Failed to fetch models".tl, value: "error")];
          _isFetchingAiModels = false;
        });
      }
    }
  }

  final List<Map<String, dynamic>> _categories = [
    {"id": "minecraft", "title": "Minecraft & Java".tl, "desc": "Java, game directories and download sources".tl, "icon": CupertinoIcons.cube},
    {"id": "home", "title": "Home".tl, "desc": "Account display, tray and multi-instance".tl, "icon": Icons.home},
    {"id": "system", "title": "System".tl, "desc": "Close and restart program".tl, "icon": Icons.power_settings_new},
    {"id": "gamepad", "title": "Virtual Gamepad".tl, "desc": "COMING SOON", "icon": Icons.videogame_asset},
    {"id": "notification", "title": "Notifications".tl, "desc": "COMING SOON", "icon": Icons.notifications},
    {"id": "appearance", "title": "Appearance".tl, "desc": "Language and Theme".tl, "icon": Icons.color_lens},
    {"id": "plugins", "title": "Plugins".tl, "desc": "COMING SOON", "icon": Icons.extension},
    {"id": "log", "title": "Logs".tl, "desc": "Open or clear log files".tl, "icon": Icons.list_alt},
    {"id": "network", "title": "Network".tl, "desc": "HTTP / SOCKS5 Proxy".tl, "icon": Icons.language},
    {"id": "ai", "title": "AI Providers".tl, "desc": "Default models and custom providers".tl, "icon": Icons.smart_toy},
    {"id": "bloriko", "title": "Blora Agent".tl, "desc": "AI settings and message connector management".tl, "icon": Icons.chat_bubble_outline},
    {"id": "control", "title": "App Control".tl, "desc": "Hot updates and advanced debugging".tl, "icon": Icons.build},
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: PopScope(
        canPop: _currentCategory == "",
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          if (_currentCategory != "") {
            setState(() => _currentCategory = "");
          }
        },
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _currentCategory == "" ? _buildHub(theme) : _buildDetail(theme),
        ),
      ),
    );
  }

  Widget _buildHub(ThemeData theme) {
    return LayoutBuilder(builder: (context, constraints) {
      final double availableWidth = constraints.maxWidth - 48;
      int columns = (availableWidth / 300).floor().clamp(1, 4);
      final double spacing = columns > 1 ? 12.0 : 0.0;
      final double itemWidth = (availableWidth - (columns - 1) * spacing) / columns;

      return ListView(
        key: const ValueKey("hub"),
        padding: const EdgeInsets.all(24),
        children: [
          Text("Settings".tl, style: theme.textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.bold)),
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
                      Text("Current Version".tl, style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text("$name Launcher"),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text("0.0.1", style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold)),
                    if (_hotfixVersion != "0.0.0") Text("Hotfix $_hotfixVersion", style: const TextStyle(fontSize: 10, color: Colors.grey)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text("Select a category to manage related settings".tl, style: const TextStyle(fontSize: 13, color: Colors.grey)),
          const SizedBox(height: 12),
          Wrap(
            spacing: spacing,
            runSpacing: 12,
            children: _categories.map((cat) {
              final bool isComingSoon = cat["desc"] == "COMING SOON";
              return SizedBox(
                width: itemWidth,
                child: InkWell(
                  onTap: isComingSoon ? null : () {
                    setState(() => _currentCategory = cat["id"]);
                    if (cat["id"] == "ai") _fetchRemoteAiModels();
                  },
                  borderRadius: BorderRadius.circular(8),
                  splashColor: theme.colorScheme.primary.withValues(alpha: 0.03),
                  highlightColor: theme.colorScheme.primary.withValues(alpha: 0.01),
                  hoverColor: theme.colorScheme.onSurface.withValues(alpha: 0.05),
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
                                Text(cat["title"], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                Text(cat["desc"], style: const TextStyle(fontSize: 12, color: Colors.grey)),
                              ],
                            ),
                          ),
                          if (!isComingSoon) const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
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
    });
  }

  Widget _buildDetail(ThemeData theme) {
    final cat = _categories.firstWhere((element) => element["id"] == _currentCategory);
    final brightness = MediaQuery.platformBrightnessOf(context);
    return ListView(
      key: const ValueKey("detail"),
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            IconButton(onPressed: () => setState(() => _currentCategory = ""), icon: const Icon(Icons.arrow_back)),
            const SizedBox(width: 8),
            Text("${"Settings".tl} · ${cat["title"]}", style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 24),
        if (_currentCategory == "appearance") ...[
          _buildSettingItem("Language".tl, "Adjust language settings".tl, Icons.language, dropdown: Win11Dropdown(items: [
            Win11DropdownItem(label: "English (US)", value: "en_us"),
            Win11DropdownItem(label: "简体中文", value: "zh_cn"),
            Win11DropdownItem(label: "繁體中文", value: "zh_tw"),
            Win11DropdownItem(label: "日本語", value: "ja_jp"),
            Win11DropdownItem(label: "Русский", value: "ru_ru"),
          ],
            initialValue: ConfigService.getLanguage(),
            onChanged: (v) async {
              await ConfigService.setLanguage(v ?? "zh_cn");
            },
          )),
          _buildSettingItem("Theme".tl, "Choose interface color mode".tl, Icons.color_lens, dropdown: Win11Dropdown(items: [
            Win11DropdownItem(label: "Auto".tl, value: "Auto"),
            Win11DropdownItem(label: "Light".tl, value: "Light"),
            Win11DropdownItem(label: "Dark".tl, value: "Dark"),
          ],
            initialValue: ConfigService.get("theme_mode") ?? "Auto",
            onChanged: (v) async {
              await ConfigService.set("theme_mode", v);
            },
          )),
          if (Platform.isAndroid)
            _buildSettingItem("App Icon".tl, "Select app icon type".tl, Icons.app_registration, dropdown: Win11Dropdown(items: [
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
            )),
        ],
        if (_currentCategory == "minecraft") ...[
          _buildSettingItem(
            "Java Selection Mode".tl, 
            (ConfigService.get("java_selection_mode") ?? "auto") == "auto" 
              ? "Auto-match paths".tl
              : "${"Fixed path mode".tl}: ${ConfigService.get("java_path") ?? "Not set".tl}", 
            Icons.code,
            itemKey: "java_main",
            expandedChild: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(width: 5,),
                    Win11Dropdown(
                      items: [
                        Win11DropdownItem(label: "Auto Selection (Recommended)".tl, value: "auto"),
                        Win11DropdownItem(label: "Fixed Java".tl, value: "fixed"),
                      ],
                      initialValue: ConfigService.get("java_selection_mode") ?? "auto",
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
                  ]
                ),
                const SizedBox(height: 12),
                _buildSettingItem(
                  (ConfigService.get("java_selection_mode") ?? "auto") == "auto" ? "Available Java Environments".tl : "Select Java Path".tl,
                  "Click to view or change Java".tl,
                  Icons.manage_search,
                  itemKey: "java_list",
                  trailing: _isScanningJava 
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : IconButton(
                        icon: const Icon(Icons.refresh, size: 18), 
                        onPressed: _refreshJavaList,
                        visualDensity: VisualDensity.compact,
                      ),
                  expandedChild: Column(
                    children: [
                      if (_detectedJavaList.isEmpty && !_isScanningJava)
                        Text("No valid Java installation detected".tl, style: const TextStyle(fontSize: 13, color: Colors.redAccent))
                      else
                        ..._detectedJavaList.map((java) {
                          final bool isSelected = ConfigService.get("java_path") == java['path'];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: InkWell(
                              onTap: () async {
                                await ConfigService.set("java_path", java['path']);
                                await ConfigService.set("java_version", java['version']);
                                setState(() {});
                              },
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isSelected 
                                    ? theme.colorScheme.primary.withValues(alpha: 0.1)
                                    : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(6),
                                  border: isSelected ? Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.5)) : null,
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.code, size: 16, color: isSelected ? theme.colorScheme.primary : null),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            java['detail'] ?? "Java ${java['version']}", 
                                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isSelected ? theme.colorScheme.primary : null)
                                          ),
                                          Text(java['path'] ?? "", style: const TextStyle(fontSize: 11, color: Colors.grey, fontFamily: 'monospace'), overflow: TextOverflow.ellipsis),
                                        ],
                                      ),
                                    ),
                                    if (isSelected) Icon(Icons.check_circle, size: 16, color: theme.colorScheme.primary),
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
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.1)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.folder, size: 20, color: theme.colorScheme.primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              path,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, fontFamily: 'monospace'),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            onPressed: () {
                              setState(() {
                                _minecraftDirs.removeAt(index);
                                ConfigService.set("minecraft_dirs", _minecraftDirs);
                              });
                            },
                            icon: const Icon(Icons.remove_circle_outline, size: 20, color: Colors.red),
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
                  child: BloretButton(text: "Add Folder".tl, onPressed: () async {
                    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
                    if (selectedDirectory != null) {
                      setState(() {
                        if (!_minecraftDirs.contains(selectedDirectory)) {
                          _minecraftDirs.add(selectedDirectory);
                          ConfigService.set("minecraft_dirs", _minecraftDirs);
                        }
                      });
                    }
                  }),
                ),
              ],
            ),
          ),
          _buildSettingItem("Download Source".tl, "Select download source".tl, Icons.cloud_download, dropdown: Win11Dropdown(items: [
            Win11DropdownItem(label: "Bloret", value: "gitcode"),
            Win11DropdownItem(label: "Mojang", value: "official"),
            Win11DropdownItem(label: "BMCLAPI", value: "bmclapi"),
          ],
            initialValue: ConfigService.get("download_source") ?? "gitcode",
            onChanged: (v) => ConfigService.set("download_source", v),
          )),
        ],
        if (_currentCategory == "home") ...[
          _buildSettingItem("Show Account Info".tl, "Show account details on home page".tl, Icons.person, dropdown: Win11Dropdown(items: [
            Win11DropdownItem(label: "Compact".tl, value: "compact"),
            Win11DropdownItem(label: "Full".tl, value: "full"),
            Win11DropdownItem(label: "Hidden".tl, value: "hidden"),
          ],
            initialValue: ConfigService.get("home_account_mode") ?? "compact",
            onChanged: (v) => ConfigService.set("home_account_mode", v),
          )),
          _buildSettingItem("Close Button Action".tl, "Minimize to tray or exit directly".tl, Icons.close, dropdown: Win11Dropdown(items: [
            Win11DropdownItem(label: "Minimize to Tray".tl, value: "hide"),
            Win11DropdownItem(label: "Exit Directly".tl, value: "exit"),
          ],
            initialValue: ConfigService.getExitBehavior() == "ask" ? "exit" : ConfigService.getExitBehavior(),
            onChanged: (v) {
              if (v != null) ConfigService.setExitBehavior(v);
            },
          )),
        ],
        if (_currentCategory == "system") ...[
          _buildSettingItem("Close Program".tl, "Completely exit Blora Launcher".tl, Icons.power_settings_new, trailing: BloretButton(text: "Close".tl, onPressed: () {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: Text("Confirm Close".tl),
                content: Text("Are you sure you want to completely exit Blora Launcher?".tl),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: Text("Cancel".tl)),
                  TextButton(onPressed: () => terminateProcess(), child: Text("Exit".tl)),
                ],
              ),
            );
          })),
          if (!Platform.isAndroid)
            _buildSettingItem("Restart Program".tl, "Restart app".tl, Icons.refresh, trailing: BloretButton(text: "Restart".tl, onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text("Confirm Restart".tl),
                  content: Text("Are you sure you want to restart Blora Launcher?".tl),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context), child: Text("Cancel".tl)),
                    TextButton(onPressed: () async {
                      Navigator.pop(context);
                      if (Platform.isWindows) {
                        await Process.start("cmd", ["/c", "start", "", Platform.resolvedExecutable]);
                      } else {
                        await Process.start("sh", ["-c", "${Platform.resolvedExecutable} &"]);
                      }
                      exit(0);
                    }, child: Text("Restart".tl)),
                  ],
                )
              );  
            })),
        ],
        if (_currentCategory == "gamepad") ...[
          Center(child: Padding(padding: const EdgeInsets.all(20), child: Text("Feature not enabled yet".tl))),
        ],
        if (_currentCategory == "notification") ...[
          _buildSettingItem("Enable System Notifications".tl, "Master Switch".tl, Icons.notifications_active, switchValue: true, onSwitchChanged: (v){}),
          _buildSettingItem("Game Launch Completed".tl, "Notification after Minecraft successfully enters".tl, Icons.check_circle, switchValue: true, onSwitchChanged: (v){}),
          _buildSettingItem("Update Reminders".tl, "Notification when there is a new patch".tl, Icons.update, switchValue: true, onSwitchChanged: (v){}),
        ],
        if (_currentCategory == "log") ...[
          _buildSettingItem(
            "View Logs".tl, 
            "View launcher runtime logs in real-time".tl, 
            Icons.list, 
            trailing: IconButton(
              icon: const Icon(Icons.arrow_forward),
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const Scaffold(body: AdvancedLogViewer(canPop: true))));
              },
            )
          ),
          _buildSettingItem("Log Folder Location".tl, (Platform.isWindows || Platform.isLinux) ? p.dirname(Platform.resolvedExecutable) : "App Data Directory".tl, Icons.folder, trailing: IconButton(icon: const Icon(Icons.open_in_new), onPressed: () {})),
          _buildSettingItem("Clear Logs".tl, "Delete all local log records".tl, Icons.delete_sweep, trailing: BloretButton(text: "Clear".tl, onPressed: () {
             showDialog(
               context: context,
               builder: (context) => AlertDialog(
                 title: Text("Confirm Clear".tl),
                 content: Text("Are you sure you want to delete all local log records? This action is irreversible.".tl),
                 actions: [
                   TextButton(onPressed: () => Navigator.pop(context), child: Text("Cancel".tl)),
                   TextButton(onPressed: () async {
                     Navigator.pop(context);
                     await logger.clearLogs();
                     if (context.mounted) {
                       showSuccess("Logs cleared".tl);
                     }
                   }, child: Text("Clear".tl, style: const TextStyle(color: Colors.red))),
                 ],
               ),
             );
          })),
        ],
        if (_currentCategory == "network") ...[
          _buildSettingItem(
            "Network Proxy".tl, 
            ConfigService.get("proxy") == null || ConfigService.get("proxy").isEmpty ? "Proxy disabled".tl : "${"Current proxy".tl}: ${ConfigService.get("proxy")}", 
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
                    title: Text("Not configured".tl, style: const TextStyle(fontSize: 14)),
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
                            title: Text(proxy, style: const TextStyle(fontSize: 14, fontFamily: 'monospace')),
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
                          icon: const Icon(Icons.remove_circle_outline, size: 20, color: Colors.red),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    );
                  }),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: theme.dividerColor.withValues(alpha: 0.1)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.add_link, size: 20, color: theme.colorScheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _proxyController,
                          decoration: const InputDecoration(
                            hintText: "http://127.0.0.1:10808",
                            border: InputBorder.none,
                            isDense: true,
                          ),
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, fontFamily: 'monospace'),
                          onSubmitted: (v) async {
                            final val = v.trim();
                            if (val.isNotEmpty) {
                              if (!_proxyList.contains(val)) {
                                setState(() {
                                  _proxyList.add(val);
                                  ConfigService.set("proxy_list", _proxyList);
                                  _proxyController.clear();
                                });
                                if (mounted) showSuccess("Proxy address added".tl);
                              } else {
                                if (mounted) showWarning("This address is already in the list".tl);
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
                              if (mounted) showSuccess("Proxy address added".tl);
                            } else {
                              if (mounted) showWarning("This address is already in the list".tl);
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
          ),)
        ],
        if (_currentCategory == "bloriko") ...[
          _buildSettingItem("Current Character Type".tl, "Switch AI processing logic".tl, Icons.face, dropdown: Win11Dropdown(
            initialValue: Bloriko.type,
            items: [
              Win11DropdownItem(label: "Default".tl, value: "default"),
              Win11DropdownItem(label: "Bloriko".tl, value: "bloriko"),
              if (ConfigService.get("develop_mode") ?? false) Win11DropdownItem(label: "Bloriko (R18)".tl, value: "bloriko_r18"),
            ],
            onChanged: (value) async {
              if (value != null) {
                Bloriko.setType(value);
                setState(() {});
              }
            },
          )),
          _buildSettingItem("Planning Mode".tl, "AI behavior mode".tl, Icons.psychology, dropdown: Win11Dropdown(
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
          )),
          Padding(padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16), child: Text("Message Connectors".tl, style: const TextStyle(fontWeight: FontWeight.bold))),
          _buildSettingItem("WeChat Connector".tl, "Scan code to login WeChat for interaction".tl, Icons.wechat, trailing: BloretButton(text: "Configure".tl, onPressed: () {})),
        ],
        if (_currentCategory == "ai") ...[
           _buildSettingItem("Current Provider".tl, "Switch backend interface source".tl, Icons.hub, dropdown: Win11Dropdown(
             initialValue: ConfigService.get('ai_provider') ?? 'bloret_passport',
             items: [
                Win11DropdownItem(label: "Bloret PassPort", value: "bloret_passport"),
                Win11DropdownItem(label: "OpenCode Zen", value: "opencode_zen"),
                Win11DropdownItem(label: "Google AI Studio", value: "google_ai_studio"),
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
           )),
           Builder(builder: (context) {
             final provider = ConfigService.get('ai_provider') ?? 'bloret_passport';
             
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
                           color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                           borderRadius: BorderRadius.circular(6),
                           border: Border.all(color: theme.dividerColor.withValues(alpha: 0.1)),
                         ),
                         padding: const EdgeInsets.all(8),
                         child: const CircularProgressIndicator(strokeWidth: 2),
                       ),
                     )
                   : Win11Dropdown(
                       initialValue: ConfigService.get('ai_model'),
                       items: _remoteModelItems.isEmpty 
                         ? [Win11DropdownItem(label: "No models fetched".tl, value: "none")] 
                         : _remoteModelItems,
                       onChanged: (m) async {
                         if (m != null && m != "none" && m != "error") {
                           await ConfigService.set('ai_model', m);
                           setState(() {});
                         }
                       },
                     )
               );
             }

             final List<Win11DropdownItem> modelItems = switch (provider) {
               "bloret_passport" => [
                 Win11DropdownItem(label: "Claude Fable 5", value: "default"),
               ],
               "opencode_zen" => [
                 Win11DropdownItem(label: "DeepSeek V4 Flash (Free)", value: "deepseek-v4-flash-free"),
                 Win11DropdownItem(label: "Mimo V2.5 (Free)", value: "mimo-v2.5-free"),
                 Win11DropdownItem(label: "Qwen 3.6 Plus (Free)", value: "qwen3.6-plus-free"),
                 Win11DropdownItem(label: "MiniMax M2.5 (Free)", value: "minimax-m2.5-free"),
                 Win11DropdownItem(label: "Nemotron 3 Super (Free)", value: "nemotron-3-super-free"),
               ],
               _ => [
                 Win11DropdownItem(label: ConfigService.get("custom_ai_model") ?? "gpt-4o", value: ConfigService.get("custom_ai_model") ?? "gpt-4o"),
               ],
             };

             return _buildSettingItem("Default Model".tl, "Select the preferred model for this provider".tl, Icons.model_training, dropdown: Win11Dropdown(
               initialValue: ConfigService.get('ai_model') ?? modelItems.first.value,
               items: modelItems,
               onChanged: (m) async {
                 if (m != null) {
                   await ConfigService.set('ai_model', m);
                   setState(() {});
                 }
               },
             ));
           }),
           _buildSettingItem("Interface Config".tl, "Manage API Key and address".tl, Icons.settings, trailing: BloretButton(text: "Configure".tl, onPressed: () {
              _showAiConfigDialog(context);
           })),
        ],
        if (_currentCategory == "control") ...[
          if (Platform.isWindows) _buildSettingItem(
            "Check for Updates".tl, 
            "${"Check and install hot update patches".tl} (${"Current".tl}: $_hotfixVersion)", 
            Icons.update, 
            trailing: _isCheckingUpdate 
              ? const Padding(padding: EdgeInsets.only(right: 6), child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2)))
              : IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () async {
                  setState(() => _isCheckingUpdate = true);
                  try {
                    final update = await UpdateManager.instance.checkUpdate();
                    if (mounted) {
                      if (update != null) {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: Text("New Patch Found".tl),
                            content: Text("${"Version".tl}: ${update.version}\n${"Download and apply now?".tl}\n${"(Note: Requires app restart after application)".tl}"),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(context, false), child: Text("Cancel".tl)),
                              TextButton(onPressed: () => Navigator.pop(context, true), child: Text("Install".tl)),
                            ],
                          ),
                        );

                        if (confirm == true) {
                          final progressController = StreamController<double>();

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
                                final String percentText = isIndeterminate 
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
                                        GoogleSquigglySlider(value: p * 100, max: 100,),
                                      const SizedBox(height: 12),
                                      Text(percentText, style: const TextStyle(fontWeight: FontWeight.bold)),
                                      Text("Downloading and applying, please do not close the app...".tl, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                    ],
                                  ),
                                );
                              },
                            ),
                          );
                          }

                          try {
                            final result = await UpdateManager.instance.checkAndApplyUpdate(
                              context: context.mounted ? context : null,
                              onProgress: (p) => progressController.add(p)
                            );
                            if (mounted) Navigator.pop(context);
                            if (!result) return;
                            await _loadHotfixVersion();
                            if (mounted) {
                              showSuccess("Patch installed, restart app to take effect.".tl);
                            }
                          } catch (e) {
                            if (mounted) Navigator.pop(context);
                            logger.error("[Update] Apply failed: $e", LogSource.system);
                          } finally {
                            progressController.close();
                          }
                        }
                      } else {
                        showInfo("You are already on the latest patch version.".tl);
                      }
                    }
                  } catch (e) {
                    if (mounted) {
                      showError("${"Check error".tl}: $e");
                    }
                  } finally {
                    if (mounted) setState(() => _isCheckingUpdate = false);
                  }
                },
              )
          ),
          _buildSettingItem("Notifications".tl, "Show a test notification".tl, Icons.notifications_active, trailing: BloretButton(text: "Show".tl, onPressed: () {
            showInfo("This is a test notification".tl);
          })),
        ],
        const SizedBox(height: 24),
        Text("Most settings require an app restart to take effect.".tl, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  Future<void> _showAiConfigDialog(BuildContext context) async {
    final provider = ConfigService.get('ai_provider') ?? 'bloret_passport';
    final urlController = TextEditingController(text: ConfigService.get("custom_ai_base_url") ?? "https://api.openai.com/v1");
    final keyController = TextEditingController(text: ConfigService.get("custom_ai_key") ?? "");
    final modelController = TextEditingController(text: ConfigService.get("custom_ai_model") ?? "gpt-4o");

    final isGoogle = provider == 'google_ai_studio';
    if (isGoogle) {
      keyController.text = ConfigService.get("google_ai_key") ?? "";
    }

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isGoogle ? "Configure Google AI Studio".tl : "Configure Custom API".tl),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isGoogle)
              TextField(
                controller: urlController,
                decoration: InputDecoration(labelText: "Base URL".tl, hintText: "https://api.example.com/v1"),
              ),
            TextField(
              controller: keyController,
              decoration: InputDecoration(labelText: "API Key".tl, hintText: "AQ.xxxxxx"),
              obscureText: true,
            ),
            if (!isGoogle)
              TextField(
                controller: modelController,
                decoration: InputDecoration(labelText: "Default Model ID".tl, hintText: "gpt-4o"),
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text("Cancel".tl)),
          TextButton(
            onPressed: () async {
              if (isGoogle) {
                await ConfigService.set("google_ai_key", keyController.text);
              } else {
                await ConfigService.set("custom_ai_base_url", urlController.text);
                await ConfigService.set("custom_ai_key", keyController.text);
                await ConfigService.set("custom_ai_model", modelController.text);
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

  Widget _buildSettingItem(
    String title, 
    String desc, 
    IconData icon, {
      Widget? trailing,
      bool? switchValue,
      ValueChanged<bool>? onSwitchChanged,
      double? sliderValue,
      ValueChanged<double>? onSliderChanged,
      Widget? dropdown,
      Widget? expandedChild,
      String? itemKey,
    }
  ) {
    final bool isExpanded = itemKey != null && _expandedItems.contains(itemKey);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: FluentCard(
        padding: EdgeInsets.zero,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: expandedChild != null ? () {
                setState(() {
                  if (isExpanded) {
                    _expandedItems.remove(itemKey);
                  } else {
                    _expandedItems.add(itemKey!);
                  }
                });
              } : null,
              borderRadius: BorderRadius.circular(8),
              splashColor: theme.colorScheme.primary.withValues(alpha: 0.03),
              highlightColor: theme.colorScheme.primary.withValues(alpha: 0.01),
              hoverColor: theme.colorScheme.onSurface.withValues(alpha: 0.02),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Icon(icon, size: 20, color: theme.colorScheme.onSurface.withValues(alpha: 0.8)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          Text(desc, style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
                        ],
                      ),
                    ),
                    if (switchValue != null)
                      Switch(value: switchValue, onChanged: onSwitchChanged),
                    if (sliderValue != null)
                      SizedBox(
                        width: 150,
                        child: Slider(value: sliderValue, onChanged: onSliderChanged ?? (_) {}),
                      ),
                    if (dropdown != null)
                      SizedBox(width: 120, child: dropdown),
                    if (trailing != null && switchValue == null && sliderValue == null && dropdown == null)
                      trailing,
                    if (expandedChild != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: AnimatedRotation(
                          turns: isExpanded ? 0.5 : 0,
                          duration: const Duration(milliseconds: 200),
                          child: Icon(Icons.expand_more, size: 20, color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
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
                   Divider(height: 1, color: theme.dividerColor.withValues(alpha: 0.05)),
                   Padding(
                     padding: const EdgeInsets.all(16),
                     child: expandedChild ?? const SizedBox.shrink(),
                   ),
                ],
              ),
              crossFadeState: isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 300),
              sizeCurve: Curves.easeInOutCubic,
            ),
          ],
        ),
      ),
    );
  }
}
