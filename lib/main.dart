import 'dart:ui';
import 'package:flutter/material.dart';
import 'services/config_service.dart';
import 'services/win32_icon_service.dart';
import 'services/passport_service.dart';
import 'pages/welcome_page.dart';
import 'dart:convert';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ConfigService.init();
  Win32IconService.init(); // 初始化 FFI
  runApp(const BloretLauncherApp());
}

class BloretLauncherApp extends StatelessWidget {
  const BloretLauncherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bloret Launcher',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0078D4),
          brightness: Brightness.light,
        ),
        cardTheme: CardTheme(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Colors.grey.withOpacity(0.2))),
        ).data,
        fontFamily: "Segoe"
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0078D4),
          brightness: Brightness.dark,
        ),
        cardTheme: CardTheme(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Colors.white.withOpacity(0.1))),
        ).data,
      ),
      themeMode: ThemeMode.system,
      home: ConfigService.isFirstRun() ? const WelcomeSetupScreen() : const MainShell(),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateAppIcon();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    super.didChangePlatformBrightness();
    _updateAppIcon();
  }

  void _updateAppIcon() {
    final isDark = WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
    Win32IconService.switchIcon(isDark);
  }

  final List<(_NavDestination, Widget)> _pages = [
    (const _NavDestination("主页", Icons.home_outlined, Icons.home), const HomePage()),
    (const _NavDestination("Blora Agent", Icons.smart_toy_outlined, Icons.smart_toy), const PlaceholderPage(title: "Blora Agent")),
    (const _NavDestination("下载", Icons.file_download_outlined, Icons.file_download), const PlaceholderPage(title: "下载")),
    (const _NavDestination("核心", Icons.view_in_ar_outlined, Icons.view_in_ar), const PlaceholderPage(title: "核心")),
    (const _NavDestination("Mods", Icons.extension_outlined, Icons.extension), const PlaceholderPage(title: "Mods")),
    (const _NavDestination("通行证", Icons.person_outline, Icons.person), const PassPortPage()),
    (const _NavDestination("设置", Icons.settings_outlined, Icons.settings), const SettingsPage()),
    (const _NavDestination("关于", Icons.info_outline, Icons.info), const PlaceholderPage(title: "关于")),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPortrait = MediaQuery.of(context).size.height > MediaQuery.of(context).size.width;

    return Scaffold(
      body: Column(
        children: [
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withOpacity(0.5),
              border: Border(bottom: BorderSide(color: theme.dividerColor.withOpacity(0.05))),
            ),
            child: Row(
              children: [
                const FlutterLogo(size: 18),
                const SizedBox(width: 12),
                Text("Bloret Launcher", style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                if (!isPortrait) ...[
                  Icon(Icons.minimize, size: 16, color: theme.colorScheme.onSurface.withOpacity(0.6)),
                  const SizedBox(width: 16),
                  Icon(Icons.close, size: 16, color: theme.colorScheme.onSurface.withOpacity(0.6)),
                ],
              ],
            ),
          ),
          Expanded(
            child: Row(
              children: [
                if (!isPortrait)
                  NavigationRail(
                    extended: MediaQuery.of(context).size.width > 900,
                    selectedIndex: _selectedIndex,
                    onDestinationSelected: (index) => setState(() => _selectedIndex = index),
                    labelType: NavigationRailLabelType.none,
                    destinations: _pages.map((item) {
                      return NavigationRailDestination(
                        icon: Icon(item.$1.icon),
                        selectedIcon: Icon(item.$1.selectedIcon),
                        label: Text(item.$1.title),
                      );
                    }).toList(),
                  ),
                if (!isPortrait) const VerticalDivider(thickness: 1, width: 1),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    transitionBuilder: (child, animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: isPortrait ? const Offset(0, 0.05) : const Offset(0.05, 0),
                            end: Offset.zero,
                          ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
                          child: child,
                        ),
                      );
                    },
                    child: _pages[_selectedIndex].$2,
                  ),
                ),
              ],
            ),
          ),
          Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withOpacity(0.8),
              border: Border(top: BorderSide(color: theme.dividerColor.withOpacity(0.05))),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle_outline, size: 12, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text("就绪", style: theme.textTheme.labelSmall?.copyWith(fontSize: 10)),
                const Spacer(),
                Text("v2.0.0-Beta", style: theme.textTheme.labelSmall?.copyWith(fontSize: 10, color: Colors.grey)),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: isPortrait
          ? NavigationBar(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (index) => setState(() => _selectedIndex = index),
              destinations: _pages.take(5).map((item) {
                return NavigationDestination(
                  icon: Icon(item.$1.icon),
                  selectedIcon: Icon(item.$1.selectedIcon),
                  label: item.$1.title,
                );
              }).toList(),
            )
          : null,
    );
  }
}

class _NavDestination {
  final String title;
  final IconData icon;
  final IconData selectedIcon;
  const _NavDestination(this.title, this.icon, this.selectedIcon);
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  late AnimationController _listController;

