import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:dio/dio.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../core/i18n.dart';
import '../core/logger.dart';
import '../core/global.dart';
import '../core/grammer_candy.dart';
import '../core/ffi_proxy.dart';
import '../main.dart';
import '../services/bloriko.dart';
import '../services/config_service.dart';
import '../services/launch_service.dart';
import '../services/passport_service.dart';
import '../shell/main_shell.dart';
import '../widgets/button.dart';
import '../widgets/sliding_text.dart';

enum HomeState { normal, launching, running }

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  late AnimationController _listController;
  late AnimationController _chartAnimationController;
  late PageController _pageController;
  final List<String> sentences = config?.blTips ?? [];
  final TextEditingController homeInputController = TextEditingController();
  Timer? timer;

  HomeState _homeState = HomeState.normal;
  bool _showRunningHandle = false;
  bool _isHandleExtended = false;
  bool _showLogsInRunning = false;

  String? _selectedVersion;
  String? _selectedVersionDir;

  RunningCore? _selectedCore;

  double _launchProgress = 0.0;
  String _launchStatus = "";
  String? _launchError;
  final ScrollController _logScrollController = ScrollController();

  bool get _isChinese => ConfigService.getLanguage().toLowerCase().startsWith("zh");

  bool get _showTranslatedTips => TranslationStore.showTranslated;
  List<String>? get _translatedSentences => TranslationStore.translatedTips;
  bool _isTranslating = false;

  bool get _showTranslatedServer => TranslationStore.showTranslated;
  String? get _translatedServerBestTime => TranslationStore.translatedServerBestTime;
  String? get _translatedServerText => TranslationStore.translatedServerText;
  bool _apiAvailable = false;

  Future<void> _checkApi() async {
    for (int i = 0; i < 5; i++) {
      try {
        final dio = Dio();
        final response = await dio.get(
          "https://translate.googleapis.com/translate_a/single",
          queryParameters: {
            "client": "gtx",
            "sl": "auto",
            "tl": "zh-CN",
            "dt": "t",
            "q": "ping",
          },
        ).timeout(const Duration(seconds: 3));

        if (mounted) {
          setState(() {
            _apiAvailable = response.statusCode == 200;
          });
          if (_apiAvailable) return;
        }
      } catch (_) {}
      await Future.delayed(const Duration(seconds: 1));
    }
  }

  Future<String> _googleTranslate(String text) async {
    try {
      String lang = ConfigService.getLanguage().toLowerCase();
      if (lang.contains("zh_tw") || lang.contains("zh_hk")) {
        lang = "zh-TW";
      } else if (lang.contains("zh")) {
        lang = "zh-CN";
      } else {
        lang = lang.split('_').first;
      }

      // Use placeholders to protect brands from being merged or mistranslated
      // Add protection for JP/RU variants as well
      final source = text
          .replaceAll("百络谷", "___BLORET_P___")
          .replaceAll("络可", "___BLORIKO_P___")
          .replaceAll("ロコ", "___BLORIKO_P___")
          .replaceAll("Блорико", "___BLORIKO_P___")
          .replaceAll("Blora", "___BLORA_P___");

      final response = await Dio().get(
        "https://translate.googleapis.com/translate_a/single",
        queryParameters: {
          "client": "gtx",
          "sl": "auto",
          "tl": lang,
          "dt": "t",
          "q": source,
        },
      );

      if (response.statusCode == 200 && response.data is List) {
        final List parts = response.data[0];
        var result = parts.map((p) => p[0]).join();

        // Robust restoration function that handles spaces and case changes
        String restore(String content, String placeholder, String brand) {
          final escaped = placeholder.replaceAll('_', r'[_ ]*');
          return content.replaceAll(RegExp(escaped, caseSensitive: false), brand);
        }

        result = restore(result, "___BLORET_P___", "Bloret");
        result = restore(result, "___BLORIKO_P___", "Bloriko");
        result = restore(result, "___BLORA_P___", "Blora");
        result = result.replaceAll("___BLORET_P___", "Bloret");

        return result;
      }
    } catch (e) {
      logger.error("Google Translation Error: $e", LogSource.network);
    }
    return text;
  }

  Future<void> _toggleTranslation() async {
    // If translations exist and match current state, just toggle visibility
    bool langMatch = TranslationStore.lastLang == ConfigService.getLanguage();
    bool tipsMatch = _translatedSentences != null && _translatedSentences!.length == sentences.length && TranslationStore.lastTipsHash == sentences.hashCode;
    bool serverMatch = _translatedServerBestTime != null;

    if (langMatch && tipsMatch && serverMatch) {
      setState(() {
        TranslationStore.showTranslated = !TranslationStore.showTranslated;
      });
      return;
    }

    setState(() => _isTranslating = true);
    final currentLang = ConfigService.getLanguage();
    try {
      final List<Future> tasks = [];
      if (sentences.isNotEmpty) {
        tasks.add(() async {
          final results = await Future.wait(
            sentences.map((s) => _googleTranslate(s)),
          );
          TranslationStore.translatedTips = results;
          TranslationStore.lastTipsHash = sentences.hashCode;
        }());
      }
      tasks.add(() async {
        final List<Future<String>> serverTasks = [];
        if (server?.bestTime != null) {
          serverTasks.add(_googleTranslate(server!.bestTime));
        }
        if (server?.text != null) {
          serverTasks.add(_googleTranslate(server!.text));
        }
        
        if (serverTasks.isNotEmpty) {
          final results = await Future.wait(serverTasks);
          int idx = 0;
          if (server?.bestTime != null) TranslationStore.translatedServerBestTime = results[idx++];
          if (server?.text != null) TranslationStore.translatedServerText = results[idx++];
        }
      }());

      await Future.wait(tasks);
      TranslationStore.lastLang = currentLang;
      setState(() {
        TranslationStore.showTranslated = true;
      });
    } catch (e) {
      logger.error("Translate error: $e", LogSource.system);
    } finally {
      setState(() => _isTranslating = false);
    }
  }

  void _onLanguageChanged() {
    if (TranslationStore.showTranslated && TranslationStore.translatedTips == null && !_isTranslating) {
      _toggleTranslation();
    }
  }

  Widget _buildTranslateButton({required bool isTranslating, required VoidCallback onPressed, required bool isTranslated}) {
    return IconButton(
      onPressed: isTranslating ? null : onPressed,
      icon: isTranslating
          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(isTranslated ? Icons.translate : Icons.translate_outlined, size: 16, color: isTranslated ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outline),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      visualDensity: VisualDensity.compact,
      tooltip: "Translate".tl,
    );
  }

  void _parseLogForProgress(String line) {
    if (line.contains("FabricLoader") || line.contains("Forge Mod Loader") || line.contains("NeoForge")) {
      _updateLaunchInfo("Initializing mod loader...".tl, 0.1);
    } else if (line.contains("Setting user:")) {
      _updateLaunchInfo("Verifying identity and preparing environment...".tl, 0.2);
    } else if (line.contains("Initializing Game")) {
      _updateLaunchInfo("Initializing game engine...".tl, 0.3);
    } else if (line.contains("OpenAL initialized")) {
      _updateLaunchInfo("Audio system ready".tl, 0.4);
    } else if (line.contains("Sound engine started")) {
      _updateLaunchInfo("Loading audio resources...".tl, 0.5);
    } else if (line.contains("Created: ") && line.contains("x")) {
      _updateLaunchInfo("Creating game window...".tl, 0.65);
    } else if (line.contains("Reloading ResourceManager")) {
      _updateLaunchInfo("Loading resource packs and data packs...".tl, 0.8);
    } else if (line.contains("ModelManager") || line.contains("Building models")) {
      _updateLaunchInfo("Rendering 3D models...".tl, 0.88);
    } else if (line.contains("TextureAtlas") || line.contains("Stitching")) {
      _updateLaunchInfo("Optimizing textures...".tl, 0.95);
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

  @override
  void initState() {
    super.initState();
    _checkApi();
    _loadSelectedVersion();
    I18n.instance.addListener(_onLanguageChanged);
    
    // Resume selected core if any exists in manager
    if (CoreManager.instance.runningCores.isNotEmpty) {
      _selectedCore = CoreManager.instance.runningCores.last;
      _showRunningHandle = true;
    }

    _listController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _chartAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _pageController = PageController();
    _listController.forward();
    // Pre-initialize stats for a clean layout
    _startStatsMonitoring();
    timer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (config != null && sentences.length != config!.blTips.length) {
        setState(() {
          sentences.clear();
          sentences.addAll(config!.blTips);
          TranslationStore.translatedTips = null; // Reset translations if source changes
          TranslationStore.lastTipsHash = null;
        });
      } else {
        setState(() {}); // Still trigger UI update for other things if needed
      }
    });
  }

  @override
  void dispose() {
    I18n.instance.removeListener(_onLanguageChanged);
    _listController.dispose();
    _chartAnimationController.dispose();
    _pageController.dispose();
    timer?.cancel();
    _statsTimer?.cancel();
    super.dispose();
  }

  Timer? _statsTimer;

  void _startStatsMonitoring() {
    final coreCount = WinProcess.getCpuCoreCount();
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted && CoreManager.instance.runningCores.isNotEmpty) {
        setState(() {
          final now = DateTime.now();

          for (var core in CoreManager.instance.runningCores) {
            final isAlive = WinProcess.isAlive(core.process.pid);
            if (!isAlive) continue;

            final currentCpuTime = WinProcess.getCpuTime(core.process.pid);
            if (currentCpuTime == 0 && core.lastCpuTime != 0) {

            }
            final deltaCpuTime = currentCpuTime - core.lastCpuTime;
            final deltaTimeMs = now.difference(core.lastCpuTimestamp).inMilliseconds;

            double cpuPercent = (deltaCpuTime / 10000.0) / (deltaTimeMs * coreCount);
            cpuPercent = cpuPercent.clamp(0.0, 1.0);

            core.lastCpuTime = currentCpuTime;
            core.lastCpuTimestamp = now;

            core.cpuUsage.removeAt(0);
            core.cpuUsage.add(cpuPercent);

            final memBytes = WinProcess.getMemoryUsage(core.process.pid);
            double memNormalized = memBytes / (8.0 * 1024 * 1024 * 1024);
            memNormalized = memNormalized.clamp(0.0, 1.0);

            core.memUsage.removeAt(0);
            core.memUsage.add(memNormalized);
          }
          _chartAnimationController.reset();
          _chartAnimationController.forward();
        });
      }
    });
  }

  void _loadSelectedVersion() {
    _selectedVersion = ConfigService.get("selected_version");
    _selectedVersionDir = ConfigService.get("selected_version_dir");
    
    if (_selectedVersion == null) {
      // Try to pick first available
      LaunchService.instance.getAllAvailableVersions().then((versions) {
        if (versions.isNotEmpty && mounted) {
          setState(() {
            _selectedVersion = versions.first['id'];
            _selectedVersionDir = versions.first['directory'];
            ConfigService.set("selected_version", _selectedVersion);
            ConfigService.set("selected_version_dir", _selectedVersionDir);
          });
        }
      });
    }
  }

  Future<void> _showVersionSelector() async {
    final versions = await LaunchService.instance.getAllAvailableVersions();
    if (!mounted) return;

    if (versions.isEmpty) {
      showWarning("No cores found. Please download one first.".tl);
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text("Select Minecraft Core".tl, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                itemCount: versions.length,
                itemBuilder: (context, index) {
                  final v = versions[index];
                  final isSelected = v['id'] == _selectedVersion;
                  return ListTile(
                    leading: Icon(Icons.layers, color: isSelected ? Theme.of(context).colorScheme.primary : null),
                    title: Text(v['id']!, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                    subtitle: Text(v['directory']!, style: const TextStyle(fontSize: 10)),
                    trailing: isSelected ? const Icon(Icons.check_circle, size: 18) : null,
                    onTap: () {
                      setState(() {
                        _selectedVersion = v['id'];
                        _selectedVersionDir = v['directory'];
                      });
                      ConfigService.set("selected_version", _selectedVersion);
                      ConfigService.set("selected_version_dir", _selectedVersionDir);
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openGameDir() {
    if (_selectedVersionDir == null) {
      showWarning("Please select a core first.".tl);
      return;
    }
    final path = _selectedVersionDir!;
    if (Platform.isWindows) {
      Process.run("explorer.exe", [path]);
    } else if (Platform.isMacOS) {
      Process.run("open", [path]);
    } else {
      launchUrlString("file://$path");
    }
  }

  Future<void> _startLaunch() async {
    if (_selectedVersion == null || _selectedVersionDir == null) {
      showWarning("Please select a core first.".tl);
      return;
    }

    final shellState = context.findAncestorStateOfType<MainShellState>();
    if (shellState != null) {
      shellState.setNavExtended(false);
      await Future.delayed(const Duration(milliseconds: 450));
    }

    if (!mounted) return;

    setState(() {
      _homeState = HomeState.launching;
      _launchError = null;
      _launchProgress = 0.0;
      _launchStatus = "Checking file integrity...".tl;
    });

    _pageController.animateToPage(1, duration: const Duration(milliseconds: 700), curve: Curves.easeOutExpo);

    try {
      // 1. 账户验证 (Microsoft Account Validation)
      final List<dynamic> accountListRaw = ConfigService.get("MinecraftAccountList") ?? [];
      final int chosenIndex = ConfigService.get("MinecraftAccount_Chosen") ?? 0;
      
      Map<String, dynamic> account = {};
      if (accountListRaw.isNotEmpty && chosenIndex < accountListRaw.length) {
        account = accountListRaw[chosenIndex] is String 
            ? jsonDecode(accountListRaw[chosenIndex]) 
            : accountListRaw[chosenIndex];
      }

      if (account['type'] == "Microsoft") {
        setState(() => _launchStatus = "Verifying Microsoft account...".tl);
        final bool refreshSuccess = await PassportService.refreshMinecraftToken();
        if (!refreshSuccess) {
          throw Exception("Microsoft session expired. Please re-login in Passport page.".tl);
        }
        await PassportService.syncMinecraftAccounts();
      }

      setState(() => _launchStatus = "Checking file integrity...".tl);
      final missing = await LaunchService.instance.getMissingFiles(_selectedVersionDir!, _selectedVersion!);
      if (missing.isNotEmpty) {
        if (mounted) {
          final confirm = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text("Missing Files".tl),
              content: Text("Current core is missing ${missing.length} files. Download and complete them before launch?".tl),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: Text("Skip".tl)),
                TextButton(onPressed: () => Navigator.pop(context, true), child: Text("Download & Launch".tl)),
              ],
            ),
          );

          if (confirm == true) {
            setState(() => _launchStatus = "Downloading missing files...".tl);
            await LaunchService.instance.downloadMissingFiles(_selectedVersionDir!, _selectedVersion!, onStatus: (status, p) {
              if (mounted) {
                setState(() {
                _launchStatus = status;
                _launchProgress = p * 0.5;
              });
              }
            });
            showInfo("Download tasks submitted. Please wait for completion in the overlay.".tl);
          }
        }
      }

      setState(() {
        _launchStatus = "Preparing to launch...".tl;
        _launchProgress = 0.1;
      });

      if (accountListRaw.isNotEmpty && chosenIndex < accountListRaw.length) {
        account = accountListRaw[chosenIndex] is String 
            ? jsonDecode(accountListRaw[chosenIndex]) 
            : accountListRaw[chosenIndex];
      }

      final String mcUsername = account['username'] ?? "BloretPlayer";
      final String mcUuid = account['uuid'] ?? "";
      final String mcType = account['type'] ?? "Offline";
      
      // Construct MC Avatar URL (Rounded Rectangle later in UI)
      final String mcAvatar = mcUuid.isNotEmpty 
          ? "https://mc-heads.net/avatar/$mcUuid/100" 
          : "https://mc-heads.net/avatar/$mcUsername/100";

      final process = await LaunchService.instance.launch(
        version: _selectedVersion!,
        minecraftDir: _selectedVersionDir!,
        onStatus: (status, progress) {
          if (mounted) {
            setState(() {
              _launchStatus = status;
              _launchProgress = progress;
            });
          }
        },
      );

      final identityId = ConfigService.get("user_identity");
      final identityName = identityId == "sister" ? "Sister".tl : identityId == "little_sister" ? "Little Sister".tl : "Brother".tl;

      final newCore = RunningCore(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        version: "1.21.8",
        loader: "Forge-47.2.0",
        userName: mcUsername,
        avatar: mcAvatar,
        accountType: mcType,
        identityName: identityName,
        process: process,
      );

      setState(() {
        CoreManager.instance.addCore(newCore);
        _selectedCore = newCore;
      });
      
      process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
        _addLogToCore(newCore, line);
        _parseLogForProgress(line);

        if (line.contains("Created: ") && line.contains("x") || line.contains("GLFW window created")) {
           if (_homeState == HomeState.launching) {
             _onWindowCreated();
           }
        }
      });

      process.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
        _addLogToCore(newCore, line);
        _parseLogForProgress(line);
      });

      if (mounted) {
        setState(() {
          _launchStatus = "Game launched successfully".tl;
          _launchProgress = 1.0;
        });
      }

      process.exitCode.then((code) {
        debugPrint("Minecraft exited with code $code");
        logger.info("Minecraft exited with code $code", LogSource.tool);
        if (mounted) {
          setState(() {
            CoreManager.instance.removeCore(newCore);
            if (_selectedCore == newCore) {
              _selectedCore = CoreManager.instance.runningCores.isNotEmpty ? CoreManager.instance.runningCores.last : null;
            }
            if (CoreManager.instance.runningCores.isEmpty) {
              _showRunningHandle = false;
              if (_homeState == HomeState.running) {
                _pageController.animateToPage(0, duration: const Duration(milliseconds: 700), curve: Curves.easeOutExpo);
                _homeState = HomeState.normal;
              }
            }
          });
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _launchError = e.toString();
        });
        showError("Failed to launch game: $e".tl);
      }
      logger.error("Launch error: $e", LogSource.tool);
    }
  }

  void _addLogToCore(RunningCore core, String line) {
    if (!mounted) return;
    setState(() {
      core.logs.add(line);
      if (core.logs.length > 500) core.logs.removeAt(0);
    });
    
    // Only scroll if this core is currently selected
    if (_selectedCore == core) {
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
  }

  void _onWindowCreated() {
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        _pageController.animateToPage(0, duration: const Duration(milliseconds: 700), curve: Curves.easeOutExpo).then((_) {
          if (mounted) {
            setState(() {
              _homeState = HomeState.normal;
              _showRunningHandle = true;
            });
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPortrait = MediaQuery.of(context).size.height > MediaQuery.of(context).size.width;

    // Define pages dynamically based on state to "remove" the middle page
    final List<Widget> pages = [
      _buildNormalLayout(theme, isPortrait),
    ];

    if (_homeState == HomeState.launching) {
      pages.add(_buildLaunchingLayout(theme, isPortrait));
      pages.add(_buildRunningLayout(theme, isPortrait));
    } else {
      // Normal or Running: Skip launching page
      pages.add(_buildRunningLayout(theme, isPortrait));
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          PageView(
            controller: _pageController,
            physics: const NeverScrollableScrollPhysics(),
            children: pages,
          ),
          if (_showRunningHandle && _homeState == HomeState.normal)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: Center(
                child: MouseRegion(
                  onEnter: (_) => setState(() => _isHandleExtended = true),
                  onExit: (_) => setState(() => _isHandleExtended = false),
                  child: InkWell(
                    onTap: () {
                      setState(() => _homeState = HomeState.running);
                      _pageController.animateToPage(1, duration: const Duration(milliseconds: 700), curve: Curves.easeOutExpo);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeOutQuart,
                      width: _isHandleExtended ? 42 : 12,
                      height: 140,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.85),
                        borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 8, offset: const Offset(-2, 2))
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.insights_outlined,
                            color: theme.colorScheme.onPrimary,
                            size: _isHandleExtended ? 22 : 0,
                          ),
                          if (_isHandleExtended) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.onPrimary.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                CoreManager.instance.runningCores.length.toString(),
                                style: TextStyle(
                                  color: theme.colorScheme.onPrimary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
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
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        isPortrait
                            ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("$name Launcher",
                                style: theme.textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            SlidingTextCycle(
                              key: ValueKey("tips_${_showTranslatedTips}_${_translatedSentences?.length}_${sentences.hashCode}"),
                              sentences: (_showTranslatedTips ? (_translatedSentences ?? sentences) : sentences)
                                  .map((e) => e.replaceAll("Windows 11", "Android").replaceAll("RinUI", "Flutter"))
                                  .toList()..add("絡可好き好き"),
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
                                key: ValueKey("tips_${_showTranslatedTips}_${_translatedSentences?.length}_${sentences.hashCode}"),
                                sentences: (_showTranslatedTips ? (_translatedSentences ?? sentences) : sentences)
                                    .map((e) => e.replaceAll("Windows 11", "Android").replaceAll("RinUI", "Flutter"))
                                    .toList()..add("絡可好き好き"),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.outline,
                                  fontWeight: FontWeight.w500,
                                ) ?? const TextStyle(),
                              ),
                            ),
                            if (!_isChinese && _apiAvailable) const SizedBox(width: 28),
                          ],
                        ),
                        if (!_isChinese && _apiAvailable)
                          Positioned(
                            right: 0,
                            top: -4,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 10, right: 10),
                              child: _buildTranslateButton(
                                isTranslating: _isTranslating,
                                onPressed: _toggleTranslation,
                                isTranslated: _showTranslatedTips,
                              ),
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
                child: Text("${agentName.tl} ${"relies on AI. It may make mistakes, please verify important information.".tl}",
                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 14)),
              ),
              const SizedBox(height: 32),
              SlideFadeIn(
                controller: _listController,
                delay: 0.6,
                child: Text("Information".tl, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
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
                    Text("Bloret Server data provided by Bloret Server Check".tl, style: TextStyle(color: Theme.of(context).colorScheme.outline)),
                  ],
                ),
              )
            ],
          ),
        ),
        _BottomActionRail(
          onLaunch: _startLaunch,
          onSwitchCore: _showVersionSelector,
          onOpenFolder: _openGameDir,
          selectedVersion: _selectedVersion,
        ),
      ],
    );
  }

  Widget _buildLaunchingLayout(ThemeData theme, bool isPortrait) {
    final List<dynamic> accountListRaw = ConfigService.get("MinecraftAccountList") ?? [];
    final int chosenIndex = ConfigService.get("MinecraftAccount_Chosen") ?? 0;
    Map<String, dynamic> account = {};
    if (accountListRaw.isNotEmpty && chosenIndex < accountListRaw.length) {
      account = accountListRaw[chosenIndex] is String ? jsonDecode(accountListRaw[chosenIndex]) : accountListRaw[chosenIndex];
    }
    final String mcUsername = account['username'] ?? "Guest".tl;
    final String mcUuid = account['uuid'] ?? "";
    final String mcType = account['type'] ?? "Offline";
    final String mcAvatar = mcUuid.isNotEmpty ? "https://mc-heads.net/avatar/$mcUuid/100" : "https://mc-heads.net/avatar/$mcUsername/100";

    return Container(
      key: const ValueKey("launching_home"),
      padding: const EdgeInsets.all(48),
      child: Center(
        child: SizedBox(
          width: 500,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.inventory_2, size: 40),
              ),
              const SizedBox(height: 24),
              Text(_selectedVersion ?? "...", style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
              Text("Minecraft Core".tl, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 48),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                      imageUrl: mcAvatar, 
                      width: 44, height: 44, 
                      fit: BoxFit.cover, 
                      errorWidget: (_,_,_) => Container(color: Colors.blueGrey, width: 44, height: 44, child: const Icon(Icons.person, color: Colors.white70))
                    ),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(mcUsername, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      Text("$mcType ${"Account".tl}", style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 64),
              if (_launchError == null) ...[
                Text(_launchStatus, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: _launchProgress,
                    minHeight: 8,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  ),
                ),
                const SizedBox(height: 8),
                Text("${(_launchProgress * 100).toInt()}%", style: theme.textTheme.bodySmall),
              ] else ...[
                const Icon(Icons.error_outline, color: Colors.red, size: 48),
                const SizedBox(height: 12),
                Text("Launch Failed".tl, style: theme.textTheme.titleMedium?.copyWith(color: Colors.red, fontWeight: FontWeight.bold)),
                Text(_launchError!, style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                BloretButton(onPressed: () {
                  _pageController.animateToPage(0, duration: const Duration(milliseconds: 700), curve: Curves.easeOutExpo);
                  setState(() => _homeState = HomeState.normal);
                }, text: "Back to Home".tl),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRunningLayout(ThemeData theme, bool isPortrait) {
    final core = _selectedCore;
    if (core == null) return Center(child: Text("No running cores".tl));

    return Container(
      padding: const EdgeInsets.all(32),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () {
                        _pageController.animateToPage(0, duration: const Duration(milliseconds: 700), curve: Curves.easeOutExpo);
                        setState(() => _homeState = HomeState.normal);
                      },
                    ),
                    const SizedBox(width: 8),
                    Text("Running Core Info".tl, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    transitionBuilder: (Widget child, Animation<double> animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: animation.drive(Tween(begin: const Offset(0.02, 0), end: Offset.zero).chain(CurveTween(curve: Curves.easeOutCubic))),
                          child: child,
                        ),
                      );
                    },
                    child: KeyedSubtree(
                      key: ValueKey("core_details_${core.id}"),
                      child: ListView(
                        padding: const EdgeInsets.only(right: 16),
                        children: [
                          _buildProcessActions(theme, core),
                          const SizedBox(height: 24),
                          FluentCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("Real-time Performance".tl, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                                const SizedBox(height: 24),
                                SizedBox(
                                  height: 180,
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          children: [
                                            Text("CPU Usage".tl, style: theme.textTheme.bodySmall),
                                            const SizedBox(height: 8),
                                            Expanded(child: _CoreStatsChart(data: core.cpuUsage, color: Colors.blueAccent, animation: _chartAnimationController, unit: "%")),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 32),
                                      Expanded(
                                        child: Column(
                                          children: [
                                            Text("Memory Usage".tl, style: theme.textTheme.bodySmall),
                                            const SizedBox(height: 8),
                                            Expanded(child: _CoreStatsChart(data: core.memUsage, color: Colors.greenAccent, animation: _chartAnimationController, unit: "GB", scaleFactor: 8.0)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          _buildLogPanel(theme),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 32),
          Expanded(
            flex: 1,
            child: Column(
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: FluentCard(
                    key: ValueKey("player_card_${core.id}"),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: core.avatar != null && core.avatar!.isNotEmpty
                              ? CachedNetworkImage(imageUrl: core.avatar!, width: 36, height: 36, fit: BoxFit.cover, errorWidget: (_,_,_) => const Icon(Icons.account_circle, size: 36))
                              : const Icon(Icons.account_circle, size: 36),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(core.userName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), overflow: TextOverflow.ellipsis),
                              Text("${core.accountType} ${"Account".tl}", style: const TextStyle(fontSize: 10, color: Colors.grey)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: FluentCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Running Cores".tl, style: const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 16),
                        Expanded(
                          child: ListView.builder(
                            itemCount: CoreManager.instance.runningCores.length,
                            itemBuilder: (context, index) => _buildRunningCoreItem(theme, CoreManager.instance.runningCores[index]),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProcessActions(ThemeData theme, RunningCore core) {
    return FluentCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Process Control".tl, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildActionButton(
                theme,
                icon: Icons.stop_circle_outlined,
                label: "Kill".tl,
                tooltip: "Forcefully terminate the game process.".tl,
                color: Colors.redAccent,
                onTap: () {
                  if (!WinProcess.isAlive(core.process.pid)) {
                    showError("Process already terminated.".tl);
                    return;
                  }
                  if (!WinProcess.isAlive(core.process.pid)) {
                    showError("Process already terminated.".tl);
                    return;
                  }
                  core.process.kill();
                  showSuccess("${"Terminating game process...".tl} (PID: ${core.process.pid})");
                },
              ),
              const SizedBox(width: 6),
              _buildActionButton(
                theme,
                icon: core.isSuspended ? Icons.play_circle_outline : Icons.pause_circle_outline,
                label: core.isSuspended ? "Resume".tl : "Suspend".tl,
                tooltip: "Freeze or thaw the game process to save CPU resources.".tl,
                color: Colors.orangeAccent,
                onTap: () {
                  if (core.isSuspended) {
                    WinProcess.resume(core.process.pid);
                    setState(() => core.isSuspended = false);
                    showSuccess("Process resumed.".tl);
                  } else {
                    WinProcess.suspend(core.process.pid);
                    setState(() => core.isSuspended = true);
                    showSuccess("Process suspended.".tl);
                  }
                },
              ),
              const SizedBox(width: 6),
              _buildActionButton(
                theme,
                icon: Icons.bolt,
                label: "Efficiency".tl,
                tooltip: "Enable Windows Efficiency Mode to reduce power consumption.".tl,
                color: core.isEfficiencyMode ? Colors.green : Colors.greenAccent,
                onTap: () {
                  setState(() => core.isEfficiencyMode = !core.isEfficiencyMode);
                  WinProcess.setEfficiencyMode(core.process.pid, core.isEfficiencyMode);
                  showSuccess(core.isEfficiencyMode ? "Efficiency mode enabled.".tl : "Efficiency mode disabled.".tl);
                },
              ),
              const SizedBox(width: 6),
              _buildActionButton(
                theme,
                icon: Icons.cleaning_services_outlined,
                label: "Clean RAM".tl,
                tooltip: "Trim process working set. May cause temporary disk I/O lag as memory is swapped back from disk.".tl,
                color: Colors.blueAccent,
                onTap: () {
                  WinProcess.cleanRAM(core.process.pid);
                  showSuccess("Memory working set trimmed.".tl);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(ThemeData theme, {required IconData icon, required String label, required String tooltip, required Color color, required VoidCallback onTap}) {
    return Expanded(
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: color.withValues(alpha: 0.1)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: color, size: 16),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRunningCoreItem(ThemeData theme, RunningCore core) {
    final isSelected = _selectedCore == core;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => setState(() => _selectedCore = core),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isSelected 
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5) 
                : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
            border: isSelected ? Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.5)) : null,
          ),
          child: Row(
            children: [
              Stack(
                alignment: Alignment.bottomRight,
                children: [
                  Icon(
                    CupertinoIcons.cube, 
                    color: core.isSuspended ? theme.colorScheme.outline : theme.colorScheme.primary, 
                    size: 24
                  ),
                  if (core.isSuspended)
                    Container(
                      padding: const EdgeInsets.all(1),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.pause, size: 10, color: Colors.orangeAccent),
                    )
                  else if (core.isEfficiencyMode)
                    Container(
                      padding: const EdgeInsets.all(1),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.energy_savings_leaf, size: 10, color: Colors.greenAccent),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(core.version, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    Text(core.loader, style: const TextStyle(fontSize: 10)),
                  ],
                ),
              ),
              if (isSelected)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.greenAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text("ACTIVE", style: TextStyle(color: Colors.greenAccent, fontSize: 9, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogPanel(ThemeData theme) {
    final logs = _selectedCore?.logs ?? [];
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      height: _showLogsInRunning ? 400 : 64,
      child: FluentCard(
        padding: EdgeInsets.zero,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Column(
            children: [
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    setState(() => _showLogsInRunning = !_showLogsInRunning);
                    if (_showLogsInRunning) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (_logScrollController.hasClients) {
                          _logScrollController.jumpTo(_logScrollController.position.maxScrollExtent);
                        }
                      });
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    color: theme.colorScheme.primary.withValues(alpha: 0.05),
                    child: Row(
                      children: [
                        Icon(Icons.description_outlined, size: 18, color: theme.colorScheme.primary),
                        const SizedBox(width: 12),
                        Text("Launch Logs".tl, style: TextStyle(color: theme.colorScheme.primary, fontSize: 13, fontWeight: FontWeight.bold)),
                        const Spacer(),
                        Icon(
                          _showLogsInRunning ? Icons.expand_less : Icons.expand_more,
                          size: 20,
                          color: theme.colorScheme.primary,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (_showLogsInRunning)
                Expanded(
                  child: ListView.builder(
                    controller: _logScrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: logs.length,
                    itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: SelectableText(
                        logs[index],
                        style: TextStyle(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                          fontFamily: 'monospace',
                          fontSize: 11,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
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
                    final identity = identityId == "sister" ? "Sister".tl : identityId == "little_sister" ? "Little Sister".tl : "Brother".tl;

                    String hintText;
                    if (isBusy) {
                      hintText = isShort ? "Thinking...".tl : "${agentName.tl} ${"is thinking...".tl}";
                    } else {
                      if (isShort) {
                        hintText = "${"To".tl} ${agentName.tl} ${"ask".tl}...";
                      } else {
                        hintText = "${"About".tl} Minecraft ${"any questions, you can ask".tl} ${agentName.tl}${Bloriko.type == "bloriko" ? ", $identity ~" : ""}";
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
                        Text("Bloret ${server?.text == null ? "" : "| ${_showTranslatedServer ? (_translatedServerText ?? server?.text) : server?.text}"}", style: theme.textTheme.bodySmall),
                      ],
                    )
                  ],
                ),
              )
            ],
          ),
          const Divider(height: 24),
          Text("${agentName.tl} ${"Recommended Time".tl}", style: const TextStyle(fontWeight: FontWeight.bold)),
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
                ? KeyedSubtree(key: ValueKey(server != null), child: GptMarkdown(_showTranslatedServer ? (_translatedServerBestTime ?? server?.bestTime ?? "...") : (server?.bestTime ?? "..."), style: theme.textTheme.bodySmall))
                : Row(
              key: ValueKey(server != null),
              mainAxisSize: MainAxisSize.min,
              children: [
                Expanded(child: Text("${"Hehe".tl}~ ${agentName.tl} ${"is here! The current online player count is perfect for playing~".tl}", style: theme.textTheme.bodySmall)),
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

class _CoreStatsChart extends StatelessWidget {
  final List<double> data;
  final Color color;
  final Animation<double> animation;
  final String? unit;
  final double scaleFactor;

  const _CoreStatsChart({
    required this.data, 
    required this.color, 
    required this.animation,
    this.unit,
    this.scaleFactor = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        // Dynamic range: Find the max value in current data to adjust Y-axis scale
        double currentMax = data.isEmpty ? 0.1 : data.reduce((a, b) => a > b ? a : b);
        // Ensure a minimum scale so it doesn't look empty when usage is low
        double yRange = (currentMax * 1.2).clamp(0.1, 1.0);

        return CustomPaint(
          painter: _SmoothChartPainter(data, color, animation.value, yRange, unit, scaleFactor),
          size: Size.infinite,
        );
      },
    );
  }
}

class _SmoothChartPainter extends CustomPainter {
  final List<double> data;
  final Color color;
  final double progress;
  final double yRange;
  final String? unit;
  final double scaleFactor;

  _SmoothChartPainter(this.data, this.color, this.progress, this.yRange, this.unit, this.scaleFactor);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;

    // --- Draw Grid and Labels ---
    final gridPaint = Paint()
      ..color = color.withValues(alpha: 0.1)
      ..strokeWidth = 1;
    
    final labelStyle = TextStyle(color: color.withValues(alpha: 0.6), fontSize: 9, fontWeight: FontWeight.bold);
    
    // Draw 3 horizontal lines (0%, 50%, 100% of range)
    for (int i = 0; i <= 2; i++) {
      double y = size.height - (i * size.height / 2);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
      
      double val = (i * yRange / 2) * scaleFactor;
      String label = unit == "%" ? "${(val * 100).toInt()}%" : "${val.toStringAsFixed(1)}${unit ?? ""}";
      
      final tp = TextPainter(
        text: TextSpan(text: label, style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(4, y - tp.height - 2));
    }

    // --- Draw Chart Line ---
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withValues(alpha: 0.25), color.withValues(alpha: 0.0)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    final path = Path();
    final fillPath = Path();

    final double stepX = size.width / (data.length - 2);
    final double horizontalOffset = -stepX * progress;

    bool first = true;
    for (int i = 0; i < data.length; i++) {
      final double x = (i * stepX) + horizontalOffset;
      // Use the dynamic yRange for scaling
      final double y = size.height * (1 - (data[i] / yRange));

      if (first) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
        first = false;
      } else {
        final prevX = ((i - 1) * stepX) + horizontalOffset;
        final prevY = size.height * (1 - (data[i - 1] / yRange));
        path.quadraticBezierTo(prevX + stepX / 2, prevY, x, y);
        fillPath.quadraticBezierTo(prevX + stepX / 2, prevY, x, y);
      }
    }

    fillPath.lineTo(size.width + stepX, size.height);
    fillPath.close();

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SmoothChartPainter oldDelegate) => true;
}

class _BottomActionRail extends StatelessWidget {
  final VoidCallback onLaunch;
  final VoidCallback onSwitchCore;
  final VoidCallback onOpenFolder;
  final String? selectedVersion;

  const _BottomActionRail({
    required this.onLaunch,
    required this.onSwitchCore,
    required this.onOpenFolder,
    this.selectedVersion,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPortrait = MediaQuery.of(context).size.height > MediaQuery.of(context).size.width;

    final List<dynamic> accountListRaw = ConfigService.get("MinecraftAccountList") ?? [];
    final int chosenIndex = ConfigService.get("MinecraftAccount_Chosen") ?? 0;
    String username = "None";
    if (accountListRaw.isNotEmpty && chosenIndex < accountListRaw.length) {
      final account = accountListRaw[chosenIndex] is String 
          ? jsonDecode(accountListRaw[chosenIndex]) 
          : accountListRaw[chosenIndex];
      username = account['username'] ?? "None";
    }

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
                        Text(selectedVersion ?? "No Core Selected".tl, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), overflow: TextOverflow.ellipsis),
                        Text("${"As".tl} $username ${"launch".tl} Minecraft", style: theme.textTheme.bodySmall?.copyWith(fontSize: 11)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  BloretIconButton(
                    icon: Icons.folder_open,
                    tooltip: "Game Directory".tl,
                    onPressed: onOpenFolder,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: BloretButton(
                      onPressed: onSwitchCore,
                      icon: Icons.swap_horiz,
                      text: "Switch Core".tl,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: BloretButton(
                      onPressed: onLaunch,
                      icon: Icons.play_arrow,
                      text: "Launch".tl,
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
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(selectedVersion ?? "No Core Selected".tl, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), overflow: TextOverflow.ellipsis),
                    Text("${"As".tl} $username ${"launch".tl} Minecraft", style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              const Spacer(),
              BloretIconButton(
                icon: Icons.folder_open,
                tooltip: "Game Directory".tl,
                onPressed: onOpenFolder,
              ),
              const SizedBox(width: 12),
              BloretButton(
                onPressed: onSwitchCore,
                icon: Icons.swap_horiz,
                text: "Switch Core".tl,
                height: 48,
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 44,
                width: 140,
                child: BloretButton(
                  onPressed: onLaunch,
                  icon: Icons.play_arrow,
                  text: "Launch".tl,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
