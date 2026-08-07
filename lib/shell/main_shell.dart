import 'dart:async';
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
import 'package:bloret_launcher/services/win32_icon_service.dart';
import 'package:bloret_launcher/core/window_bridge.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:bloret_launcher/tools/server_info.dart';

import '../core/global.dart';
import '../main.dart';
import '../pages/home_page.dart';
import '../pages/passport_page.dart';
import '../pages/settings_page.dart';
import '../core/i18n.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => MainShellState();
}

class MainShellState extends State<MainShell> with WidgetsBindingObserver {
  int selectedIndex = 0;
  bool _isExtended = true;
  Timer? _timer;
  final Set<int> _renderedIndices = {0};

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
        config = value[0] as BloraLauncherConfig?;
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

  void setNavExtended(bool value) {
    if (mounted) {
      setState(() {
        _isExtended = value;
      });
    }
  }

  void _updateAppIcon() {
    final isDark = WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
    Win32IconService.switchIcon(isDark);
  }

  List<dynamic> get _pages => [
    (_NavDestination("Home".tl, Icons.home_outlined, Icons.home,), () => const HomePage()),
    (_NavDestination("Agent".tl, Icons.smart_toy_outlined, Icons.smart_toy, keepAlive: true), () => const BloraChatPage()),
    "divider",
    (_NavDestination("Download".tl, Icons.file_download_outlined, Icons.file_download, keepAlive: true), () => const DownloadPage()),
    (_NavDestination("Cores".tl, Icons.view_in_ar_outlined, Icons.view_in_ar), () => const CoresPage()),
    (_NavDestination("Tools".tl, Icons.handyman_outlined, Icons.handyman), () => const ToolsPage()),
    (_NavDestination("Stats".tl, Icons.bar_chart_outlined, Icons.bar_chart), () => const StatsPage()),
    (_NavDestination("Mods".tl, Icons.extension_outlined, Icons.extension), () => const ModsPage()),
    (_NavDestination("BBBS".tl, Icons.forum_outlined, Icons.forum, keepAlive: true), () => const BbbsPage()),
    (_NavDestination("Live".tl, Icons.live_tv_outlined, Icons.live_tv, keepAlive: true), () => const LivePage()),

    "divider",
    (_NavDestination("Passport".tl, Icons.person_outline, Icons.person), () => const PassPortPage()),
    (_NavDestination("Settings".tl, Icons.settings_outlined, Icons.settings), () => const SettingsPage()),
    (_NavDestination("About".tl, Icons.info_outline, Icons.info), () => const AboutPage()),
  ];

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
    final isPortrait = MediaQuery.of(context).size.height > MediaQuery.of(context).size.width;

    final userName = ConfigService.get('Bloret_PassPort_UserName') ?? "Guest".tl;
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
                                      title: "Menu".tl,
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
                                          const Divider(height: 16, indent: 8, endIndent: 8),
                                          _AccountTile(
                                            isExtended: _isExtended,
                                            isSelected: selectedIndex == 11,
                                            userName: userName,
                                            avatar: avatar,
                                            onTap: () => _onPageChanged(11),
                                          ),
                                          _NavTile(
                                            icon: _pages[12].$1.icon,
                                            title: _pages[12].$1.title,
                                            isExtended: _isExtended,
                                            isSelected: selectedIndex == 12,
                                            onTap: () => _onPageChanged(12),
                                          ),
                                          _NavTile(
                                            icon: _pages[13].$1.icon,
                                            title: _pages[13].$1.title,
                                            isExtended: _isExtended,
                                            isSelected: selectedIndex == 13,
                                            onTap: () => _onPageChanged(13),
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
                      listenable: Listenable.merge([Bloriko.instance, Bloriko.typeNotifier, Bloriko.modeNotifier]),
                      builder: (context, child) {
                        return Stack(
                          children: _pages.asMap().entries.map((entry) {
                            final index = entry.key;
                            final item = entry.value;
                            if (item is String) return const SizedBox.shrink();

                            final isSelected = selectedIndex == index;
                            if (!_renderedIndices.contains(index)) return const SizedBox.shrink();

                            return AnimatedOpacity(
                              key: ValueKey(index),
                              duration: const Duration(milliseconds: 400),
                              curve: Curves.easeOutCubic,
                              opacity: isSelected ? 1.0 : 0.0,
                              child: IgnorePointer(
                                ignoring: !isSelected,
                                child: AnimatedSlide(
                                  duration: const Duration(milliseconds: 400),
                                  curve: Curves.easeOutCubic,
                                  offset: isSelected
                                      ? Offset.zero
                                      : (isPortrait ? const Offset(0, 0.05) : const Offset(0.02, 0)),
                                  child: (item.$2 as Widget Function())(),
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

              ListenableBuilder(
                listenable: Bloriko.instance,
                builder: (context, child) {
                  if (!Bloriko.instance.busy || selectedIndex == 1) return const SizedBox.shrink();

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
                          onTap: () => _onPageChanged(1),
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
                                        ? "${agentName.tl} ${"is:".tl} ${Bloriko.instance.currentTool}"
                                        : "${agentName.tl} ${"is running...".tl}",
                                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onPrimaryContainer)
                                    ),
                                    if (Bloriko.instance.currentTool == null)
                                      Row(
                                        children: [
                                          Text(
                                              switch (Bloriko.instance.connectionStatus) {
                                                BlorikoConnectionStatus.connecting => "Connecting to server...".tl,
                                                BlorikoConnectionStatus.handshake => "Verifying...".tl,
                                                BlorikoConnectionStatus.streaming => "Receiving response...".tl,
                                                BlorikoConnectionStatus.error => "Connection Error".tl,
                                                _ => "Please wait...".tl,
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
                    final isSelected = selectedIndex == index;
                    final theme = Theme.of(context);

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                      child: InkWell(
                        onTap: () => _onPageChanged(index),
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
                        ? CachedNetworkImage(imageUrl: avatar, fit: BoxFit.cover, errorWidget: (_,_,_) => const Icon(Icons.account_circle, size: 28), progressIndicatorBuilder: (_, _, loadingProgress) => const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 4),))
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
                        ConfigService.get('Bloret_PassPort_Login') == true ? userName : "Login".tl,
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
  const _NavDestination(this.title, this.icon, this.selectedIcon, {this.keepAlive = false});
}