  @override
  void initState() {
    super.initState();
    _listController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _listController.forward();
  }

  @override
  void dispose() {
    _listController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                // 标题进入动画
                _SlideFadeIn(
                  controller: _listController,
                  delay: 0,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text("Bloret Launcher",
                          style: theme.textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(width: 12),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(0, 0, 0, 0.8),
                        child: Text("最贴近 Windows 11 设计的 Minecraft 启动器",
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.secondary)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // 活动卡片动画
                _SlideFadeIn(
                  controller: _listController,
                  delay: 0.2,
                  child: _FluentCard(
                    child: Row(
                      children: [
                        Hero(
                          tag: 'grass_block',
                          child: Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceVariant, borderRadius: BorderRadius.circular(12)),
                            child: const Icon(Icons.grass, size: 40),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("筑岁同欢 ✨", style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                              Text("欢迎来到百络谷！这里有最纯粹的生存体验...", style: theme.textTheme.bodyMedium),
                            ],
                          ),
                        ),
                        ElevatedButton(onPressed: () {}, child: const Text("前往")),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),

                // AI 输入框动画
                _SlideFadeIn(
                  controller: _listController,
                  delay: 0.4,
                  child: Row(
                    children: [
                      const CircleAvatar(radius: 20, backgroundColor: Colors.blueGrey),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          decoration: InputDecoration(
                            hintText: "关于 Minecraft 的任何问题，可以问 Blora Agent 哦 ~",
                            isDense: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton.filled(onPressed: () {}, icon: const Icon(Icons.send)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _SlideFadeIn(
                  controller: _listController,
                  delay: 0.5,
                  child: Text("Blora Agent 依靠 AI。可能犯错，请核实重要信息。",
                      style: theme.textTheme.bodySmall?.copyWith(fontSize: 11)),
                ),

                const SizedBox(height: 32),
                _SlideFadeIn(
                  controller: _listController,
                  delay: 0.6,
                  child: Text("信息", style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 12),

                _SlideFadeIn(
                  controller: _listController,
                  delay: 0.7,
                  child: _FluentCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const FlutterLogo(size: 40),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text("Bloret", style: TextStyle(fontWeight: FontWeight.bold)),
                                      Text("256 / 2025", style: theme.textTheme.bodySmall),
                                    ],
                                  ),
                                  Text("bloret.net", style: theme.textTheme.bodySmall),
                                ],
                              ),
                            )
                          ],
                        ),
                        const Divider(height: 24),
                        const Text("Blora Agent 推荐时间段", style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        const Text("嘿嘿~ Blora Agent 来啦！现在的在线人数非常适合游玩哦~"),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          _BottomActionRail(),
        ],
      ),
    );
  }
}

class _SlideFadeIn extends StatelessWidget {
  final Widget child;
  final double delay;
  final AnimationController controller;

  const _SlideFadeIn({required this.child, required this.delay, required this.controller});

