import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:ai_flutter_agent/ai_flutter_agent.dart';
import 'package:bloret_launcher/pages/about_page.dart';
import 'package:bloret_launcher/pages/bbbs_page.dart';
import 'package:bloret_launcher/pages/blora_chat_page.dart';
import 'package:bloret_launcher/pages/cores_page.dart';
import 'package:bloret_launcher/pages/download_page.dart';
import 'package:bloret_launcher/pages/live_page.dart';
import 'package:bloret_launcher/pages/mods_page.dart';
import 'package:bloret_launcher/pages/stat_page.dart';
import 'package:bloret_launcher/pages/tools_page.dart';
import 'package:bloret_launcher/services/bloriko.dart';
import 'package:bloret_launcher/services/memory.dart';
import 'package:bloret_launcher/tools/server_info.dart';
import 'package:bloret_launcher/widgets/button.dart';
import 'package:bloret_launcher/widgets/sliding_text.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'core/global.dart';
import 'services/config_service.dart';
import 'services/win32_icon_service.dart';
import 'services/passport_service.dart';
import 'core/window_bridge.dart';
import 'pages/welcome_page.dart';
import 'dart:convert';

BloretLauncherConfig? config;

BloretServer? server;

const name = "Blora";

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ConfigService.init();
  Win32IconService.init();
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return const SizedBox.shrink();
  };
  Bloriko.getInstance();
  await MemoryStore.instance.loadOnInit();
  runApp(const BloretLauncherApp());
}

class BloretLauncherApp extends StatelessWidget {
  const BloretLauncherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '$name Launcher',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0078D4),
          brightness: Brightness.light,
        ),
        cardTheme: CardTheme(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Colors.grey.withValues(alpha: 0.2))),
        ).data,
        buttonTheme: ButtonThemeData(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
        ),
        fontFamily: "Microsoft",
        textTheme: const TextTheme().apply(fontFamily: "Microsoft"),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0078D4),
          brightness: Brightness.dark,
        ),
        cardTheme: CardTheme(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
        ).data,
        buttonTheme: ButtonThemeData(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
        ),
        fontFamily: "Microsoft",
        textTheme: const TextTheme().apply(fontFamily: "Microsoft"),
      ),
      themeMode: ThemeMode.system,
      home: Semantics(
        container: true,
        child: ConfigService.isFirstRun()
            ? const WelcomeSetupScreen()
            : AgentOverlayWidget(child: const MainShell()),
      )
    );
  }
}

