import 'dart:async';
import 'dart:io';
import 'package:bloret_launcher/main.dart';
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
    {"id": "system", "title": "系统", "desc": "关闭与重启程序", "icon": Icons.power_settings_new},
    {"id": "gamepad", "title": "虚拟手柄", "desc": "COMING SOON", "icon": Icons.videogame_asset},
    {"id": "notification", "title": "通知", "desc": "系统推送偏好设置", "icon": Icons.notifications},
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
      final double availableWidth = constraints.maxWidth - 48; // ListView padding 24 * 2
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
                  onTap: isComingSoon ? null : () => setState(() => _currentCategory = cat["id"]),
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
          _buildSettingItem("语言", "调整语言设置", Icons.language, trailing: const Text("简体中文")),
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
          _buildSettingItem("Java 选择模式", "按版本自动匹配或固定路径", Icons.code, dropdown: Win11Dropdown(items: [
            Win11DropdownItem(label: "自动选择 (推荐)", value: "auto"),
            Win11DropdownItem(label: "固定 Java", value: "fixed"),
          ],
            initialValue: ConfigService.get("java_selection_mode") ?? "auto",
            onChanged: (v) => ConfigService.set("java_selection_mode", v),
          )),
          _buildSettingItem("Minecraft 文件夹位置", ConfigService.get("mc_dir") ?? "未设置", Icons.folder, trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(icon: const Icon(Icons.folder_open), onPressed: () {}),
              IconButton(icon: const Icon(Icons.edit), onPressed: () {}),
            ],
          )),
          _buildSettingItem("下载源", "选择下载来源", Icons.cloud_download, dropdown: Win11Dropdown(items: [
            Win11DropdownItem(label: "Bloret", value: "gitcode"),
            Win11DropdownItem(label: "Mojang", value: "official"),
            Win11DropdownItem(label: "BMCLAPI", value: "bmclapi"),
          ],
            initialValue: ConfigService.get("download_source") ?? "gitcode",
            onChanged: (v) => ConfigService.set("download_source", v),
          )),
          // _buildSettingItem("下载线程数", "并发下载数 (建议 8-32)", Icons.list, trailing: SizedBox(
          //   width: 100,
          //   child: TextField(
          //     decoration: const InputDecoration(isDense: true),
          //     controller: TextEditingController(text: (ConfigService.get("max_threads") ?? 16).toString()),
          //     onSubmitted: (v) => ConfigService.set("max_threads", int.tryParse(v) ?? 16),
          //   ),
          // )),
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
            Win11DropdownItem(label: "最小化到托盘", value: "tray"),
            Win11DropdownItem(label: "直接退出", value: "exit"),
          ],
            initialValue: ConfigService.get("minimize_to_tray") ?? "tray",
            onChanged: (v) => ConfigService.set("minimize_to_tray", v),
          )),
          _buildSettingItem("允许重复打开", "运行多个启动器实例", Icons.copy, switchValue: ConfigService.get("repeat_run") ?? false, onSwitchChanged: (v) => ConfigService.set("repeat_run", v)),
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
                  TextButton(onPressed: () => exit(0), child: const Text("退出")),
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
                    TextButton(onPressed: () {
                      Navigator.pop(context);
                      Process.start(Platform.resolvedExecutable, []).then((_) => exit(0));
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
              icon: const Icon(Icons.open_in_new),
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const Scaffold(body: AdvancedLogViewer(canPop: true))));
              },
            )
          ),
          _buildSettingItem("日志文件夹位置", "查看存储的日志文件", Icons.folder, trailing: IconButton(icon: const Icon(Icons.open_in_new), onPressed: () {})),
          _buildSettingItem("清空日志", "删除所有本地日志记录", Icons.delete_sweep, trailing: BloretButton(text: "清空", onPressed: () {})),
        ],
        if (_currentCategory == "network") ...[
          _buildSettingItem("网络代理", "HTTP/SOCKS5 代理地址", Icons.security, trailing: SizedBox(
            width: 200,
            child: TextField(
              decoration: const InputDecoration(hintText: "http://127.0.0.1:7890"),
              onSubmitted: (v) => ConfigService.set("proxy", v),
            ),
          )),
        ],
        if (_currentCategory == "bloriko") ...[
          _buildSettingItem("AI 供应商", "Bloriko 使用的 AI 后端", Icons.smart_toy, trailing: const Text("默认")),
          const Padding(padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16), child: Text("消息连接器", style: TextStyle(fontWeight: FontWeight.bold))),
          _buildSettingItem("微信连接器", "扫码登录微信进行交互", Icons.wechat, trailing: BloretButton(text: "配置", onPressed: () {})),
          // _buildSettingItem("钉钉连接器", "COMING SOON", Icons.chat, trailing: const Text("敬请期待", style: TextStyle(color: Colors.grey, fontSize: 12))),
          // _buildSettingItem("QQ 连接器", "COMING SOON", Icons.chat, trailing: const Text("敬请期待", style: TextStyle(color: Colors.grey, fontSize: 12))),
        ],
        if (_currentCategory == "ai") ...[
          _buildSettingItem("默认 AI 供应商", "全局模型设置", Icons.hub, trailing: const Text("Google AI")),
          _buildSettingItem("添加供应商", "管理自定义 OpenAI 兼容接口", Icons.add, trailing: BloretButton(text: "添加", onPressed: () {})),
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
