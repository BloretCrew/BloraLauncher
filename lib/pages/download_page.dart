import 'package:bloret_launcher/widgets/button.dart';
import 'package:bloret_launcher/widgets/windows_widgets.dart';
import 'package:flutter/material.dart';

import '../main.dart';

class DownloadPage extends StatefulWidget {
  const DownloadPage({super.key});

  @override
  State<DownloadPage> createState() => _DownloadPageState();
}

class _DownloadPageState extends State<DownloadPage> {
  List<String> vanillaVersions = [];
  List<String> fabricVersions = [];
  List<String> forgeVersions = [];
  List<String> neoForgeVersions = [];
  List<String> javaVersions = [];

  @override
  void initState() {
    super.initState();
    _loadVersions();
  }

  void _loadVersions() {
    // TODO:
    // Backend.getVersionsByCategory()
    // Backend.getJavaDownloadVersions()

    setState(() {
      vanillaVersions = ["1.21.1", "1.20.1", "其他版本..."];
      fabricVersions = ["1.21.1", "其他版本..."];
      forgeVersions = ["1.20.1", "其他版本..."];
      neoForgeVersions = ["1.21", "其他版本..."];
      javaVersions = ["Java 17", "Java 21"];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.only(left: 32, right: 16, top: 16, bottom: 16),
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 8),
            child: Text(
              "下载",
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text("  当前下载源: bangbang93/BMCLAPI"),
          const SizedBox(height: 8),
          DownloadCard(
            image: SizedBox(width: 42, height: 42, child: Image.asset("assets/icons/mc_be.png")),
            title: "Minecraft 官方版本",
            subtitle: "下载并安装原生 Minecraft 核心",
            versions: vanillaVersions,
            onDownload: (version) {
              // TODO: Backend.downloadVanilla()
            },
          ),
          DownloadCard(
            image: SizedBox(width: 42, height: 42, child: Image.asset("assets/icons/forge.png")),
            title: "Forge Loader",
            subtitle: "安装 Forge 加载器以使用 Forge Mod",
            versions: forgeVersions,
            onDownload: (version) {
              // TODO: Backend.downloadForge()
            },
          ),
          DownloadCard(
            image: SizedBox(width: 42, height: 42, child: Image.asset("assets/icons/fabric.png")),
            title: "Fabric Loader",
            subtitle: "安装 Fabric 加载器以使用 modern Mod",
            versions: fabricVersions,
            onDownload: (version) {
              // TODO: Backend.downloadFabric()
            },
          ),

          DownloadCard(
            image: SizedBox(width: 42, height: 42, child: Image.asset("assets/icons/neoforge.png")),
            title: "NeoForge Loader",
            subtitle: "安装 NeoForge 加载器以使用 NeoForge Mod",
            versions: neoForgeVersions,
            onDownload: (version) {
              // TODO: Backend.downloadNeoForge()
            },
          ),
          DownloadCard(
            image: SizedBox(width: 42, height: 42, child: Image.asset("assets/icons/java.png")),
            title: "Java 运行时环境",
            subtitle: "运行 Minecraft 所需的 Java 环境",
            versions: javaVersions,
            onDownload: (version) {
              // TODO: Backend.downloadJava()
            },
          ),
          DownloadCard(
            image: SizedBox(width: 42, height: 42, child: Image.asset("assets/icons/ext.png")),
            title: "外部程序/整合包",
            subtitle: "添加您的自定义启动项或整合包文件",
            buttonText: "添加自定义项目",
            onPressed: () {
              // TODO: Backend.addCustomApp()
            },
          ),
          DownloadCard(
            image: SizedBox(width: 42, height: 42, child: CustomPaint(painter: ModrinthPainter(), size: const Size(42, 42))),
            title: "Modrinth 整合包",
            subtitle: "导入 .mrpack 格式的 Modrinth 整合包",
            buttonText: "导入整合包",
            onPressed: () {
              // TODO: Backend.importMrpack()
            },
          ),
        ],
      ),
    );
  }
}

class DownloadCard extends StatefulWidget {
  final Widget image;
  final String title;
  final String subtitle;
  final List<String>? versions;
  final String? badge;
  final String? buttonText;
  final Function(String)? onDownload;
  final VoidCallback? onPressed;

  const DownloadCard({
    super.key,
    required this.image,
    required this.title,
    required this.subtitle,
    this.versions,
    this.badge,
    this.buttonText,
    this.onDownload,
    this.onPressed,
  });

  @override
  State<DownloadCard> createState() => _DownloadCardState();
}

class _DownloadCardState extends State<DownloadCard> {
  String? selected;

  @override
  Widget build(BuildContext context) {
    selected ??= widget.versions?.firstOrNull;

    return FluentCard(
      child: Row(
        children: [
          widget.image,
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.badge != null)
                  Chip(label: Text(widget.badge!)),
                Text(
                  widget.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  widget.subtitle,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          if (widget.versions != null)
            SizedBox(
              width: 150,
              child: Win11Dropdown(
                initialValue: selected,
                items: widget.versions!
                    .map((e) => Win11DropdownItem(
                  value: e,
                  label: e,
                ))
                    .toList(),
                onChanged: (v) {
                  setState(() => selected = v);
                  if (v == "其他版本...") {
                    // TODO: 打开版本选择Dialog
                  }
                },
              ),
            ),
          const SizedBox(width: 12),
          BloretButton(
            onPressed: () {
              if (widget.onDownload != null) {
                widget.onDownload!(selected ?? "");
              } else {
                widget.onPressed?.call();
              }
            },
            text: widget.buttonText ?? "下载并安装",
          ),
        ],
      ),
    );
  }
}

class ModrinthPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Color(0xFF60D677)
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