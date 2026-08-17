import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_flutter_agent/ai_flutter_agent.dart';
import 'package:bloret_launcher/core/i18n.dart';
import 'package:bloret_launcher/core/logger.dart';
import 'package:bloret_launcher/services/bloriko.dart';
import 'package:bloret_launcher/services/memory.dart';
import 'package:bloret_launcher/services/notice_manager.dart';
import 'package:bloret_launcher/services/update_manager.dart';
import 'package:bloret_launcher/shell/main_shell.dart';
import 'package:bloret_launcher/tools/server_info.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'core/global.dart';
import 'core/network_config.dart';
import 'core/theme_manager.dart';
import 'pages/welcome_page.dart';
import 'services/config_service.dart';
import 'services/win32_icon_service.dart';

BloraLauncherConfig? config;

BloretServer? server;

const name = "Blora";

late final AppLogger logger;

late final UpdateManager updateManager;

final NoticeManager noticeManager = NoticeManager.instance;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ConfigService.init();
  await I18n.init();
  HttpOverrides.global = BloraHttpOverrides();
  logger = await AppLogger.getInstance();
  Win32IconService.init();
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return const SizedBox.shrink();
  };
  Bloriko.getInstance();
  await MemoryStore.instance.loadOnInit();
  updateManager = await UpdateManager.instance.init();
  Timer.periodic(const Duration(seconds: 30), (timer) async {
    try {
      final res = await Dio().get(
        "https://raw.gitcode.com/Bloret/Bloret-Launcher/raw/Windows/IP.json",
      );
      if (res.statusCode == 200) {
        if (jsonDecode(res.data)["PCFS"] != null &&
            jsonDecode(res.data)["PCFS"] != serverIP) {
          serverIP = res.data["PCFS"];
          timer.cancel();
        }
      }
    } catch (e) {
      logger.error("Fetch Server IP Error: $e");
    }
  });
  runApp(const BloraLauncherApp());
}

class BloraLauncherApp extends StatelessWidget {
  const BloraLauncherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([I18n.instance, ThemeManager.instance]),
      builder: (context, child) {
        return MaterialApp(
          title: '$name Launcher',
          debugShowCheckedModeBanner: false,
          theme: ThemeManager.instance.getTheme(Brightness.light),
          darkTheme: ThemeManager.instance.getTheme(Brightness.dark),
          themeMode: ThemeManager.instance.themeMode,
          home: Semantics(
            container: true,
            child: ConfigService.isFirstRun()
                ? const WelcomeSetupScreen()
                : AgentOverlayWidget(child: MainShell()),
          ),
        );
      },
    );
  }
}

Widget buildSimpleMarkdownText(String text, {TextStyle? style}) {
  final List<InlineSpan> spans = [];
  final RegExp exp = RegExp(r'\*\*(.*?)\*\*');

  int lastMatchEnd = 0;

  for (final Match match in exp.allMatches(text)) {
    if (match.start > lastMatchEnd) {
      spans.add(
        TextSpan(text: text.substring(lastMatchEnd, match.start), style: style),
      );
    }

    spans.add(
      TextSpan(
        text: match.group(1),
        style: (style ?? const TextStyle()).copyWith(
          fontWeight: FontWeight.bold,
        ),
      ),
    );

    lastMatchEnd = match.end;
  }

  if (lastMatchEnd < text.length) {
    spans.add(TextSpan(text: text.substring(lastMatchEnd), style: style));
  }

  return Text.rich(TextSpan(children: spans));
}

class SlideFadeIn extends StatelessWidget {
  final Widget child;
  final double delay;
  final AnimationController controller;

  const SlideFadeIn({
    super.key,
    required this.child,
    required this.delay,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final animation = CurvedAnimation(
      parent: controller,
      curve: Interval(
        delay,
        (delay + 0.3).clamp(0.0, 1.0),
        curve: Curves.easeOutCubic,
      ),
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
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final void Function()? onTap;
  const FluentCard({
    super.key,
    required this.child,
    this.padding,
    this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color,
      child: onTap != null
          ? InkWell(
              mouseCursor: SystemMouseCursors.click,
              onTap: onTap,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: padding ?? const EdgeInsets.all(16),
                child: child,
              ),
            )
          : Padding(padding: padding ?? const EdgeInsets.all(16), child: child),
    );
  }
}

class PlaceholderPage extends StatelessWidget {
  final String title;
  const PlaceholderPage({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(title, style: Theme.of(context).textTheme.headlineMedium),
    );
  }
}
