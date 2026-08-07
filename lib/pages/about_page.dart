import 'dart:io';

import 'package:bloret_launcher/services/config_service.dart';
import 'package:bloret_launcher/widgets/button.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/i18n.dart';
import '../core/grammer_candy.dart';
import '../core/logger.dart';
import '../main.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => AboutPageState();
}

class AboutPageState extends State<AboutPage> {
  int count = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPortrait = MediaQuery.of(context).size.height > MediaQuery.of(context).size.width;

    return Scaffold(
      body: Padding(
        padding: EdgeInsets.only(left: Platform.isAndroid ? 24 : 36, right: 24, top: 24, bottom: 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text("About".tl,
                      style: theme.textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 12),
              FluentCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Image.asset(theme.brightness == Brightness.dark ? "assets/bloret_dark.png" : "assets/bloret_light.png", width: isPortrait ? 64 : 100, height: isPortrait ? 64 : 100, fit: BoxFit.cover,),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("$name Launcher", style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, fontSize: isPortrait ? 22 : 28)),
                              MouseRegion(
                                cursor: SystemMouseCursors.click,
                                child: GestureDetector(
                                  onTap: () {
                                    if (count > 5) {
                                      if (!(ConfigService.get("develop_mode") ?? false)) {
                                        ConfigService.set("develop_mode", true).then((_) {
                                          setState(() {});
                                          showSuccess("Developer mode enabled".tl);
                                          logger.info("Developer mode enabled", LogSource.tool);
                                        });
                                      }
                                    } else {
                                      setState(() {
                                        count++;
                                      });
                                    }
                                  },
                                  child: Text("Version: 0.0.1", style: ConfigService.get("develop_mode") == true ? theme.textTheme.bodyMedium!.copyWith(color: Colors.greenAccent) : theme.textTheme.bodyMedium),
                                ),
                              ),
                              if (!isPortrait)
                                Text("Be creative, be simple. Your Personal Innovative Open Source AI Minecraft Launcher. Relax, it's $name Launcher.", style: TextStyle(color: theme.colorScheme.outline, fontSize: 15, height: 1.4)),
                            ],
                          ),
                        )
                      ],
                    ),
                    if (isPortrait) ...[
                      const SizedBox(height: 12),
                      Text("Be creative, be simple. Your Personal Innovative Open Source AI Minecraft Launcher. Relax, it's $name Launcher.", style: TextStyle(color: theme.colorScheme.outline, fontSize: 14, height: 1.4)),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const BloretAboutWidget(),
              const SizedBox(height: 12),
              FluentCard(
                child: isPortrait 
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(width: 40, height: 40, decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)), clipBehavior: Clip.hardEdge, child: Image.asset("assets/icons/qq.png", isAntiAlias: true, filterQuality: FilterQuality.high,),),
                            const SizedBox(width: 12),
                            Text("Bloret QQ".tl, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            BloretButton(
                              text: "Bloret".tl,
                              onPressed: () => launchUrl(Uri.parse("https://qm.qq.com/q/iGw0GwUCiI")),
                            ),
                            BloretButton(
                              text: "Bloret Software Community".tl,
                              onPressed: () => launchUrl(Uri.parse("https://qm.qq.com/q/kEt8fb41wc")),
                            ),
                          ],
                        )
                      ],
                    )
                  : Row(
                      children: [
                        Container(width: 48, height: 48, decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)), clipBehavior: Clip.hardEdge, child: Image.asset("assets/icons/qq.png", isAntiAlias: true, filterQuality: FilterQuality.high,),),
                        const SizedBox(width: 12),
                        Text("Bloret QQ".tl, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                        const Spacer(),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            BloretButton(
                              text: "Bloret".tl,
                              onPressed: () => launchUrl(Uri.parse("https://qm.qq.com/q/iGw0GwUCiI")),
                            ),
                            const SizedBox(width: 16),
                            BloretButton(
                              text: "Bloret Software Community".tl,
                              onPressed: () => launchUrl(Uri.parse("https://qm.qq.com/q/kEt8fb41wc")),
                            ),
                          ],
                        )
                      ],
                    ),
              ),
              const SizedBox(height: 8),
              FluentCard(
                child: isPortrait
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CustomPaint(painter: GithubPainter(), size: const Size(40, 40)),
                            const SizedBox(width: 12),
                            Text("Github".tl, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            BloretButton(
                              text: "Organization".tl,
                              onPressed: () => launchUrl(Uri.parse("https://github.com/BloretCrew")),
                            ),
                            BloretButton(
                              text: "Legacy Project".tl,
                              onPressed: () => launchUrl(Uri.parse("https://github.com/BloretCrew/Bloret-Launcher")),
                            ),
                            BloretButton(
                              text: "Current Project".tl,
                              onPressed: () => launchUrl(Uri.parse("https://github.com/xXYxxdMC-GH/BloretLauncher")),
                            ),
                          ],
                        )
                      ],
                    )
                  : Row(
                      children: [
                        CustomPaint(painter: GithubPainter(), size: const Size(48, 48)),
                        const SizedBox(width: 12),
                        Text("Github".tl, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                        const Spacer(),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            BloretButton(
                              text: "Organization".tl,
                              onPressed: () => launchUrl(Uri.parse("https://github.com/BloretCrew")),
                            ),
                            const SizedBox(width: 16),
                            BloretButton(
                              text: "Legacy Project".tl,
                              onPressed: () => launchUrl(Uri.parse("https://github.com/BloretCrew/Bloret-Launcher")),
                            ),
                            const SizedBox(width: 16),
                            BloretButton(
                              text: "Current Project".tl,
                              onPressed: () => launchUrl(Uri.parse("https://github.com/xXYxxdMC-GH/BloretLauncher")),
                            ),
                          ],
                        )
                      ],
                    ),
              ),
            ],
          ),
        )
      ),
    );
  }

}