IconData _getEmotionIcon(String emotion) {
  switch (emotion) {
    case 'neutral': return Icons.sentiment_satisfied;
    case 'happy': return Icons.sentiment_very_satisfied;
    case 'shy': return Icons.face_retouching_natural;
    case 'angry': return Icons.sentiment_very_dissatisfied;
    case 'sad': return Icons.sentiment_dissatisfied;
    case 'excited': return Icons.celebration;
    case 'curious': return Icons.help_outline;
    default: return Icons.sentiment_satisfied;
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  bool _isExtended = true;
  Timer? _timer;

  final _trayChannel = const BasicMessageChannel('bloret/tray', StandardMessageCodec());

  @override
  void initState() {
    super.initState();
    WindowBridge.init(context);

    _trayChannel.setMessageHandler((message) async {
      if (message == null) return null;
      
      switch (message.toString()) {
        case "bbbs":
          launchUrlString("https://bbs.bloret.net/");
          break;
        case "passport":
          launchUrlString("https://passport.bloret.net/");
          break;
        case "img_host":
          launchUrlString("https://img.bloret.net/");
          break;
      }
      return null;
    });

    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (ConfigService.isFirstRun()) {
        Bloriko.getInstance();
      }
      _updateAppIcon();
      final futures = Future.wait([
        BloretApiService.fetchLauncherConfig(),
        BloretApiService.fetchServerInfo("Bloret")
      ]);
      futures.then((value) {
        config = value[0] as BloretLauncherConfig?;
        server = value[1] as BloretServer?;
        setState(() {});
      });
    });
    _timer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      config = await BloretApiService.fetchLauncherConfig();
      server = await BloretApiService.fetchServerInfo("Bloret");
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
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

  final List<dynamic> _pages = [
    (const _NavDestination("主页", Icons.home_outlined, Icons.home), const HomePage()),
    (const _NavDestination("助手", Icons.smart_toy_outlined, Icons.smart_toy), const BloraChatPage()),
    "divider",
    (const _NavDestination("下载", Icons.file_download_outlined, Icons.file_download), const DownloadPage()),
    (const _NavDestination("核心", Icons.view_in_ar_outlined, Icons.view_in_ar), const CoresPage()),
    (const _NavDestination("小工具", Icons.handyman_outlined, Icons.handyman), const ToolsPage()),
    (const _NavDestination("统计", Icons.bar_chart_outlined, Icons.bar_chart), const StatsPage()),
    (const _NavDestination("Mods", Icons.extension_outlined, Icons.extension), const ModsPage()),
    (const _NavDestination("BBBS", Icons.forum_outlined, Icons.forum), const BbbsPage()),
    (const _NavDestination("Live", Icons.live_tv_outlined, Icons.live_tv), const LivePage()),

    "divider",
    (const _NavDestination("通行证", Icons.person_outline, Icons.person), const PassPortPage()),
    (const _NavDestination("设置", Icons.settings_outlined, Icons.settings), const SettingsPage()),
    (const _NavDestination("关于", Icons.info_outline, Icons.info), const AboutPage()),
  ];

  @override
  Widget build(BuildContext context) {
    final isPortrait = MediaQuery.of(context).size.height > MediaQuery.of(context).size.width;

    final userName = ConfigService.get('Bloret_PassPort_UserName') ?? "未登录";
    final avatar = ConfigService.get('Bloret_PassPort_Avatar') ?? "";

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  width: !isPortrait ? (_isExtended ? 240 : 48) : 0,
                  curve: Curves.linearToEaseOut,
                  child: ClipRect(
                    child: OverflowBox(
                      alignment: Alignment.topLeft,
                      minWidth: _isExtended ? 240 : 48,
                      maxWidth: _isExtended ? 240 : 48,
                      child: Row(
                        children: [
                          SizedBox(
                            width: _isExtended ? 239 : 47,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 8),
                                  _NavTile(
                                    icon: Icons.menu,
                                    title: "菜单",
                                    isExtended: false,
                                    isSelected: false,
                                    compact: true,
                                    onTap: () => setState(() => _isExtended = !_isExtended),
                                  ),
                                  const SizedBox(height: 12),
                                  Expanded(
                                    child: ListView.builder(
                                      padding: EdgeInsets.zero,
                                      itemCount: 10,
                                      itemBuilder: (context, index) {
                                        final item = _pages[index];
                                        if (item is String) {
                                          return const Divider(height: 16, indent: 8, endIndent: 8);
                                        }
                                        final dest = item.$1;
                                        return _NavTile(
                                          icon: dest.icon,
                                          selectedIcon: dest.selectedIcon,
                                          title: dest.title,
                                          isExtended: _isExtended,
                                          isSelected: _selectedIndex == index,
                                          onTap: () => setState(() => _selectedIndex = index),
                                        );
                                      },
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Column(
                                      children: [
                                        const Divider(height: 16, indent: 8, endIndent: 8),
                                        _AccountTile(
                                          isExtended: _isExtended,
                                          isSelected: _selectedIndex == 11,
                                          userName: userName,
                                          avatar: avatar,
                                          onTap: () => setState(() => _selectedIndex = 11),
                                        ),
                                        _NavTile(
                                          icon: _pages[12].$1.icon,
                                          title: _pages[12].$1.title,
                                          isExtended: _isExtended,
                                          isSelected: _selectedIndex == 12,
                                          onTap: () => setState(() => _selectedIndex = 12),
                                        ),
                                        _NavTile(
                                          icon: _pages[13].$1.icon,
                                          title: _pages[13].$1.title,
                                          isExtended: _isExtended,
                                          isSelected: _selectedIndex == 13,
                                          onTap: () => setState(() => _selectedIndex = 13),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const VerticalDivider(thickness: 1, width: 1),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    transitionBuilder: (child, animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: isPortrait ? const Offset(0, 0.05) : const Offset(0.02, 0),
                            end: Offset.zero,
                          ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
                          child: child,
                        ),
                      );
                    },
                    child: _pages[_selectedIndex] is String ? const SizedBox.shrink() : _pages[_selectedIndex].$2,
                  ),
                ),
              ],
            ),

            ListenableBuilder(
              listenable: Bloriko.instance,
              builder: (context, child) {
                if (!Bloriko.instance.busy || _selectedIndex == 1) return const SizedBox.shrink();
                
                return Positioned(
                  bottom: isPortrait ? 100 : 100,
                  right: 24,
                  child: TweenAnimationBuilder<double>(
                    duration: const Duration(milliseconds: 400),
                    tween: Tween(begin: 0.0, end: 1.0),
                    curve: Curves.easeOutBack,
                    builder: (context, value, child) => Transform.scale(scale: value, child: child),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedIndex = 1),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(25),
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 10, offset: const Offset(0, 4))],
                            border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Stack(
                                alignment: Alignment.center,
                                children: [
                                  const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2)),
                                  Icon(_getEmotionIcon(Bloriko.instance.emotion), size: 16),
                                ],
                              ),
                              const SizedBox(width: 12),
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(Bloriko.instance.currentTool != null && Bloriko.instance.currentTool! != "set_user_identity"
                                    ? "$agentName正在: ${Bloriko.instance.currentTool}"
                                    : "$agentName 正在运行...",
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onPrimaryContainer)
                                  ),
                                  if (Bloriko.instance.currentTool == null)
                                    Row(
                                      children: [
                                        Text(
                                          switch (Bloriko.instance.connectionStatus) {
                                            BlorikoConnectionStatus.connecting => "正在连接服务器...",
                                            BlorikoConnectionStatus.handshake => "正在验证...",
                                            BlorikoConnectionStatus.streaming => "正在接收响应流...",
                                            BlorikoConnectionStatus.error => "连接异常",
                                            _ => "请稍候...",
                                          },
                                          style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onPrimaryContainer.withValues(alpha: 0.7))
                                        ),
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
        ),
      ),
      bottomNavigationBar: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        height: isPortrait ? 84 : 0,
        child: ClipRect(
          child: isPortrait ? Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(top: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.1))),
            ),
            child: SafeArea(
              top: false,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _pages.length,
                itemBuilder: (context, index) {
                  final item = _pages[index];
                  if (item is String) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Center(child: SizedBox(height: 24, child: VerticalDivider(width: 1))),
                    );
                  }
                  
                  final dest = item.$1;
                  final isSelected = _selectedIndex == index;
                  final theme = Theme.of(context);
                  
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                    child: InkWell(
                      onTap: () => setState(() => _selectedIndex = index),
                      borderRadius: BorderRadius.circular(12),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: isSelected ? theme.colorScheme.primaryContainer.withValues(alpha: 0.4) : Colors.transparent,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              isSelected ? dest.selectedIcon : dest.icon, 
                              color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                              size: 24
                            ),
                            const SizedBox(height: 4),
                            Text(
                              dest.title,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ) : const SizedBox.shrink(),
        ),
      )
    );
  }
}

