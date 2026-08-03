import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:ai_flutter_agent/ai_flutter_agent.dart';
import 'package:bloret_launcher/core/logger.dart';
import 'package:bloret_launcher/services/bloriko.dart';
import 'package:bloret_launcher/services/memory.dart';
import 'package:bloret_launcher/services/notice_manager.dart';
import 'package:bloret_launcher/services/update_manager.dart';
import 'package:bloret_launcher/shell/main_shell.dart';
import 'package:bloret_launcher/tools/server_info.dart';
import 'package:bloret_launcher/widgets/button.dart';
import 'package:bloret_launcher/widgets/sliding_text.dart';
import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'core/global.dart';
import 'services/config_service.dart';
import 'services/win32_icon_service.dart';
import 'pages/welcome_page.dart';

BloraLauncherConfig? config;

BloretServer? server;

const name = "Blora";

late final AppLogger logger;

late final UpdateManager updateManager;

final NoticeManager noticeManager = NoticeManager.instance;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ConfigService.init();
  logger = await AppLogger.getInstance();
  Win32IconService.init();
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return const SizedBox.shrink();
  };
  Bloriko.getInstance();
  await MemoryStore.instance.loadOnInit();
  updateManager = await UpdateManager.instance.init();
  runApp(const BloraLauncherApp());
}

class BloraLauncherApp extends StatelessWidget {
  const BloraLauncherApp({super.key});

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
              padding: EdgeInsets.only(left: Platform.isAndroid ? 24 : 36, top: 24, bottom: 24, right: 24),
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
                                        context.findAncestorStateOfType<MainShellState>()?.setState(() {
                                          context.findAncestorStateOfType<MainShellState>()?.selectedIndex = 1;
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
                                context.findAncestorStateOfType<MainShellState>()?.setState(() {
                                  context.findAncestorStateOfType<MainShellState>()?.selectedIndex = 1;
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
                      const Text("26.2", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text("以身份 ${jsonDecode(ConfigService.get("MinecraftAccountList")[ConfigService.get("MinecraftAccount_Chosen") ?? 0])["username"] ?? "None"} 启动 Minecraft", style: theme.textTheme.bodySmall),
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