class BloretAboutWidget extends StatelessWidget {
  final Function(String url)? openUrl;

  const BloretAboutWidget({
    super.key,
    this.openUrl,
  });

  void _handleLink(String url) {
    if (openUrl != null) {
      openUrl!(url);
    } else {
      launchUrl(Uri.parse(url));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDarkMode ? const Color(0xFFB0B0B0) : const Color(0xFF606060);

    return LayoutBuilder(
      builder: (context, constraints) {
        return DefaultTextStyle(
          style: TextStyle(
            fontSize: 16,
            color: textColor,
            height: 1.4,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildLinkText('$name Launcher Website: ', 'https://launcher.bloret.net/', isDarkMode),
              _buildLinkText('Bloret PassPort: ', 'https://passport.bloret.net/', isDarkMode),
              _buildLinkText('Bloret Wiki: ', 'https://wiki.bloret.net/', isDarkMode),
              Text('$name Launcher brings Bloret to your computer.'.tl),
              Text('$name Launcher is ad-free open-source software owned by Bloret.'.tl),
              Text('$name Launcher: Flutter Edition is ad-free open-source software owned by Bloret.'.tl),
              const SizedBox(height: 8),
              Text('© 2026 $name Launcher All rights reserved. © 2026 Bloret All rights reserved.'),
              _buildLinkText('To view the source code of $name Launcher, please go to: ', 'https://github.com/BloretCrew/Bloret-Launcher/', isDarkMode),
              _buildLinkText('To view the source code of $name Launcher: Flutter Edition, please go to: ', 'https://github.com/xXYxxdMC-GH/BloretLauncher/', isDarkMode),
              _buildLinkText('To view the source code of $name Launcher Setup, please go to: ', 'https://github.com/BloretCrew/Bloret-Launcher-Setup/', isDarkMode),
              _buildLinkText('To submit an issue, please go to: ', 'https://github.com/xXYxxdMC-GH/BloretLauncher/issues/new/choose', isDarkMode),
              const SizedBox(height: 8),
              _buildRichEulaText(),
              const SizedBox(height: 8),
              Text('Thanks to Flutter for providing the framework for $name Launcher. Thanks to the developers who contributed to $name Launcher. Thanks to the open-source projects that $name Launcher learned from and integrated.'.tl),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLinkText(String prefixKey, String url, bool isDarkMode) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _handleLink(url),
        child: RichText(
          text: TextSpan(
            style: const TextStyle(fontSize: 14, height: 1.4),
            children: [
              TextSpan(text: prefixKey.tl, style: TextStyle(color: isDarkMode ? const Color(0xFFB0B0B0) : const Color(0xFF606060))),
              TextSpan(
                text: url,
                style: const TextStyle(
                  color: Color(0xFF0067C0),
                  decoration: TextDecoration.underline,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRichEulaText() {
    return RichText(
      text: TextSpan(
        style: TextStyle(
          fontSize: 12,
          height: 1.4,
          color: Colors.grey[600],
        ),
        children: [
          TextSpan(text: '$name Launcher follows '.tl),
          _widgetSpanLink('Mojang Eula', 'https://www.minecraft.net/zh-hans/eula'),
          TextSpan(text: ' , $name Launcher\'s Microsoft Login feature is approved by Mojang. $name Launcher itself does not contain Minecraft binaries or other resource files. $name Launcher is ad-free open-source software. We encourage all players to purchase '.tl),
          _widgetSpanLink('Genuine Minecraft Account', 'https://www.minecraft.net/zh-hans/choose-your-game'),
          TextSpan(text: ' to play.'.tl),
        ],
      ),
    );
  }

  InlineSpan _widgetSpanLink(String text, String url) {
    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => _handleLink(url),
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF0067C0),
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      )
    );
  }
}

class GithubPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = (ThemeData().brightness == Brightness.dark ? Colors.white : Colors.black)
      ..style = PaintingStyle.fill;

    canvas.scale(size.width / 24);
    canvas.drawPath(buildIconPath(), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}


Path buildIconPath() {
  final Path path = Path();
  path.moveTo(10.226, 17.284);
  path.cubicTo(7.261, 16.924, 5.172, 14.791, 5.172, 12.028);
  path.cubicTo(5.172, 10.905, 5.576, 9.692, 6.25, 8.884);
  path.cubicTo(5.958, 8.143, 6.003, 6.57, 6.34, 5.919);
  path.cubicTo(7.238, 5.807, 8.451, 6.279, 9.17, 6.929);
  path.cubicTo(10.023, 6.66, 10.922, 6.525, 12.023, 6.525);
  path.cubicTo(13.123, 6.525, 14.022, 6.66, 14.83, 6.907);
  path.cubicTo(15.526, 6.278, 16.762, 5.807, 17.66, 5.919);
  path.cubicTo(17.975, 6.525, 18.02, 8.098, 17.727, 8.861);
  path.cubicTo(18.447, 9.715, 18.828, 10.861, 18.828, 12.028);
  path.cubicTo(18.828, 14.791, 16.739, 16.88, 13.73, 17.262);
  path.cubicTo(14.493, 17.756, 15.01, 18.834, 15.01, 20.069);
  path.lineTo(15.01, 22.405);
  path.cubicTo(15.01, 23.079, 15.571, 23.461, 16.245, 23.191);
  path.cubicTo(20.311, 21.641, 23.5, 17.576, 23.5, 12.545);
  path.cubicTo(23.5, 6.188, 18.334, 1, 11.978, 1);
  path.cubicTo(5.62, 1, 0.5, 6.188, 0.5, 12.545);
  path.cubicTo(0.5, 17.531, 3.667, 21.665, 7.935, 23.214);
  path.cubicTo(8.541, 23.439, 9.125, 23.034, 9.125, 22.428);
  path.lineTo(9.125, 20.63);
  path.cubicTo(8.847, 20.754, 8.547, 20.854, 8.257, 20.854);
  path.cubicTo(6.774, 20.854, 5.898, 20.046, 5.27, 18.541);
  path.cubicTo(5.023, 17.934, 4.753, 17.575, 4.236, 17.508);
  path.cubicTo(3.966, 17.485, 3.877, 17.373, 3.877, 17.238);
  path.cubicTo(3.877, 16.968, 4.327, 16.767, 4.775, 16.767);
  path.cubicTo(5.427, 16.767, 5.988, 17.171, 6.572, 18.002);
  path.cubicTo(7.022, 18.653, 7.493, 18.945, 8.055, 18.945);
  path.cubicTo(8.616, 18.945, 8.975, 18.743, 9.492, 18.226);
  path.cubicTo(9.874, 17.845, 10.166, 17.508, 10.436, 17.283);
  return path;
}
