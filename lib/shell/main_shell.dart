import 'dart:async';
import 'dart:io';

import 'package:bloret_launcher/core/ffi_proxy.dart';
import 'package:bloret_launcher/core/ffi_reg_op.dart';
import 'package:bloret_launcher/core/window_bridge.dart';
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
import 'package:bloret_launcher/services/config_service.dart';
import 'package:bloret_launcher/services/download_service.dart';
import 'package:bloret_launcher/services/plugin_install_server.dart';
import 'package:bloret_launcher/tools/server_info.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../core/global.dart';
import '../core/i18n.dart';
import '../main.dart';
import '../pages/home_page.dart';
import '../pages/passport_page.dart';
import '../pages/settings_page.dart';

enum ShellPage {
  home,
  agent,
  divider1,
  download,
  cores,
  tools,
  stats,
  mods,
  bbbs,
  live,
  divider2,
  passport,
  settings,
  about
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  static MainShellState? of(BuildContext context) {
    return context.findAncestorStateOfType<MainShellState>();
  }

  @override
  State<MainShell> createState() => MainShellState();
}

class MainShellState extends State<MainShell> with WidgetsBindingObserver {
  static MainShellState? instance;

  int selectedIndex = ShellPage.home.index;
  bool _isExtended = true;
  bool _isDownloadExpanded = false;
  Timer? _timer;
  final Set<int> _renderedIndices = {ShellPage.home.index};
  final Map<int, Widget> _pageCache = {};
  final Map<int, GlobalKey> pageKeys = {};
  Brightness? _lastBrightness;

  final _trayChannel = const BasicMessageChannel(
    'bloret/tray',
    StandardMessageCodec(),
  );

