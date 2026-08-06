import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import '../core/i18n.dart';
import '../core/logger.dart';
import '../core/global.dart';
import '../main.dart';
import '../services/bloriko.dart';
import '../services/config_service.dart';
import '../services/launch_service.dart';
import '../shell/main_shell.dart';
import '../widgets/button.dart';
import '../widgets/google_widgets.dart';
import '../widgets/sliding_text.dart';

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

  // Launch state
  bool _isLaunching = false;
  double _launchProgress = 0.0;
  String _launchStatus = "";
  String? _launchError;
  final List<String> _launchLogs = [];
  final ScrollController _logScrollController = ScrollController();

  void _parseLogForProgress(String line) {
    if (line.contains("FabricLoader") || line.contains("Forge Mod Loader") || line.contains("NeoForge")) {
      _updateLaunchInfo("正在初始化模组加载器...".tl, 0.1);
    } else if (line.contains("Setting user:")) {
      _updateLaunchInfo("正在验证身份并准备环境...".tl, 0.2);
    } else if (line.contains("Initializing Game")) {
      _updateLaunchInfo("正在初始化游戏引擎...".tl, 0.3);
    } else if (line.contains("OpenAL initialized")) {
      _updateLaunchInfo("音频系统已就绪".tl, 0.4);
    } else if (line.contains("Sound engine started")) {
      _updateLaunchInfo("正在加载音频资源...".tl, 0.5);
    } else if (line.contains("Created: ") && line.contains("x")) {
      _updateLaunchInfo("正在创建游戏窗口...".tl, 0.65);
    } else if (line.contains("Reloading ResourceManager")) {
      _updateLaunchInfo("正在加载资源包与数据包...".tl, 0.8);
    } else if (line.contains("ModelManager") || line.contains("Building models")) {
      _updateLaunchInfo("正在渲染 3D 模型...".tl, 0.88);
    } else if (line.contains("TextureAtlas") || line.contains("Stitching")) {
      _updateLaunchInfo("正在优化贴图纹理...".tl, 0.95);
    }
  }

  void _updateLaunchInfo(String status, double progress) {
    if (mounted && progress > _launchProgress) {
      setState(() {
        _launchStatus = status;
        _launchProgress = progress;
      });
    }
  }

  void _addLog(String line) {
    if (!mounted) return;
    setState(() {
      _launchLogs.add(line);
      if (_launchLogs.length > 500) _launchLogs.removeAt(0);
    });
    
    // Auto scroll to bottom
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollController.hasClients) {
        _logScrollController.animateTo(
          _logScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

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

  Future<void> _startLaunch() async {
    setState(() {
      _isLaunching = true;
      _launchError = null;
      _launchProgress = 0.0;
      _launchStatus = "正在准备启动...".tl;
      _launchLogs.clear();
    });

    try {
      final process = await LaunchService.instance.launch(
        version: "1.21.8",
        minecraftDir: r"C:\Users\Administrator\AppData\Roaming\.minecraft\1.21.8-main",
        onStatus: (status, progress) {
          if (mounted) {
            setState(() {
              _launchStatus = status;
              _launchProgress = progress;
            });
          }
        },
      );

      final logger = await AppLogger.getInstance();
      
      process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
        _addLog(line);
        _parseLogForProgress(line);
        logger.log(line, source: LogSource.tool, level: LogLevel.info);
      });

      process.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
        _addLog(line);
        _parseLogForProgress(line);
        logger.log(line, source: LogSource.tool, level: LogLevel.error);
      });

      if (mounted) {
        setState(() {
          _launchStatus = "游戏已启动，祝你玩得愉快！";
          _launchProgress = 1.0;
        });
      }

      // Hide launching overlay after a delay
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _isLaunching = false;
          });
        }
      });

      process.exitCode.then((code) {
        debugPrint("Minecraft exited with code $code");
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _launchError = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPortrait = MediaQuery.of(context).size.height > MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 600),
        switchInCurve: Curves.easeInOutCubic,
        switchOutCurve: Curves.easeInOutCubic,
        transitionBuilder: (Widget child, Animation<double> animation) {
          return FadeTransition(opacity: animation, child: child);
        },
        child: _isLaunching ? _buildLaunchingLayout(theme, isPortrait) : _buildNormalLayout(theme, isPortrait),
      ),
    );
  }

  Widget _buildNormalLayout(ThemeData theme, bool isPortrait) {
    return Column(
      key: const ValueKey("normal_home"),
      children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.only(left: Platform.isAndroid ? 24 : 36, top: 24, bottom: 24, right: 24),
            children: [
              SlideFadeIn(
                controller: _listController,
                delay: 0,
                child: Hero(
                  tag: "header_title",
                  child: Material(
                    color: Colors.transparent,
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
                ),
              ),
              const SizedBox(height: 24),
              SlideFadeIn(
                controller: _listController,
                delay: 0.4,
                child: Hero(tag: "bloriko_agent", child: _buildAgentInput(theme)),
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
                child: Hero(tag: "server_card", child: _buildServerCard(theme)),
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
        _BottomActionRail(onLaunch: _startLaunch),
      ],
    );
  }

  Widget _buildLaunchingLayout(ThemeData theme, bool isPortrait) {
    return Container(
      key: const ValueKey("launching_home"),
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          // Left: Original Widgets (Scaled down)
          Expanded(
            flex: 2,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Hero(
                    tag: "header_title",
                    child: Material(
                      color: Colors.transparent,
                      child: Text("$name Launcher", style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Hero(tag: "bloriko_agent", child: _buildAgentInput(theme)),
                  const SizedBox(height: 16),
                  Hero(tag: "server_card", child: _buildServerCard(theme)),
                  const SizedBox(height: 32),
                  // Progress Section
                  if (_launchError == null) ...[
                    GoogleSquigglySlider(value: _launchProgress * 100, max: 100),
                    const SizedBox(height: 12),
                    Text(_launchStatus, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  ] else ...[
                    Icon(Icons.error_outline, color: Colors.red, size: 48),
                    const SizedBox(height: 12),
                    Text("启动失败", style: theme.textTheme.titleMedium?.copyWith(color: Colors.red, fontWeight: FontWeight.bold)),
                    Text(_launchError!, style: theme.textTheme.bodySmall),
                    const SizedBox(height: 12),
                    BloretButton(onPressed: () => setState(() => _isLaunching = false), text: "返回主页"),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 24),
          // Right: Real-time Log Window
          Expanded(
            flex: 3,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.dividerColor.withValues(alpha: 0.1)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        color: Colors.white.withValues(alpha: 0.05),
                        child: Row(
                          children: [
                            const Icon(Icons.terminal, size: 16, color: Colors.white70),
                            const SizedBox(width: 8),
                            const Text("游戏输出日志", style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                            const Spacer(),
                            Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.greenAccent, shape: BoxShape.circle)),
                            const SizedBox(width: 4),
                            const Text("RUNNING", style: TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          controller: _logScrollController,
                          padding: const EdgeInsets.all(12),
                          itemCount: _launchLogs.length,
                          itemBuilder: (context, index) => Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Text(
                              _launchLogs[index],
                              style: const TextStyle(
                                color: Colors.white,
                                fontFamily: 'monospace',
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAgentInput(ThemeData theme) {
    return ListenableBuilder(
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
    );
  }

  Widget _buildServerCard(ThemeData theme) {
    return FluentCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Image.asset(theme.brightness == Brightness.dark ? "assets/bloret_dark.png" : "assets/bloret_light.png", width: 48, height: 48, fit: BoxFit.cover,),
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
                parent: animation, curve: const Interval(0.0, 1.0, curve: Curves.easeOutBack));
              final fadeAnimation = CurvedAnimation(
                parent: animation, curve: const Interval(0.3, 1.0, curve: Curves.easeIn));
              return FadeTransition(
                opacity: fadeAnimation,
                child: SizeTransition(sizeFactor: sizeAnimation, alignment: Alignment.centerLeft, child: child));
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
    );
  }
}

class _BottomActionRail extends StatelessWidget {
  final VoidCallback onLaunch;
  const _BottomActionRail({required this.onLaunch});

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
                      onPressed: onLaunch,
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
                  onPressed: onLaunch,
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