class _NavTile extends StatelessWidget {
  final IconData icon;
  final IconData? selectedIcon;
  final String title;
  final bool isExtended;
  final bool isSelected;
  final bool compact;
  final VoidCallback onTap;

  const _NavTile({
    required this.icon,
    this.selectedIcon,
    required this.title,
    required this.isExtended,
    required this.isSelected,
    this.compact = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Tooltip(
        message: isExtended ? "" : title,
        waitDuration: const Duration(milliseconds: 500),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            height: 38,
            width: compact ? 40 : null,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              color: isSelected ? theme.colorScheme.secondaryContainer.withValues(alpha: 0.5) : Colors.transparent,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                const SizedBox(width: 10),
                SizedBox(
                  width: 20,
                  child: Icon(isSelected ? (selectedIcon ?? icon) : icon, color: color, size: 20),
                ),
                if (isExtended && !compact) ...[
                  const SizedBox(width: 12),
                  Flexible(
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: isExtended ? 1.0 : 0.0,
                      child: Text(
                        title,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 13,
                          color: color,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        softWrap: false,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  final bool isExtended;
  final bool isSelected;
  final String userName;
  final String avatar;
  final VoidCallback onTap;

  const _AccountTile({
    required this.isExtended,
    required this.isSelected,
    required this.userName,
    required this.avatar,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Tooltip(
        message: isExtended ? "" : userName,
        waitDuration: const Duration(milliseconds: 500),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              color: isSelected ? theme.colorScheme.secondaryContainer.withValues(alpha: 0.5) : Colors.transparent,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                const SizedBox(width: 6),
                SizedBox(
                  width: 28,
                  height: 28,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: avatar.isNotEmpty && ConfigService.get('Bloret_PassPort_Login') == true
                        ? CachedNetworkImage(imageUrl: avatar, fit: BoxFit.cover, errorWidget: (_,__,___) => const Icon(Icons.account_circle, size: 28), progressIndicatorBuilder: (_, _, loadingProgress) => const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 4),))
                        : Container(
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: const Icon(Icons.person, size: 18),
                          ),
                  ),
                ),
                if (isExtended) ...[
                  const SizedBox(width: 10),
                  Flexible(
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: isExtended ? 1.0 : 0.0,
                      child: Text(
                        ConfigService.get('Bloret_PassPort_Login') == true ? userName : "登录",
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: isSelected ? theme.colorScheme.primary : null,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        softWrap: false,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
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
  final List<String> sentences = config?.blTips ?? [];
  final TextEditingController homeInputController = TextEditingController();
  Timer? timer;

  @override
  void initState() {
    super.initState();
    _listController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _listController.forward();
    timer = Timer.periodic(const Duration(seconds: 5), (timer) {
      setState(() {});
      if (sentences.isNotEmpty) {
        return;
      }
      setState(() {
        sentences.addAll(config?.blTips ?? []);
      });
    });
  }

  @override
  void dispose() {
    _listController.dispose();
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPortrait = MediaQuery.of(context).size.height > MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(left: 36, top: 24, bottom: 24, right: 24),
              children: [
                SlideFadeIn(
                  controller: _listController,
                  delay: 0,
                  child: isPortrait 
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("$name Launcher",
                              style: theme.textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          SlidingTextCycle(
                            sentences: sentences.map((e) => e.replaceAll("Windows 11", "Android")).map((e) => e.replaceAll("RinUI", "Flutter")).toList()..add("络可好き好き"),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.outline,
                              fontWeight: FontWeight.w500,
                            ) ?? const TextStyle(),
                          ),
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text("$name Launcher",
                              style: theme.textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: SlidingTextCycle(
                              sentences: sentences.map((e) => e.replaceAll("Windows 11", "Android")).map((e) => e.replaceAll("RinUI", "Flutter")).toList()..add("络可好き好き"),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.outline,
                                fontWeight: FontWeight.w500,
                              ) ?? const TextStyle(),
                            ),
                          ),
                        ],
                      ),
                ),
                const SizedBox(height: 24),

                SlideFadeIn(
                  controller: _listController,
                  delay: 0.4,
                  child: ListenableBuilder(
                    listenable: Bloriko.instance,
                    builder: (context, child) {
                      final isBusy = Bloriko.instance.busy;
                      return Row(
                        children: [
                          const CircleAvatar(radius: 20, backgroundColor: Colors.blueGrey),
                          const SizedBox(width: 12),
                          Expanded(
                            child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final isShort = constraints.maxWidth < 300;
                                  final identityId = ConfigService.get("user_identity");
                                  final identity = identityId == "sister" ? "姐姐" : identityId == "little_sister" ? "妹妹" : "哥哥";
                                  
                                  String hintText;
                                  if (isBusy) {
                                    hintText = isShort ? "正在思考..." : "$agentName 正在思考中...";
                                  } else {
                                    if (isShort) {
                                      hintText = "向 $agentName 提问...";
                                    } else {
                                      hintText = "关于 Minecraft 的任何问题，可以问 $agentName 哦${Bloriko.type == "bloriko" ? "，$identity ~" : ""}";
                                    }
                                  }

                                  return TextField(
                                    controller: homeInputController,
                                    onSubmitted: isBusy ? null : (value) {
                                      if (Platform.isAndroid) return;
                                      if (value.trim().isNotEmpty) {
                                        Bloriko.instance.startNewSession(value.trim());
                                        context.findAncestorStateOfType<_MainShellState>()?.setState(() {
                                          context.findAncestorStateOfType<_MainShellState>()?._selectedIndex = 1;
                                        });
                                      }
                                    },
                                    decoration: InputDecoration(
                                      hintText: hintText,
                                      isDense: true,
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                                    ),
                                  );
                                }
                            ),
                          ),
                          const SizedBox(width: 12),
                          IconButton.filled(
                            onPressed: isBusy ? null : () {
                              final value = homeInputController.text.trim();
                              if (value.isNotEmpty) {
                                Bloriko.instance.startNewSession(value);
                                context.findAncestorStateOfType<_MainShellState>()?.setState(() {
                                  context.findAncestorStateOfType<_MainShellState>()?._selectedIndex = 1;
                                });
                              }
                            }, 
                            icon: isBusy 
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70))
                              : const Icon(Icons.send)
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                SlideFadeIn(
                  controller: _listController,
                  delay: 0.5,
                  child: Text("$agentName 依靠 AI。可能犯错，请核实重要信息。",
                      style: theme.textTheme.bodySmall?.copyWith(fontSize: 14)),
                ),

                const SizedBox(height: 32),
                SlideFadeIn(
                  controller: _listController,
                  delay: 0.6,
                  child: Text("信息", style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 12),

                SlideFadeIn(
                  controller: _listController,
                  delay: 0.7,
                  child: FluentCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Image.asset(Theme.of(context).brightness == Brightness.dark ? "assets/bloret_dark.png" : "assets/bloret_light.png", width: 48, height: 48, fit: BoxFit.cover,),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Text("Bloret", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                      const Spacer(),
                                      if (server?.links != null) Text(server?.url ?? "", style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
                                      const SizedBox(width: 8),
                                      if (server != null && server?.realTimeStatus != null && server?.realTimeStatus?.online == true) Text("${server?.realTimeStatus?.playersOnline ?? 0} / ${server?.realTimeStatus?.playersMax ?? 0}", style: theme.textTheme.bodySmall),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      SizedBox(width: 16, height: 16, child: Image.asset("assets/icons/mc_be.png"),),
                                      const SizedBox(width: 8),
                                      Text("Bloret 百络谷 ${server?.text == null ? "" : "| ${server?.text}"}", style: theme.textTheme.bodySmall),
                                    ],
                                  )
                                ],
                              ),
                            )
                          ],
                        ),
                        const Divider(height: 24),
                        Text("$agentName 推荐时间段", style: const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          transitionBuilder: (child, animation) {
                            final sizeAnimation = CurvedAnimation(
                              parent: animation,
                              curve: const Interval(0.0, 1.0, curve: Curves.easeOutBack),
                            );

                            final fadeAnimation = CurvedAnimation(
                              parent: animation,
                              curve: const Interval(0.3, 1.0, curve: Curves.easeIn),
                            );

                            return FadeTransition(
                              opacity: fadeAnimation,
                              child: SizeTransition(
                                sizeFactor: sizeAnimation,
                                alignment: Alignment.centerLeft,
                                child: child,
                              ),
                            );
                          },
                          child: server != null 
                            ? KeyedSubtree(key: ValueKey(server != null), child: GptMarkdown(server?.bestTime ?? "...", style: theme.textTheme.bodySmall)) 
                            : Row(
                                key: ValueKey(server != null), 
                                mainAxisSize: MainAxisSize.min, 
                                children: [
                                  Expanded(child: Text("嘿嘿~ $agentName 来啦！现在的在线人数非常适合游玩哦~", style: theme.textTheme.bodySmall)),
                                  const SizedBox(width: 8), 
                                  const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                                  const SizedBox(width: 4,)
                                ],
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
                SlideFadeIn(
                  controller: _listController,
                  delay: 0.8,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 12),
                      Text("Bloret Server 数据信息提供自 百络谷查服网", style: TextStyle(color: Theme.of(context).colorScheme.outline)),
                    ],
                  ),
                )
              ],
            ),
          ),
          _BottomActionRail(),
        ],
      ),
    );
  }
}