  @override
  Widget build(BuildContext context) {
    final animation = CurvedAnimation(
      parent: controller,
      curve: Interval(delay, (delay + 0.3).clamp(0.0, 1.0), curve: Curves.easeOutCubic),
    );

    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        return Opacity(
          opacity: animation.value,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - animation.value)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

class _FluentCard extends StatelessWidget {
  final Widget child;
  const _FluentCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }
}

class _BottomActionRail extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 90,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withOpacity(0.8),
        border: Border(top: BorderSide(color: theme.dividerColor.withOpacity(0.1))),
      ),
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Row(
            children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(color: theme.colorScheme.primaryContainer, borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.inventory_2),
              ),
              const SizedBox(width: 16),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("1.20.1-Forge-47.2.0", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  Text("以身份 Bloret 启动 Minecraft", style: theme.textTheme.bodySmall),
                ],
              ),
              const Spacer(),
              TextButton.icon(onPressed: () {}, icon: const Icon(Icons.swap_horiz), label: const Text("切换核心")),
              const SizedBox(width: 12),
              SizedBox(
                height: 44,
                width: 140,
                child: FilledButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.play_arrow),
                  label: const Text("启动游戏"),
                  style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PlaceholderPage extends StatelessWidget {
  final String title;
  const PlaceholderPage({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Center(child: Text(title, style: Theme.of(context).textTheme.headlineMedium));
  }
}

class PassPortPage extends StatefulWidget {
  const PassPortPage({super.key});

  @override
  State<PassPortPage> createState() => _PassPortPageState();
}

class _PassPortPageState extends State<PassPortPage> {
  bool _isSyncing = false;
  
  Map<String, dynamic> _getAccountData() {
    final data = ConfigService.get('MinecraftAccount');
    if (data == null) return {"logined": false, "chosen": -1, "accounts": []};
    if (data is String) return jsonDecode(data);
    return data as Map<String, dynamic>;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLoggedIn = ConfigService.get('Bloret_PassPort_Login') ?? false;
    final userName = ConfigService.get('Bloret_PassPort_UserName') ?? "访客";
    final avatar = ConfigService.get('Bloret_PassPort_Avatar') ?? "";
    final accountData = _getAccountData();
    final List accounts = accountData['accounts'] ?? [];

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text("通行证", style: theme.textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 24),
          Text("Bloret PassPort", style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          _FluentCard(
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: avatar.isNotEmpty
                      ? Image.network(avatar, width: 48, height: 48, fit: BoxFit.cover)
                      : Container(
                          width: 48,
                          height: 48,
                          color: theme.colorScheme.surfaceVariant,
                          child: const Icon(Icons.person),
                        ),
                ),
                const SizedBox(width: 16),
                Expanded(child: Text(userName, style: const TextStyle(fontWeight: FontWeight.w700))),
                if (!isLoggedIn)
                  ElevatedButton(
                    onPressed: () {},
                    child: const Text("登录", style: TextStyle(fontWeight: FontWeight.w600)),
                  )
                else
                  OutlinedButton(
                    onPressed: () async {
                      await ConfigService.set('Bloret_PassPort_Login', false);
                      await ConfigService.set('Bloret_PassPort_UserName', '');
                      await ConfigService.set('Bloret_PassPort_PassWord', '');
                      setState(() {});
                    },
                    child: const Text("退出登录", style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text("使用 Bloret 通行证，可享受几乎所有的 Bloret 服务。",
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.secondary, fontWeight: FontWeight.w600)),
          const SizedBox(height: 32),
          Row(
            children: [
              Text("Minecraft 账户", style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              const Spacer(),
              if (_isSyncing)
                const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              else
                TextButton(
                  onPressed: () async {
                    setState(() => _isSyncing = true);
                    await PassportService.syncMinecraftAccounts();
                    setState(() => _isSyncing = false);
                  },
                  child: const Text("刷新", style: TextStyle(fontWeight: FontWeight.w600)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (accounts.isEmpty)
            const Center(child: Padding(padding: EdgeInsets.all(20), child: Text("暂无账户，请从云端同步", style: TextStyle(fontWeight: FontWeight.w600))))
          else
            ...accounts.asMap().entries.map((entry) {
              final index = entry.key;
              final account = entry.value;
              final isDefault = accountData['chosen'] == index;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _FluentCard(
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(account['avatarUrl'] ?? "", width: 32, height: 32, errorBuilder: (_, __, ___) => const Icon(Icons.account_circle, size: 32)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(account['name'] ?? "Unknown", style: const TextStyle(fontWeight: FontWeight.w700)),
                            Text(account['type'] ?? "Offline", style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      ElevatedButton(
                        onPressed: isDefault ? null : () async {
                          final newData = Map<String, dynamic>.from(accountData);
                          newData['chosen'] = index;
                          await ConfigService.set('MinecraftAccount', jsonEncode(newData));
                          setState(() {});
                        },
                        child: Text(isDefault ? "正在使用" : "使用此账户", style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          const SizedBox(height: 32),
          _FluentCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("通过 Bloret PassPort 管理你的账户", style: TextStyle(fontWeight: FontWeight.w700)),
                Text("轻松登录你的 Minecraft Account，便捷地进行操作。",
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.secondary, fontWeight: FontWeight.w600)),
                const SizedBox(height: 16),
                Row(
                  children: [
                    OutlinedButton(
                      onPressed: () {},
                      style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                      child: const Text("网站管理", style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: () async {
                        setState(() => _isSyncing = true);
                        await PassportService.syncMinecraftAccounts();
                        setState(() => _isSyncing = false);
                      },
                      style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                      child: const Text("云端同步", style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _currentCategory = "";

  final List<Map<String, dynamic>> _categories = [
    {"id": "minecraft", "title": "Minecraft 与 Java", "desc": "Java、游戏目录与下载源", "icon": Icons.check_box_outline_blank_outlined},
    {"id": "home", "title": "首页", "desc": "账户展示、托盘与多开", "icon": Icons.home},
    {"id": "appearance", "title": "外观", "desc": "语言与主题", "icon": Icons.color_lens},
    {"id": "ai", "title": "AI 供应商", "desc": "默认模型与自定义供应商", "icon": Icons.smart_toy},
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
        _FluentCard(
          child: Row(
            children: [
              const Icon(Icons.info_outline, size: 28),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("当前版本", style: TextStyle(fontWeight: FontWeight.bold)),
                    Text("Bloret Launcher"),
                  ],
                ),
              ),
              Text("2.0.0-Beta", style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold)),
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
                child: _FluentCard(
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
        ],
        if (_currentCategory == "minecraft") ...[
          _buildSettingItem("Java", "选择用于启动 Minecraft 的 Java", Icons.code, trailing: const Text("自动选择")),
          _buildSettingItem("Minecraft 文件夹位置", "C:/Users/Administrator/AppData/Roaming/.minecraft", Icons.folder),
        ],
        const SizedBox(height: 24),
        const Text("设置界面大部分内容需要重启程序后生效。", style: TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  Widget _buildSettingItem(String title, String desc, IconData icon, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: _FluentCard(
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
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }
}
