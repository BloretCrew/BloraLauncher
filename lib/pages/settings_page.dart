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
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../core/android_bridge.dart';
import '../services/bloriko.dart';

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
      _detectedJavaList = []; // Start fresh for real-time visual
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
        _remoteModelItems = [Win11DropdownItem(label: "请先配置 API Key".tl, value: "none")];
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
          _remoteModelItems = [Win11DropdownItem(label: "获取模型失败".tl, value: "error")];
          _isFetchingAiModels = false;
        });
      }
    }
  }

  final List<Map<String, dynamic>> _categories = [
    {"id": "minecraft", "title": "Minecraft 与 Java", "desc": "Java、游戏目录与下载源", "icon": Icons.check_box_outline_blank_outlined},
    {"id": "home", "title": "首页", "desc": "账户展示、托盘与多开", "icon": Icons.home},
    {"id": "system", "title": "系统", "desc": "关闭与重启程序", "icon": Icons.power_settings_new},
    {"id": "gamepad", "title": "虚拟手柄", "desc": "COMING SOON", "icon": Icons.videogame_asset},
    {"id": "notification", "title": "通知", "desc": "COMING SOON", "icon": Icons.notifications},
    {"id": "appearance", "title": "外观", "desc": "语言与主题", "icon": Icons.color_lens},
    {"id": "plugins", "title": "插件", "desc": "COMING SOON", "icon": Icons.extension},
    {"id": "log", "title": "日志", "desc": "打开或清空日志文件", "icon": Icons.list_alt},
    {"id": "network", "title": "网络", "desc": "HTTP / SOCKS5 代理", "icon": Icons.language},
    {"id": "ai", "title": "AI 供应商", "desc": "默认模型与自定义供应商", "icon": Icons.smart_toy},
    {"id": "bloriko", "title": "Blora Agent", "desc": "AI 设置与消息连接器管理", "icon": Icons.chat_bubble_outline},
    {"id": "control", "title": "应用控制", "desc": "热更新与高级调试", "icon": Icons.build},
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
          Text("设置", style: theme.textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.bold)),
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
                      const Text("当前版本", style: TextStyle(fontWeight: FontWeight.bold)),
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
          const Text("选择一个类别以管理相关设置", style: TextStyle(fontSize: 13, color: Colors.grey)),
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
            Text("设置 · ${cat["title"]}", style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 24),
        if (_currentCategory == "appearance") ...[
          _buildSettingItem("语言", "调整语言设置", Icons.language, dropdown: Win11Dropdown(items: [
            Win11DropdownItem(label: "English (US)", value: "en_us"),
            Win11DropdownItem(label: "简体中文", value: "zh_cn"),
            Win11DropdownItem(label: "繁體中文", value: "zh_tw"),
            Win11DropdownItem(label: "日本語", value: "ja_jp"),
            Win11DropdownItem(label: "Русский", value: "ru_ru"),
          ],
            initialValue: ConfigService.get("language") ?? "zh_cn",
            onChanged: (v) async {
              await ConfigService.set("language", v);
            },
          )),
          _buildSettingItem("主题", "选择界面的颜色模式", Icons.color_lens, dropdown: Win11Dropdown(items: [
            Win11DropdownItem(label: "自动", value: "Auto"),
            Win11DropdownItem(label: "浅色", value: "Light"),
            Win11DropdownItem(label: "深色", value: "Dark"),
          ],
            initialValue: ConfigService.get("theme_mode") ?? "Auto",
            onChanged: (v) async {
              await ConfigService.set("theme_mode", v);
            },
          )),
          if (Platform.isAndroid)
            _buildSettingItem("应用图标", "选择应用图标类型", Icons.app_registration, dropdown: Win11Dropdown(items: [
              Win11DropdownItem(label: "亮色", value: "light"),
              Win11DropdownItem(label: "暗色", value: "dark"),
              Win11DropdownItem(label: "系统", value: "system"),
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
            "Java 选择模式", 
            (ConfigService.get("java_selection_mode") ?? "auto") == "auto" 
              ? "自动匹配路径"
              : "固定路径模式: ${ConfigService.get("java_path") ?? "未设置"}", 
            Icons.code,
            itemKey: "java_main",
            expandedChild: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: .min,
                  children: [
                    const SizedBox(width: 5,),
                    Win11Dropdown(
                      items: [
                        Win11DropdownItem(label: "自动选择 (推荐)", value: "auto"),
                        Win11DropdownItem(label: "固定 Java", value: "fixed"),
                      ],
                      initialValue: ConfigService.get("java_selection_mode") ?? "auto",
                      onChanged: (v) {
                        setState(() {
                          ConfigService.set("java_selection_mode", v);
                          // Update expansion state for inner list based on mode
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
                  (ConfigService.get("java_selection_mode") ?? "auto") == "auto" ? "可用 Java 环境" : "选择 Java 路径",
                  "点击查看或更换 Java",
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
                        const Text("未检测到有效的 Java 安装", style: TextStyle(fontSize: 13, color: Colors.redAccent))
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
                        }).toList(),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _buildSettingItem(
            "Minecraft 文件夹位置", 
            "管理游戏文件的存储路径 (${_minecraftDirs.length})", 
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
                  child: BloretButton(text: "添加文件夹", onPressed: () async {
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
          _buildSettingItem("下载源", "选择下载来源", Icons.cloud_download, dropdown: Win11Dropdown(items: [
            Win11DropdownItem(label: "Bloret", value: "gitcode"),
            Win11DropdownItem(label: "Mojang", value: "official"),
            Win11DropdownItem(label: "BMCLAPI", value: "bmclapi"),
          ],
            initialValue: ConfigService.get("download_source") ?? "gitcode",
            onChanged: (v) => ConfigService.set("download_source", v),
          )),
        ],
        if (_currentCategory == "home") ...[
          _buildSettingItem("显示账户信息", "在首页展示账户详情", Icons.person, dropdown: Win11Dropdown(items: [
            Win11DropdownItem(label: "简略展示", value: "compact"),
            Win11DropdownItem(label: "完整展示", value: "full"),
            Win11DropdownItem(label: "隐藏", value: "hidden"),
          ],
            initialValue: ConfigService.get("home_account_mode") ?? "compact",
            onChanged: (v) => ConfigService.set("home_account_mode", v),
          )),
          _buildSettingItem("关闭按钮动作", "最小化到托盘或直接退出", Icons.close, dropdown: Win11Dropdown(items: [
            Win11DropdownItem(label: "最小化到托盘", value: "hide"),
            Win11DropdownItem(label: "直接退出", value: "exit"),
          ],
            initialValue: ConfigService.getExitBehavior() == "ask" ? "exit" : ConfigService.getExitBehavior(),
            onChanged: (v) {
              if (v != null) ConfigService.setExitBehavior(v);
            },
          )),
          // _buildSettingItem("允许重复打开", "运行多个启动器实例", Icons.copy, switchValue: ConfigService.get("repeat_run") ?? false, onSwitchChanged: (v) => ConfigService.set("repeat_run", v)),
        ],
        if (_currentCategory == "system") ...[
          _buildSettingItem("关闭程序", "完全退出 Blora Launcher", Icons.power_settings_new, trailing: BloretButton(text: "关闭", onPressed: () {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text("确认关闭"),
                content: const Text("确定要完全退出 Blora Launcher 吗？"),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text("取消")),
                  TextButton(onPressed: () => terminateProcess(), child: const Text("退出")),
                ],
              ),
            );
          })),
          if (!Platform.isAndroid)
            _buildSettingItem("重启程序", "重新启动应用", Icons.refresh, trailing: BloretButton(text: "重启", onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text("确认重启"),
                  content: const Text("确定要重启 Blora Launcher"),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text("取消")),
                    TextButton(onPressed: () async {
                      Navigator.pop(context);
                      if (Platform.isWindows) {
                        await Process.start("cmd", ["/c", "start", "", Platform.resolvedExecutable]);
                      } else {
                        await Process.start("sh", ["-c", "${Platform.resolvedExecutable} &"]);
                      }
                      exit(0);
                    }, child: const Text("重启")),
                  ],
                )
              );  
            })),
        ],
        if (_currentCategory == "gamepad") ...[
          /*
          _buildSettingItem("移动摇杆灵敏度", "控制移动响应速度", Icons.directions_run, sliderValue: 0.5, onSliderChanged: (v){}),
          _buildSettingItem("视角摇杆灵敏度", "控制视角旋转速度", Icons.visibility, sliderValue: 0.5, onSliderChanged: (v){}),
          */
          const Center(child: Padding(padding: EdgeInsets.all(20), child: Text("功能暂未启用"))),
        ],
        if (_currentCategory == "notification") ...[
          _buildSettingItem("启用系统通知", "总开关", Icons.notifications_active, switchValue: true, onSwitchChanged: (v){}),
          _buildSettingItem("游戏启动完成", "Minecraft 成功进入后的通知", Icons.check_circle, switchValue: true, onSwitchChanged: (v){}),
          _buildSettingItem("更新提醒", "应用有新补丁时的通知", Icons.update, switchValue: true, onSwitchChanged: (v){}),
        ],
        if (_currentCategory == "log") ...[
          _buildSettingItem(
            "查看日志", 
            "实时查看启动器运行日志", 
            Icons.list, 
            trailing: IconButton(
              icon: const Icon(Icons.arrow_forward),
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const Scaffold(body: AdvancedLogViewer(canPop: true))));
              },
            )
          ),
          _buildSettingItem("日志文件夹位置", (Platform.isWindows || Platform.isLinux) ? p.dirname(Platform.resolvedExecutable) : "应用数据目录", Icons.folder, trailing: IconButton(icon: const Icon(Icons.open_in_new), onPressed: () {})),
          _buildSettingItem("清空日志", "删除所有本地日志记录", Icons.delete_sweep, trailing: BloretButton(text: "清空", onPressed: () {
             showDialog(
               context: context,
               builder: (context) => AlertDialog(
                 title: const Text("确认清空"),
                 content: const Text("确定要删除所有本地日志记录吗？此操作不可撤销。"),
                 actions: [
                   TextButton(onPressed: () => Navigator.pop(context), child: const Text("取消")),
                   TextButton(onPressed: () async {
                     final nav = Navigator.of(context);
                     final messenger = noticeManager;
                     nav.pop();
                     final logger = await AppLogger.getInstance();
                     await logger.clearLogs();
                     if (!context.mounted) return;
                     messenger.show(context, message: "日志已清空", icon: Icons.check_circle);
                   }, child: const Text("清空", style: TextStyle(color: Colors.red))),
                 ],
               ),
             );
          })),
        ],
        if (_currentCategory == "network") ...[
          _buildSettingItem(
            "网络代理", 
            ConfigService.get("proxy") == null || ConfigService.get("proxy").isEmpty ? "未启用代理" : "当前代理: ${ConfigService.get("proxy")}", 
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
                  const RadioListTile<String>(
                    title: Text("未配置", style: TextStyle(fontSize: 14)),
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
                // Add New Proxy
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
                                if (mounted) noticeManager.show(context, message: "已添加代理地址", icon: Icons.check_circle);
                              } else {
                                if (mounted) noticeManager.show(context, message: "该地址已在列表中", icon: Icons.warning);
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
                              if (mounted) noticeManager.show(context, message: "已添加代理地址", icon: Icons.check_circle);
                            } else {
                              if (mounted) noticeManager.show(context, message: "该地址已在列表中", icon: Icons.warning);
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
          _buildSettingItem("当前角色类型", "切换 AI 处理逻辑", Icons.face, dropdown: Win11Dropdown(
            initialValue: Bloriko.type,
            items: [
              Win11DropdownItem(label: "默认", value: "default"),
              Win11DropdownItem(label: "络可", value: "bloriko"),
              if (ConfigService.get("develop_mode") ?? false) Win11DropdownItem(label: "络可 (R18)", value: "bloriko_r18"),
            ],
            onChanged: (value) async {
              if (value != null) {
                Bloriko.setType(value);
                setState(() {});
              }
            },
          )),
          _buildSettingItem("规划模式", "AI 运行行为模式", Icons.psychology, dropdown: Win11Dropdown(
            initialValue: Bloriko.mode,
            items: [
              Win11DropdownItem(label: "自动模式", value: "auto"),
              Win11DropdownItem(label: "辅助点击", value: "help"),
              Win11DropdownItem(label: "规划模式", value: "plan"),
            ],
            onChanged: (value) {
              if (value != null) {
                Bloriko.setMode(value);
                setState(() {});
              }
            },
          )),
          const Padding(padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16), child: Text("消息连接器", style: TextStyle(fontWeight: FontWeight.bold))),
          _buildSettingItem("微信连接器", "扫码登录微信进行交互", Icons.wechat, trailing: BloretButton(text: "配置", onPressed: () {})),
        ],
        if (_currentCategory == "ai") ...[
           _buildSettingItem("当前提供商", "切换后端接口源", Icons.hub, dropdown: Win11Dropdown(
             initialValue: ConfigService.get('ai_provider') ?? 'bloret_passport',
             items: [
                Win11DropdownItem(label: "Bloret PassPort", value: "bloret_passport"),
                Win11DropdownItem(label: "OpenCode Zen", value: "opencode_zen"),
                Win11DropdownItem(label: "Google AI Studio", value: "google_ai_studio"),
                Win11DropdownItem(label: "自定义 API", value: "custom_api"),
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
                 "默认模型", 
                 "选择该提供商下的首选模型", 
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
                         ? [Win11DropdownItem(label: "未获取到模型".tl, value: "none")] 
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

             return _buildSettingItem("默认模型", "选择该提供商下的首选模型", Icons.model_training, dropdown: Win11Dropdown(
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
           _buildSettingItem("接口配置", "管理 API Key 与地址", Icons.settings, trailing: BloretButton(text: "配置", onPressed: () {
              _showAiConfigDialog(context);
           })),
        ],
        if (_currentCategory == "control") ...[
          if (Platform.isWindows) _buildSettingItem(
            "检查更新", 
            "检查并安装热更新补丁 (当前: $_hotfixVersion)", 
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
                            title: const Text("发现新补丁"),
                            content: Text("版本: ${update.version}\n是否立即下载并应用？\n(注意：覆盖后需重启应用)"),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("取消")),
                              TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("安装")),
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
                                  title: const Text("正在更新补丁"),
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
                                      const Text("正在下载并应用，请勿关闭应用...", style: TextStyle(fontSize: 12, color: Colors.grey)),
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
                              noticeManager.show(context, message: "补丁已安装，重启应用生效。", icon: Icons.check_circle);
                            }
                          } catch (e) {
                            if (mounted) Navigator.pop(context);
                            rethrow;
                          } finally {
                            progressController.close();
                          }
                        }
                      } else {
                        noticeManager.show(context, message: "当前已是最新补丁版本。", icon: Icons.info);
                      }
                    }
                  } catch (e) {
                    if (mounted) {
                      noticeManager.show(context, message: "检查出错: $e", icon: Icons.error);
                    }
                  } finally {
                    if (mounted) setState(() => _isCheckingUpdate = false);
                  }
                },
              )
          ),
          _buildSettingItem("通知", "显示一个测试通知", Icons.notifications_active, trailing: BloretButton(text: "显示", onPressed: () {
            noticeManager.show(context, message: "这是一个测试通知", icon: Icons.info);
          })),
        ],
        const SizedBox(height: 24),
        const Text("设置界面大部分内容需要重启程序后生效。", style: TextStyle(fontSize: 12, color: Colors.grey)),
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
        title: Text(isGoogle ? "配置 Google AI Studio".tl : "配置自定义 API".tl),
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
                decoration: InputDecoration(labelText: "默认模型 ID".tl, hintText: "gpt-4o"),
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text("取消".tl)),
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
            child: Text("保存".tl),
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
