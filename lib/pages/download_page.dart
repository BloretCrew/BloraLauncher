import 'dart:io';

import 'package:bloret_launcher/pages/version_selector_view.dart';
import 'package:bloret_launcher/services/config_service.dart';
import 'package:bloret_launcher/services/launch_service.dart';
import 'package:bloret_launcher/shell/main_shell.dart';
import 'package:bloret_launcher/widgets/windows_widgets.dart';
import 'package:flutter/material.dart';

import '../core/grammer_candy.dart';
import '../core/i18n.dart';
import '../core/java_config.dart';
import '../main.dart';
import '../services/download_service.dart';
import 'external_app_selector_view.dart';
import 'java_selector_view.dart';
import 'mrpack_import_view.dart';

class DownloadPage extends StatefulWidget {
  const DownloadPage({super.key});

  @override
  State<DownloadPage> createState() => _DownloadPageState();
}

enum PageType { minecraft, java, external, modrinth }

class _DownloadPageState extends State<DownloadPage> {
  final PageController _pageController = PageController();
  PageType _selectedPageType = PageType.minecraft;
  List<String> javaVersions = [];
  String? selectedTargetDir;

  @override
  void initState() {
    super.initState();
    javaVersions = JavaConfig.versionList.map((e) => "Java $e").toList();
    _loadTargetDirs();
  }

  void _loadTargetDirs() {
    final List<dynamic> dirs = ConfigService.get('minecraft_dirs') ?? [];
    if (dirs.isNotEmpty) {
      selectedTargetDir = dirs.first.toString();
    } else {
      selectedTargetDir = LaunchService.instance.getPreferredDownloadDir();
    }
  }

  void _navigateToSelector() {
    // Retract MainShell sidebar if extended
    final shell = context.findAncestorStateOfType<MainShellState>();
    if (shell != null) {
      shell.setNavExtended(false);
    }

    _pageController.nextPage(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PageView(
      controller: _pageController,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _buildMainHome(context),
        switch (_selectedPageType) {
          PageType.java => JavaSelectorView(
            onBack: () => setState(() {
              _pageController.previousPage(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeInOutCubic,
              );
            }),
          ),
          PageType.external => ExternalAppEditorView(
            onBack: () => setState(() {
              _pageController.previousPage(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeInOutCubic,
              );
            }),
            onSaved: () {
              setState(() {
                _pageController.previousPage(
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeInOutCubic,
                );
              });
              showInfo("Application added. You can find it in Cores page.".tl);
            },
          ),
          PageType.modrinth => MrpackImportView(
            onBack: () => setState(() {
              _pageController.previousPage(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeInOutCubic,
              );
            }),
            onImported: () {
              setState(() {
                _pageController.previousPage(
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeInOutCubic,
                );
              });
              showInfo("Modpack imported. You can find it in Cores page.".tl);
            },
          ),
          _ => VersionSelectorView(
            onBack: () => setState(() {
              _pageController.previousPage(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeInOutCubic,
              );
            }),
          ),
        },
      ],
    );
  }