Widget buildSimpleMarkdownText(String text, {TextStyle? style}) {
  final List<InlineSpan> spans = [];
  final RegExp exp = RegExp(r'\*\*(.*?)\*\*');

  int lastMatchEnd = 0;

  for (final Match match in exp.allMatches(text)) {
    if (match.start > lastMatchEnd) {
      spans.add(TextSpan(
        text: text.substring(lastMatchEnd, match.start),
        style: style,
      ));
    }

    spans.add(TextSpan(
      text: match.group(1),
      style: (style ?? const TextStyle()).copyWith(
        fontWeight: FontWeight.bold,
      ),
    ));

    lastMatchEnd = match.end;
  }

  if (lastMatchEnd < text.length) {
    spans.add(TextSpan(
      text: text.substring(lastMatchEnd),
      style: style,
    ));
  }

  return Text.rich(TextSpan(children: spans));
}

class SlideFadeIn extends StatelessWidget {
  final Widget child;
  final double delay;
  final AnimationController controller;

  const SlideFadeIn({super.key, required this.child, required this.delay, required this.controller});

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

class FluentCard extends StatelessWidget {
  final Widget child;
  const FluentCard({super.key, required this.child});

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
    final isPortrait = MediaQuery.of(context).size.height > MediaQuery.of(context).size.width;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      height: isPortrait ? 140 : 90,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.8),
        border: Border(top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.1))),
      ),
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: isPortrait 
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(color: theme.colorScheme.primaryContainer, borderRadius: BorderRadius.circular(8)),
                        child: const Icon(Icons.inventory_2, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("1.20.1-Forge-47.2.0", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            Text("以身份 Bloret 启动 Minecraft", style: theme.textTheme.bodySmall?.copyWith(fontSize: 11)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      BloretIconButton(
                        icon: Icons.settings,
                        tooltip: "核心设置",
                        onPressed: () {},
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: BloretButton(
                          onPressed: () {},
                          icon: Icons.swap_horiz, 
                          text: "切换核心",
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: BloretButton(
                          onPressed: () {},
                          icon: Icons.play_arrow,
                          text: "启动游戏",
                        ),
                      ),
                    ],
                  ),
                ],
              )
            : Row(
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
                  BloretIconButton(
                    icon: Icons.folder_open,
                    tooltip: "游戏目录",
                    onPressed: () {},
                  ),
                  const SizedBox(width: 12),
                  BloretButton(
                    onPressed: () {},
                    icon: Icons.swap_horiz, 
                    text: "切换核心",
                    height: 48,
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    height: 44,
                    width: 140,
                    child: BloretButton(
                      onPressed: () {},
                      icon: Icons.play_arrow,
                      text: "启动游戏",
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
  bool _displayUuid = true;
  bool _isWaitingForLogin = false;
  HttpServer? _authServer;
  int _actualPort = 25252;
  final ValueNotifier<bool> _isTokenValidNotifier = ValueNotifier<bool>(false);

  Map<String, dynamic> _getAccountData() {
    final data = ConfigService.get('MinecraftAccount');
    if (data == null) return {"logined": false, "chosen": -1, "accounts": []};
    if (data is String) return jsonDecode(data);
    return data as Map<String, dynamic>;
  }

  void _syncStateToUi() {
    if (mounted) {
      setState(() {
        final bool loggedIn = ConfigService.get('Bloret_PassPort_Login') ?? false;
        if (loggedIn) {
          _isWaitingForLogin = false;
        }
      });
    }
  }

  Future<void> _loginBloretPassPort() async {
    await _startAuthServer();
    final url = Uri.parse('https://passport.bloret.net/app/oauth?app_id=BloretLauncher&redirect_uri=http://localhost:$_actualPort/login/Bloret-PassPort');
    if (await canLaunchUrl(url)) {
      await launchUrl(
          url,
          mode: Platform.isAndroid ? LaunchMode.inAppBrowserView : LaunchMode.externalApplication
      );
      setState(() => _isWaitingForLogin = true);
    }
  }

  Future<void> _startAuthServer() async {
    await _authServer?.close(force: true);
    try {
      _authServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 25252);
      _actualPort = 25252;
    } catch (_) {
      _authServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _actualPort = _authServer!.port;
    }

    _authServer!.listen((HttpRequest request) async {
      if (request.uri.path == '/login/Bloret-PassPort') {
        final params = request.uri.queryParameters;
        final code = params['code'];

        if (code != null) {
          final userInfo = await PassportService.verifyCode(code);
          if (userInfo != null) {
            await ConfigService.set('Bloret_PassPort_Login', true);
            await ConfigService.set('Bloret_PassPort_UserName', userInfo['username']);
            await ConfigService.set('Bloret_PassPort_Avatar', userInfo['avatar']);
            await ConfigService.set('Bloret_PassPort_Email', userInfo['email']);
            await ConfigService.set('Bloret_PassPort_Token', userInfo['apptoken']);
            await ConfigService.set('Bloret_PassPort_BBBS_Session', userInfo['bbbs_session']);
            await ConfigService.set('Bloret_PassPort_BBBS_Session.sig', userInfo['bbbs_session.sig']);

            final syncResult = await PassportService.syncMinecraftAccounts();
            _isTokenValidNotifier.value = syncResult;
            _syncStateToUi();
          } else {
            _isTokenValidNotifier.value = false;
          }
          setState(() {});

          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.html
            ..write('''
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>登录成功</title>
    <style>
        * {
            box-sizing: border-box;
            margin: 0;
            padding: 0;
        }
        body {
            display: flex;
            justify-content: center;
            align-items: center;
            height: 100vh;
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
            background-color: #121212;
            color: #ffffff;
            overflow: hidden;
        }
        .container {
            text-align: center;
            padding: 48px;
            background: #1e1e1e;
            border-radius: 24px;
            box-shadow: 0 12px 40px rgba(0, 0, 0, 0.5);
            border: 1px solid rgba(255, 255, 255, 0.05);
            max-width: 400px;
            width: 90%;
            animation: fadeIn 0.6s cubic-bezier(0.16, 1, 0.3, 1);
        }
        .icon-wrapper {
            position: relative;
            width: 80px;
            height: 80px;
            margin: 0 auto 24px;
        }
        .success-pulse {
            position: absolute;
            width: 100%;
            height: 100%;
            background: rgba(159, 168, 218, 0.2);
            border-radius: 50%;
            animation: pulse 2s infinite;
        }
        .success-icon {
            position: absolute;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
            background: #9FA8DA;
            border-radius: 50%;
            display: flex;
            justify-content: center;
            align-items: center;
            box-shadow: 0 4px 20px rgba(159, 168, 218, 0.4);
        }
        .success-icon svg {
            width: 40px;
            height: 40px;
            fill: none;
            stroke: #121212;
            stroke-width: 4;
            stroke-linecap: round;
            stroke-linejoin: round;
            stroke-dasharray: 100;
            stroke-dashoffset: 100;
            animation: drawCheck 0.6s 0.3s forwards cubic-bezier(0.16, 1, 0.3, 1);
        }
        h1 {
            font-size: 24px;
            font-weight: 600;
            margin-bottom: 12px;
            letter-spacing: 0.5px;
        }
        p {
            font-size: 14px;
            color: rgba(255, 255, 255, 0.5);
            line-height: 1.6;
        }
        @keyframes fadeIn {
            from { opacity: 0; transform: translateY(20px); }
            to { opacity: 1; transform: translateY(0); }
        }
        @keyframes pulse {
            0% { transform: scale(0.95); opacity: 0.5; }
            50% { transform: scale(1.2); opacity: 0; }
            100% { transform: scale(0.95); opacity: 0; }
        }
        @keyframes drawCheck {
            to { stroke-dashoffset: 0; }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="icon-wrapper">
            <div class="success-pulse"></div>
            <div class="success-icon">
                <svg viewBox="0 0 24 24">
                    <polyline points="20 6 9 17 4 12"></polyline>
                </svg>
            </div>
        </div>
        <h1>Bloret PassPort 授权成功</h1>
        <p>您现在可以安全地关闭此窗口并返回 Launcher 继续设置。</p>
    </div>
</body>
</html>
''')
            ..close();

          await _authServer?.close();
          _authServer = null;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLoggedIn = ConfigService.get('Bloret_PassPort_Login') ?? false;
    final userName = ConfigService.get('Bloret_PassPort_UserName') ?? "访客";
    final avatar = ConfigService.get('Bloret_PassPort_Avatar') ?? "";
    final accountData = _getAccountData();
    // fuck
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
          FluentCard(
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: avatar.isNotEmpty && isLoggedIn
                      ? CachedNetworkImage(imageUrl: avatar, width: 48, height: 48, fit: BoxFit.cover, )
                      : SizedBox(width: 48, height: 48, child: Image.asset(Theme.of(context).brightness == Brightness.dark ? "assets/bloret_dark.png" : "assets/bloret_light.png")),
                ),
                const SizedBox(width: 16),
                Expanded(child: Text(userName, style: const TextStyle(fontWeight: FontWeight.w700))),
                if (!isLoggedIn)
                  BloretButton(
                    onPressed: () async {
                      await _loginBloretPassPort();
                    },
                    text: _isWaitingForLogin ? "等待登录..." : "登录",
                  )
                else
                  BloretButton(
                    onPressed: () async {
                      await ConfigService.set('Bloret_PassPort_Login', false);
                      await ConfigService.set('Bloret_PassPort_UserName', '');
                      await ConfigService.set('Bloret_PassPort_PassWord', '');
                      accounts.clear();
                      setState(() {});
                    },
                    text: "退出登录",
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
                const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              IconButton(
                onPressed: () {
                  setState(() => _displayUuid = !_displayUuid);
                },
                icon: !_displayUuid ? const Icon(Icons.visibility_off) : const Icon(Icons.visibility),
              )
            ],
          ),
          const SizedBox(height: 12),
          if (!isLoggedIn)
            const Center(child: Padding(padding: EdgeInsets.all(20), child: Text("您还未登录，请先登录", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 40))))
          else if (accounts.isEmpty)
            const Center(child: Padding(padding: EdgeInsets.all(20), child: Text("暂无账户，请从云端同步", style: TextStyle(fontWeight: FontWeight.w600))))
          else
            ...accounts.asMap().entries.map((entry) {
              final index = entry.key;
              final account = entry.value;
              final isDefault = accountData['chosen'] == index;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: FluentCard(
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: CachedNetworkImage(imageUrl: account['avatarUrl'] ?? "https://mc-heads.net/avatar/${account['uuid']}/32", width: 32, height: 32, errorWidget: (_, __, ___) => const Icon(Icons.account_circle, size: 32)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    account['username'] ?? "Unknown",
                                    style: const TextStyle(fontWeight: FontWeight.w700),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (_displayUuid && account['uuid'] != null)
                                  Flexible(
                                    child: Padding(
                                      padding: const EdgeInsets.only(left: 6),
                                      child: Text(
                                        "(${account['uuid']})",
                                        style: theme.textTheme.bodySmall?.copyWith(fontSize: 10, color: theme.colorScheme.outline),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            Text(account['type'] ?? "Offline", style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      BloretButton(
                        onPressed: isDefault ? null : () async {
                          final newData = Map<String, dynamic>.from(accountData);
                          newData['chosen'] = index;
                          await ConfigService.set('MinecraftAccount', jsonEncode(newData));
                          setState(() {});
                        },
                        text: isDefault ? "正在使用" : "使用此账户",
                      ),
                    ],
                  ),
                ),
              );
            }),
          if (isLoggedIn) ...[
            const SizedBox(height: 32),
            FluentCard(
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
                        onPressed: () {
                          launchUrlString("https://passport.bloret.net/minecraft");
                        },
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
          ]
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
              Text(config?.latestVersion ?? "--", style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold)),
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
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }
}
