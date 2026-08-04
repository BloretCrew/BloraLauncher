import 'dart:async';
import 'dart:io';
import 'package:bloret_launcher/main.dart';
import 'package:bloret_launcher/pages/bloriko_page.dart';
import 'package:bloret_launcher/services/config_service.dart';
import 'package:bloret_launcher/services/update_manager.dart';
import 'package:bloret_launcher/widgets/button.dart';
import 'package:bloret_launcher/widgets/google_widgets.dart';
import 'package:bloret_launcher/widgets/log_viewer.dart';
import 'package:bloret_launcher/widgets/windows_widgets.dart';
import 'package:flutter/material.dart';

import '../core/android_bridge.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _currentCategory = "";
  bool _isCheckingUpdate = false;
  String _hotfixVersion = currentVersion;

  @override
  void initState() {
    super.initState();
    _loadHotfixVersion();
  }

  Future<void> _loadHotfixVersion() async {
    final v = await UpdateManager.instance.getLocalVersion();
    if (mounted) setState(() => _hotfixVersion = v);
  }

  final List<Map<String, dynamic>> _categories = [
    {"id": "minecraft", "title": "Minecraft 与 Java", "desc": "Java、游戏目录与下载源", "icon": Icons.check_box_outline_blank_outlined},
    {"id": "home", "title": "首页", "desc": "账户展示、托盘与多开", "icon": Icons.home},
    {"id": "appearance", "title": "外观", "desc": "语言与主题", "icon": Icons.color_lens},
    {"id": "ai", "title": "AI 供应商", "desc": "默认模型与自定义供应商", "icon": Icons.smart_toy},
    {"id": "control", "title": "应用控制", "desc": "日志查看与高级调试", "icon": Icons.build},
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: _currentCategory == "" ? _buildHub(theme) : _buildDetail(theme),
      ),
    );
  }

  Widget _buildHub(ThemeData theme) {
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
                    Text("当前版本", style: TextStyle(fontWeight: FontWeight.bold)),
                    Text("$name Launcher"),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(config?.latestVersion ?? "--", style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold)),
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
          spacing: 12,
          runSpacing: 12,
          children: _categories.map((cat) {
            return SizedBox(
              width: 400,
              child: InkWell(
                onTap: () => setState(() => _currentCategory = cat["id"]),
                borderRadius: BorderRadius.circular(8),
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
                      const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
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
          _buildSettingItem("语言", "调整语言设置", Icons.language, trailing: const Text("简体中文")),
          _buildSettingItem("主题", "选择界面的颜色模式", Icons.color_lens, trailing: const Text("Auto")),
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
          _buildSettingItem("Java", "选择用于启动 Minecraft 的 Java", Icons.code, trailing: const Text("自动选择")),
          _buildSettingItem("Minecraft 文件夹位置", "C:/Users/Administrator/AppData/Roaming/.minecraft", Icons.folder),
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
          _buildSettingItem(
            "查看日志", 
            "实时查看启动器运行日志", 
            Icons.list, 
            trailing: IconButton(
              icon: const Icon(Icons.open_in_new),
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const Scaffold(body: AdvancedLogViewer(canPop: true))));
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

  Widget _buildSettingItem(
    String title, 
    String desc, 
    IconData icon, {
      Widget? trailing,
      bool? switchValue,
      ValueChanged<bool>? onSwitchChanged,
      double? sliderValue,
      ValueChanged<double>? onSliderChanged,
      Widget? dropdown
    }
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: FluentCard(
        child: Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text(desc, style: const TextStyle(fontSize: 12, color: Colors.grey)),
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
          ],
        ),
      ),
    );
  }
}