  @override
  void initState() {
    super.initState();
    instance = this;
    globalShellContext = context;
    WindowBridge.init(context);
    PluginInstallServer.start();

    if (!kDebugMode && Platform.isWindows && !WindowsRegedit.isBloraProtocolAvailable()) {
      final exePath = Platform.resolvedExecutable;
      WindowsRegedit.registerProtocol(exePath);
    }

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
        BloretApiService.fetchServerInfo("Bloret"),
      ]);
      futures.then((value) {
        config = value[0] as BloraLauncherConfig?;
        server = value[1] as BloretServer?;
        if (mounted) setState(() {});
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
    instance = null;
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    super.didChangePlatformBrightness();
    _updateAppIcon();
  }

  bool get isExtended => _isExtended;

  void jumpToPage(ShellPage page) {
    final index = page.index;
    if (index >= 0 && index < _pages.length && _pages[index] is! String) {
      _onPageChanged(index);
    }
  }

  void refreshPage(ShellPage page) {
    final index = page.index;
    if (pageKeys.containsKey(index)) {
      pageKeys[index]!.currentState?.setState(() {});
    }
  }

  void refreshAllPages() {
    for (var key in pageKeys.values) {
      key.currentState?.setState(() {});
    }
  }

  void setNavExtended(bool value) {
    if (mounted) {
      setState(() {
        _isExtended = value;
      });
    }
  }

  void _updateAppIcon() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    WinWindow.setIconTheme(isDark);
  }

  List<dynamic> get _pages => [
    (
      _NavDestination("Home".tl, Icons.home_outlined, Icons.home),
      () => const HomePage(),
    ),
    (
      _NavDestination(
        "Agent".tl,
        Icons.smart_toy_outlined,
        Icons.smart_toy,
        keepAlive: true,
      ),
      () => const BloraChatPage(),
    ),
    "divider",
    (
      _NavDestination(
        "Download".tl,
        Icons.file_download_outlined,
        Icons.file_download,
      ),
      () => const DownloadPage(),
    ),
    (
      _NavDestination(
        "Cores".tl,
        Icons.view_in_ar_outlined,
        Icons.view_in_ar,
        keepAlive: true,
      ),
      () => const CoresPage(),
    ),
    (
      _NavDestination(
        "Tools".tl,
        Icons.handyman_outlined,
        Icons.handyman,
        keepAlive: true,
      ),
      () => const ToolsPage(),
    ),
    (
      _NavDestination("Stats".tl, Icons.bar_chart_outlined, Icons.bar_chart),
      () => const StatsPage(),
    ),
    (
      _NavDestination("Mods".tl, Icons.extension_outlined, Icons.extension),
      () => const ModsPage(),
    ),
    (
      _NavDestination(
        "BBBS".tl,
        Icons.forum_outlined,
        Icons.forum,
        keepAlive: true,
      ),
      () => const BbbsPage(),
    ),
    (
      _NavDestination(
        "Live".tl,
        Icons.live_tv_outlined,
        Icons.live_tv,
        keepAlive: true,
      ),
      () => const LivePage(),
    ),

    "divider",
    (
      _NavDestination("Passport".tl, Icons.person_outline, Icons.person),
      () => const PassPortPage(),
    ),
    (
      _NavDestination("Settings".tl, Icons.settings_outlined, Icons.settings),
      () => const SettingsPage(),
    ),
    (
      _NavDestination("About".tl, Icons.info_outline, Icons.info),
      () => const AboutPage(),
    ),
  ];

  Widget _buildAgentOverlay(BuildContext context, bool isPortrait) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _onPageChanged(ShellPage.agent.index),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.primaryContainer.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(25),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
            border: Border.all(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: Bloriko.type == "bloriko" ? 34 : 28,
                    height: Bloriko.type == "bloriko" ? 34 : 28,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  Bloriko.type == "bloriko" ? Container(width: 32, height: 32, clipBehavior: .antiAlias, decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, shape: BoxShape.circle), child: Image.asset("assets/bloriko.png"),) : Icon(Icons.smart_toy_outlined, size: 16),
                ],
              ),
              const SizedBox(width: 12),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    Bloriko.instance.currentTool != null &&
                            Bloriko.instance.currentTool! != "set_user_identity"
                        ? Bloriko.instance.currentTool!
                        : agentName.tl,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                  if (Bloriko.instance.currentTool == null)
                    Row(
                      children: [
                        Text(
                          switch (Bloriko.instance.connectionStatus) {
                            BlorikoConnectionStatus.connecting =>
                              "Connecting...".tl,
                            BlorikoConnectionStatus.handshake =>
                              "Verifying...".tl,
                            BlorikoConnectionStatus.streaming =>
                              "Thinking...".tl,
                            BlorikoConnectionStatus.error => "Error".tl,
                            _ => "Running".tl,
                          },
                          style: TextStyle(
                            fontSize: 10,
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer
                                .withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDownloadOverlay(BuildContext context) {
    final activeTasks = DownloadService.instance.activeTasks;
    final progress = DownloadService.instance.totalProgress;

    return GestureDetector(
      onTap: () => setState(() => _isDownloadExpanded = !_isDownloadExpanded),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutQuart,
        width: _isDownloadExpanded ? 300 : 48,
        height: _isDownloadExpanded ? 350 : 48,
        padding: _isDownloadExpanded
            ? const EdgeInsets.all(12)
            : EdgeInsets.zero,
        decoration: BoxDecoration(
          color: _isDownloadExpanded
              ? Theme.of(context).colorScheme.surface.withValues(alpha: 0.95)
              : Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(_isDownloadExpanded ? 20 : 24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(
            color:
                (_isDownloadExpanded
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outline)
                    .withValues(alpha: 0.3),
          ),
        ),
        child: _isDownloadExpanded
            ? _buildExpandedDownload(context, activeTasks, progress)
            : _buildCompactDownload(progress),
      ),
    );
  }

  Widget _buildCompactDownload(double progress) {
    final speed = DownloadService.instance.totalSpeed;
    return Stack(
      alignment: Alignment.center,
      children: [
        SizedBox(
          width: 36,
          height: 36,
          child: CircularProgressIndicator(
            value: progress,
            strokeWidth: 3,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        Icon(
          speed > 0 ? Icons.downloading : Icons.file_download_outlined,
          size: 18,
          color: Theme.of(context).colorScheme.primary,
        ),
      ],
    );
  }

  Widget _buildExpandedDownload(
    BuildContext context,
    List<DownloadTask> activeTasks,
    double progress,
  ) {
    final allTasks = DownloadService.instance.getTasks().where((t) {
      return t.isDownloading ||
          (t.progress > 0 && t.progress < 1.0) ||
          t.status.contains("失败") || t.status.contains("错误") || t.status.contains("超时") || t.status.contains("Failed") || t.status.contains("Error") || t.status.contains("Timeout");
    }).toList();

    final Map<String?, List<DownloadTask>> groupedTasks = {};
    for (var task in allTasks) {
      groupedTasks.putIfAbsent(task.groupId, () => []).add(task);
    }

    final totalSpeed = DownloadService.instance.totalSpeed;
    final remaining = DownloadService.instance.remainingTasks;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.file_download,
              color: theme.colorScheme.primary,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    activeTasks.length > 1
                        ? "${activeTasks.length} ${"Downloads".tl}"
                        : "Downloading".tl,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  if (totalSpeed > 0)
                    Text(
                      "${DownloadService.instance.formatSpeed(totalSpeed)} · $remaining ${"files left".tl}",
                      style: const TextStyle(fontSize: 9, color: Colors.grey),
                    )
                  else
                    Text(
                      "$remaining ${"files queued".tl}",
                      style: const TextStyle(fontSize: 9, color: Colors.grey),
                    ),
                ],
              ),
            ),
            Text(
              "${(progress * 100).toInt()}%",
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => setState(() => _isDownloadExpanded = false),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
        Expanded(
          child: allTasks.isEmpty
              ? Center(child: Text("No tasks".tl))
              : ListView(
                  padding: EdgeInsets.zero,
                  children: groupedTasks.entries.map((entry) {
                    final groupId = entry.key;
                    final tasks = entry.value;

                    return AnimatedSize(
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeOutCubic,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (groupId != null)
                            TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0.0, end: 1.0),
                              duration: const Duration(milliseconds: 500),
                              curve: Curves.easeOutBack,
                              builder: (context, value, child) {
                                return Transform.translate(
                                  offset: Offset(20 * (1 - value), 0),
                                  child: Opacity(opacity: value, child: child),
                                );
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        groupId,
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w900,
                                          color: theme.colorScheme.primary.withValues(alpha: 0.7),
                                          letterSpacing: 0.5,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    InkWell(
                                      onTap: () => DownloadService.instance.cancelGroup(groupId),
                                      borderRadius: BorderRadius.circular(4),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                        child: Text(
                                          "Cancel Group".tl,
                                          style: const TextStyle(fontSize: 9, color: Colors.redAccent),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ...tasks.map((task) {
                            return ListenableBuilder(
                              listenable: task,
                              key: ValueKey(task.id), // 重要：保持动画状态
                              builder: (context, child) {
                                return TweenAnimationBuilder<double>(
                                  tween: Tween(begin: 0.0, end: 1.0),
                                  duration: const Duration(milliseconds: 600),
                                  curve: Curves.easeOutCubic,
                                  builder: (context, value, child) {
                                    return Transform.translate(
                                      offset: Offset(0, 10 * (1 - value)),
                                      child: Opacity(opacity: value, child: child),
                                    );
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 2),
                                    child: InkWell(
                                      onTap: () {},
                                      borderRadius: BorderRadius.circular(4),
                                      child: Padding(
                                        padding: const EdgeInsets.all(4.0),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    task.id,
                                                    style: const TextStyle(
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                if (task.isDownloading) ...[
                                                  Text(
                                                    DownloadService.instance.formatSpeed(
                                                      task.speed,
                                                    ),
                                                    style: const TextStyle(
                                                      fontSize: 9,
                                                      color: Colors.blueAccent,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  IconButton(
                                                    icon: const Icon(
                                                      Icons.cancel_outlined,
                                                      size: 14,
                                                      color: Colors.redAccent,
                                                    ),
                                                    onPressed: () => DownloadService.instance
                                                        .cancelTask(task.id),
                                                    padding: EdgeInsets.zero,
                                                    constraints: const BoxConstraints(),
                                                  ),
                                                ],
                                              ],
                                            ),
                                            const SizedBox(height: 2),
                                            ClipRRect(
                                              borderRadius: BorderRadius.circular(2),
                                              child: LinearProgressIndicator(
                                                value: task.progress,
                                                minHeight: 3,
                                                backgroundColor: Colors.grey.withValues(
                                                  alpha: 0.1,
                                                ),
                                              ),
                                            ),
                                            if (task.isDownloading)
                                              Text(
                                                task.status,
                                                style: const TextStyle(
                                                  fontSize: 9,
                                                  color: Colors.grey,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            );
                          }),
                          if (groupId != null) const SizedBox(height: 8),
                        ],
                      ),
                    );
                  }).toList(),
                ),
        ),
      ],
    );
  }

  void _onPageChanged(int index) {
    if (selectedIndex == index) return;
    final oldIndex = selectedIndex;

    if (!_renderedIndices.contains(index)) {
      setState(() {
        _renderedIndices.add(index);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _doPageChange(index, oldIndex);
      });
    } else {
      _doPageChange(index, oldIndex);
    }
  }

  void _doPageChange(int index, int oldIndex) {
    setState(() {
      selectedIndex = index;
      _renderedIndices.add(index);
    });

    if (_pages[oldIndex] is! String) {
      final dest = _pages[oldIndex].$1;
      if (!dest.keepAlive) {
        Future.delayed(const Duration(milliseconds: 450), () {
          if (mounted && selectedIndex != oldIndex) {
            setState(() {
              _renderedIndices.remove(oldIndex);
            });
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (_lastBrightness != theme.brightness) {
      _lastBrightness = theme.brightness;
      WinWindow.setIconTheme(isDark);
    }

    final isPortrait =
        MediaQuery.of(context).size.height > MediaQuery.of(context).size.width;

    final userName =
        ConfigService.get('Bloret_PassPort_NickName') ?? (ConfigService.get('Bloret_PassPort_UserName') ?? "Guest".tl);
    final avatar = ConfigService.get('Bloret_PassPort_Avatar') ?? "";

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 8),
                                  _NavTile(
                                    icon: Icons.menu,
                                    title: "Menu".tl,
                                    isExtended: false,
                                    isSelected: false,
                                    compact: true,
                                    onTap: () => setState(
                                      () => _isExtended = !_isExtended,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Expanded(
                                    child: ListView.builder(
                                      padding: EdgeInsets.zero,
                                      itemCount: 10,
                                      itemBuilder: (context, index) {
                                        final item = _pages[index];
                                        if (item is String) {
                                          return const Divider(
                                            height: 16,
                                            indent: 8,
                                            endIndent: 8,
                                          );
                                        }
                                        final dest = item.$1;
                                        return _NavTile(
                                          icon: dest.icon,
                                          selectedIcon: dest.selectedIcon,
                                          title: dest.title,
                                          isExtended: _isExtended,
                                          isSelected: selectedIndex == index,
                                          onTap: () => _onPageChanged(index),
                                        );
                                      },
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Column(
                                      children: [
                                        const Divider(
                                          height: 16,
                                          indent: 8,
                                          endIndent: 8,
                                        ),
                                        _AccountTile(
                                          isExtended: _isExtended,
                                          isSelected: selectedIndex == ShellPage.passport.index,
                                          userName: userName,
                                          avatar: avatar,
                                          onTap: () => _onPageChanged(ShellPage.passport.index),
                                        ),
                                        _NavTile(
                                          icon: _pages[ShellPage.settings.index].$1.icon,
                                          title: _pages[ShellPage.settings.index].$1.title,
                                          isExtended: _isExtended,
                                          isSelected: selectedIndex == ShellPage.settings.index,
                                          onTap: () => _onPageChanged(ShellPage.settings.index),
                                        ),
                                        _NavTile(
                                          icon: _pages[ShellPage.about.index].$1.icon,
                                          title: _pages[ShellPage.about.index].$1.title,
                                          isExtended: _isExtended,
                                          isSelected: selectedIndex == ShellPage.about.index,
                                          onTap: () => _onPageChanged(ShellPage.about.index),
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
                  child: ListenableBuilder(
                    listenable: Listenable.merge([
                      Bloriko.instance,
                      Bloriko.typeNotifier,
                      Bloriko.modeNotifier,
                    ]),
                    builder: (context, child) {
                      return Stack(
                        children: _pages.asMap().entries.map((entry) {
                          final index = entry.key;
                          final item = entry.value;
                          if (item is String) return const SizedBox.shrink();

                          final isSelected = selectedIndex == index;
                          if (!_renderedIndices.contains(index)) {
                            return const SizedBox.shrink();
                          }

                          if (_pageCache[index] == null) {
                            pageKeys[index] ??= GlobalKey();
                            _pageCache[index] = _PageStorageWrapper(
                              key: pageKeys[index],
                              builder: item.$2 as Widget Function(),
                            );
                          }

                          return AnimatedOpacity(
                            key: ValueKey(index),
                            duration: isSelected ? const Duration(milliseconds: 400) : Duration.zero,
                            curve: Curves.easeOutCubic,
                            opacity: isSelected ? 1.0 : 0.0,
                            child: IgnorePointer(
                              ignoring: !isSelected,
                              child: AnimatedSlide(
                                duration: isSelected ? const Duration(milliseconds: 400) : Duration.zero,
                                curve: Curves.easeOutCubic,
                                offset: isSelected
                                    ? Offset.zero
                                    : (isPortrait
                                          ? const Offset(0, 0.05)
                                          : const Offset(0.02, 0)),
                                child: _pageCache[index]!,
                              ),
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                ),
              ],
            ),

            Positioned(
              bottom: isPortrait ? 100 : 100,
              right: 24,
              child: ListenableBuilder(
                listenable: Listenable.merge([
                  DownloadService.instance,
                  Bloriko.instance,
                ]),
                builder: (context, child) {
                  final showDownload =
                      DownloadService.instance.activeTasks.isNotEmpty;
                  final showAgent = Bloriko.instance.busy && selectedIndex != ShellPage.agent.index;

                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 350),
                        switchInCurve: Curves.easeOutBack,
                        switchOutCurve: Curves.easeInBack,
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation,
                          child: ScaleTransition(
                            scale: animation,
                            child: child,
                          ),
                        ),
                        child: showDownload
                            ? _buildDownloadOverlay(context)
                            : const SizedBox.shrink(
                                key: ValueKey("no_download"),
                              ),
                      ),
                      if (showDownload && showAgent) const SizedBox(width: 12),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 350),
                        switchInCurve: Curves.easeOutBack,
                        switchOutCurve: Curves.easeInBack,
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation,
                          child: ScaleTransition(
                            scale: animation,
                            child: child,
                          ),
                        ),
                        child: showAgent
                            ? _buildAgentOverlay(context, isPortrait)
                            : const SizedBox.shrink(key: ValueKey("no_agent")),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        height: isPortrait ? (84 + MediaQuery.of(context).padding.bottom) : 0,
        child: ClipRect(
          child: isPortrait
              ? Container(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).padding.bottom,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    border: Border(
                      top: BorderSide(
                        color: Theme.of(
                          context,
                        ).dividerColor.withValues(alpha: 0.1),
                      ),
                    ),
                  ),
                  child: SizedBox(
                    height: 84,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: _pages.length,
                      itemBuilder: (context, index) {
                        final item = _pages[index];
                        if (item is String) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Center(
                              child: SizedBox(
                                height: 24,
                                child: VerticalDivider(width: 1),
                              ),
                            ),
                          );
                        }

                        final dest = item.$1;
                        final isSelected = selectedIndex == index;
                        final theme = Theme.of(context);

                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 4,
                          ),
                          child: InkWell(
                            onTap: () => _onPageChanged(index),
                            borderRadius: BorderRadius.circular(12),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                color: isSelected
                                    ? theme.colorScheme.primaryContainer
                                          .withValues(alpha: 0.4)
                                    : Colors.transparent,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    isSelected ? dest.selectedIcon : dest.icon,
                                    color: isSelected
                                        ? theme.colorScheme.primary
                                        : theme.colorScheme.onSurfaceVariant,
                                    size: 24,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    dest.title,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: isSelected
                                          ? FontWeight.bold
                                          : FontWeight.w500,
                                      color: isSelected
                                          ? theme.colorScheme.primary
                                          : theme.colorScheme.onSurfaceVariant,
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
                )
              : const SizedBox.shrink(),
        ),
      ),
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
    final color = isSelected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface;

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
              color: isSelected
                  ? theme.colorScheme.secondaryContainer.withValues(alpha: 0.5)
                  : Colors.transparent,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                const SizedBox(width: 10),
                SizedBox(
                  width: 20,
                  child: Icon(
                    isSelected ? (selectedIcon ?? icon) : icon,
                    color: color,
                    size: 20,
                  ),
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
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
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
              color: isSelected
                  ? theme.colorScheme.secondaryContainer.withValues(alpha: 0.5)
                  : Colors.transparent,
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
                    child:
                        avatar.isNotEmpty &&
                            ConfigService.get('Bloret_PassPort_Login') == true
                        ? CachedNetworkImage(
                            imageUrl: avatar,
                            fit: BoxFit.cover,
                            errorWidget: (_, _, _) =>
                                const Icon(Icons.account_circle, size: 28),
                            progressIndicatorBuilder: (_, _, loadingProgress) =>
                                const SizedBox(
                                  width: 28,
                                  height: 28,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 4,
                                  ),
                                ),
                          )
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
                        ConfigService.get('Bloret_PassPort_Login') == true
                            ? userName
                            : "Login".tl,
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
  final bool keepAlive;
  const _NavDestination(
    this.title,
    this.icon,
    this.selectedIcon, {
    this.keepAlive = false,
  });
}

class _PageStorageWrapper extends StatefulWidget {
  final Widget Function() builder;
  const _PageStorageWrapper({super.key, required this.builder});

  @override
  State<_PageStorageWrapper> createState() => _PageStorageWrapperState();
}

class _PageStorageWrapperState extends State<_PageStorageWrapper> {
  @override
  Widget build(BuildContext context) => widget.builder();
}