  Widget _buildMainHome(BuildContext context) {
    final isPortrait =
        MediaQuery.of(context).size.height > MediaQuery.of(context).size.width;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        padding: EdgeInsets.only(
          left: isPortrait ? 16 : 32,
          right: 16,
          top: 16,
          bottom: 16,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 8),
            child: Text(
              "Download".tl,
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 16),
          // _buildActiveTasks(context),
          const SizedBox(height: 8),
          _buildTargetDirSelector(),
          const SizedBox(height: 16),
          DownloadCard(
            image: SizedBox(
              width: 42,
              height: 42,
              child: Image.asset("assets/icons/mc_be.png", scale: 0.9),
            ),
            title: "Minecraft Versions".tl,
            subtitle: "Download and install vanilla Minecraft cores".tl,
            onPressed: () {
              setState(() {
                _selectedPageType = PageType.minecraft;
              });
              _navigateToSelector();
            },
          ),
          // DownloadCard(
          //   image: SizedBox(width: 42, height: 42, child: Image.asset("assets/icons/forge.png")),
          //   title: "Forge Loader".tl,
          //   subtitle: "Install Forge to use Forge Mods".tl,
          //   buttonText: "Browse All".tl,
          //   onPressed: () => _navigateToSelector(LoaderType.forge),
          // ),
          // DownloadCard(
          //   image: SizedBox(width: 42, height: 42, child: Image.asset("assets/icons/fabric.png")),
          //   title: "Fabric Loader".tl,
          //   subtitle: "Install Fabric to use Fabric Mods".tl,
          //   buttonText: "Browse All".tl,
          //   onPressed: () => _navigateToSelector(LoaderType.fabric),
          // ),
          // DownloadCard(
          //   image: SizedBox(width: 42, height: 42, child: Image.asset("assets/icons/neoforge.png")),
          //   title: "NeoForge Loader".tl,
          //   subtitle: "Install NeoForge to use NeoForge Mods".tl,
          //   buttonText: "Browse All".tl,
          //   onPressed: () => _navigateToSelector(LoaderType.neoforge),
          // ),
          DownloadCard(
            image: SizedBox(
              width: 42,
              height: 42,
              child: Image.asset("assets/icons/java.png"),
            ),
            title: "Java Runtime".tl,
            subtitle: "Java environment required for Minecraft".tl,
            onPressed: () {
              setState(() => _selectedPageType = PageType.java);
              _navigateToSelector();
            },
            onDownload: (v) async {
              final version = v.replaceAll("Java ", "");

              updateStatus(String status) {
                DownloadService.instance
                    .getTask("Java_$version")
                    .update(0.0, status);
              }

              updateStatus("Checking device...".tl);
              final existingPath = await DownloadService.instance
                  .findExistingJava(version);
              if (existingPath != null) {
                showInfo(
                  "${"Java".tl} $version ${"is already installed at".tl}: $existingPath",
                );
                return;
              }

              final url = JavaConfig.versions[version]?["Windows"]?["x64"];
              if (url != null) {
                await DownloadService.instance.downloadFile(
                  "Java_$version",
                  url,
                  "java_$version.msi",
                  (path, updateStatus) async {
                    updateStatus("Starting installation...".tl);
                    final result = await Process.start("msiexec", [
                      "/i",
                      path,
                      "/quiet",
                      "/qn",
                    ]);
                    updateStatus("Installing in background...".tl);
                    final exitCode = await result.exitCode;
                    if (exitCode == 0) {
                      showSuccess("Java %s installed".tl.format(version));
                    } else {
                      showError(
                        "Java %s installation failed".tl.format(version),
                      );
                    }
                    return exitCode == 0;
                  },
                );
              }
            },
          ),
          DownloadCard(
            image: SizedBox(
              width: 42,
              height: 42,
              child: Image.asset("assets/icons/ext.png"),
            ),
            title: "External / Modpack".tl,
            subtitle: "Add custom launchers or modpack files".tl,
            onPressed: () {
              setState(() {
                _selectedPageType = PageType.external;
              });
              _navigateToSelector();
            },
          ),
          DownloadCard(
            image: SizedBox(
              width: 42,
              height: 42,
              child: CustomPaint(
                painter: ModrinthPainter(),
                size: const Size(42, 42),
              ),
            ),
            title: "Modrinth Modpack".tl,
            subtitle: "Import .mrpack format modpacks".tl,
            onPressed: () {
              setState(() => _selectedPageType = PageType.modrinth);
              _navigateToSelector();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTargetDirSelector() {
    final List<dynamic> dirs = ConfigService.get('minecraft_dirs') ?? [];
    if (dirs.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Download Target Directory".tl,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 4),
          Win11Dropdown(
            initialValue: selectedTargetDir,
            items: dirs
                .map(
                  (d) => Win11DropdownItem(
                    value: d.toString(),
                    label: d.toString(),
                  ),
                )
                .toList(),
            onChanged: (v) {
              setState(() => selectedTargetDir = v);
            },
          ),
        ],
      ),
    );
  }
}

class DownloadCard extends StatelessWidget {
  final Widget image;
  final String title;
  final String subtitle;
  final Function(String)? onDownload;
  final VoidCallback? onPressed;
  final Widget? label;

  const DownloadCard({
    super.key,
    required this.image,
    required this.title,
    required this.subtitle,
    this.label,
    this.onDownload,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final isPortrait =
        MediaQuery.of(context).size.height > MediaQuery.of(context).size.width;

    if (isPortrait) {
      return FluentCard(
        onTap: onPressed,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                image,
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.arrow_forward),
              ],
            ),
          ],
        ),
      );
    }

    return FluentCard(
      onTap: onPressed,
      child: Row(
        children: [
          image,
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(subtitle, style: TextStyle(color: Colors.grey.shade600)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.arrow_forward),
        ],
      ),
    );
  }
}

class ModrinthPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF60D677)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    canvas.scale(0.08);

    canvas.drawPath(buildIconPath(), paint);
    canvas.drawPath(buildIconPath2(), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

Path buildIconPath() {
  final Path path = Path();
  path.moveTo(503.16, 323.56);
  path.cubicTo(514.55, 281.47, 515.32, 235.91, 503.2, 190.76);
  path.cubicTo(466.57, 54.23, 326.04, -26.8, 189.33, 9.78);
  path.cubicTo(83.81, 38.02, 11.39, 128.07, 0.69, 230.47);
  path.lineTo(44, 230.47);
  path.cubicTo(54.3, 147.33, 113.75, 74.73, 199.76, 51.71);
  path.cubicTo(306.06, 23.26, 415.14, 80.67, 453.18, 181.38);
  path.lineTo(411.04, 192.65);
  path.cubicTo(391.65, 145.8, 352.58, 111.45, 306.31, 96.82);
  path.lineTo(298.57, 140.66);
  path.cubicTo(335.1, 154.13, 364.73, 184.5, 375.57, 224.91);
  path.cubicTo(391.37, 283.8, 361.95, 344.14, 308.57, 369.17);
  path.lineTo(320.1, 412.16);
  path.cubicTo(390.26, 383.21, 432.41, 310.3, 422.44, 235.14);
  path.lineTo(464.42, 223.91);
  path.cubicTo(460.56, 308.07, 503.16, 323.56, 503.16, 323.56);
  return path;
}

Path buildIconPath2() {
  final Path path = Path();
  path.moveTo(321.99, 504.22);
  path.cubicTo(185.27, 540.8, 44.75, 459.77, 8.11, 323.24);
  path.cubicTo(3.36, 305.76, 1.09, 290.06, 0, 275.46);
  path.lineTo(43.27, 275.46);
  path.cubicTo(44.36, 287.37, 46.47, 299.35, 49.68, 311.29);
  path.cubicTo(53.04, 323.8, 57.45, 335.75, 62.79, 347.07);
  path.lineTo(101.38, 323.92);
  path.cubicTo(98.13, 316.42, 95.39, 308.6, 93.21, 300.47);
  path.cubicTo(69.17, 210.87, 122.41, 118.77, 212.13, 94.76);
  path.cubicTo(229.13, 90.21, 246.23, 88.44, 262.93, 89.15);
  path.lineTo(255.19, 133);
  path.cubicTo(244.73, 133.05, 234.11, 134.42, 223.53, 137.25);
  path.cubicTo(157.31, 154.98, 118.01, 222.95, 135.75, 289.09);
  path.cubicTo(136.85, 293.16, 138.13, 297.13, 139.59, 300.99);
  path.lineTo(188.94, 271.38);
  path.lineTo(174.07, 231.95);
  path.lineTo(220.67, 184.08);
  path.lineTo(279.57, 171.39);
  path.lineTo(296.62, 192.38);
  path.lineTo(269.47, 219.88);
  path.lineTo(245.79, 227.33);
  path.lineTo(228.87, 244.72);
  path.lineTo(237.16, 267.79);
  path.cubicTo(253.95, 285.63, 253.98, 285.64, 253.98, 285.64);
  path.lineTo(277.7, 279.33);
  path.lineTo(294.58, 260.79);
  path.lineTo(331.44, 249.12);
  path.lineTo(342.42, 273.82);
  path.lineTo(304.39, 320.45);
  path.lineTo(240.66, 340.63);
  path.lineTo(212.08, 308.81);
  path.lineTo(162.26, 338.7);
  path.cubicTo(187.8, 367.78, 226.2, 383.93, 266.01, 380.56);
  path.lineTo(277.54, 423.55);
  path.cubicTo(218.13, 431.41, 160.1, 406.82, 124.05, 361.64);
  path.lineTo(85.64, 384.68);
  path.cubicTo(136.25, 451.17, 223.84, 484.11, 309.61, 461.16);
  path.cubicTo(371.35, 444.64, 419.4, 402.56, 445.42, 349.38);
  path.lineTo(488.06, 364.88);
  path.cubicTo(457.17, 431.16, 398.22, 483.82, 321.99, 504.22);
  return path;
}
