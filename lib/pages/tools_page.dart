import 'dart:io';

import 'package:bloret_launcher/main.dart';
import 'package:bloret_launcher/widgets/button.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' hide Image;
import 'package:pasteboard/pasteboard.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:screen_capturer/screen_capturer.dart';

class ToolsPage extends StatefulWidget {
  const ToolsPage({super.key});

  @override
  State<ToolsPage> createState() => _ToolsPageState();
}

class _ToolsPageState extends State<ToolsPage> {
  List<dynamic> pluginToolCards = [];

  final uuidController = TextEditingController();
  final nameController = TextEditingController();
  final skinController = TextEditingController();

  String uuidResult = "查询的结果将显示在这里";
  String nameResult = "查询的结果将显示在这里";
  String skinResult = "皮肤的查询的结果";
  String capeResult = "披风的查询的结果";

  @override
  void initState() {
    super.initState();
    loadPluginToolCards();
  }

  void loadPluginToolCards() {
    // TODO PluginHost.getToolsContributionsJson()
    pluginToolCards = [];
  }

  Widget sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.only(
          left: 32,
          right: 16,
          top: 16,
          bottom: 16,
        ),
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 8, bottom: 8),
            child: Text(
              "小工具",
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          if (pluginToolCards.isNotEmpty) ...[
            sectionTitle("插件工具"),
            // TODO PluginHost Widget 加载
          ],

          sectionTitle("资源包工具"),
          const SizedBox(height: 4),
          ToolCard(
            icon: "assets/icons/resource_editor.png",
            title: "Bloret Launcher 资源包编辑器",
            subtitle: "创建和编辑 Minecraft 资源包，内置 Git 版本管理，无需编程基础",
            button: "暂未兼容",
            onPressed: null,
          ),

          sectionTitle("屏幕截图"),
          const SizedBox(height: 4),
          ToolCard(
            icon: "assets/icons/screen_cap.png",
            title: "Windows原生截图",
            subtitle: "便捷地截取屏幕画面，包括 Minecraft 窗口",
            button: "截图",
            onPressed: () async {
              await takeScreenCut();
            },
          ),

          sectionTitle("Minecraft 数据查询"),

          const SizedBox(height: 4),
          QueryCard(
            title: "查询玩家UUID",
            hint: "玩家名称（正版）",
            controller: uuidController,
            result: uuidResult,
            onQuery: () {
              setState(() {
                uuidResult = "查询中...";
              });
              // TODO Backend.queryUUID()
            },
            onCopy: () {
              // TODO copy
            },
          ),

          QueryCard(
            title: "查询玩家名字",
            hint: "玩家UUID",
            controller: nameController,
            result: nameResult,
            onQuery: () {
              setState(() {
                nameResult = "查询中...";
              });
              // TODO Backend.queryName()
            },
            onCopy: () {},
          ),

          QueryCard(
            title: "获取玩家的皮肤和披风",
            hint: "玩家UUID",
            controller: skinController,
            result: skinResult,
            extraResult: capeResult,
            onQuery: () {
              setState(() {
                skinResult = "查询中...";
                capeResult = "查询中...";
              });
              // TODO Backend.querySkin()
            },
            onCopy: () {},
          ),
        ],
      ),
    );
  }
}

class ToolCard extends StatelessWidget {
  final String icon;
  final String title;
  final String subtitle;
  final String button;
  final VoidCallback? onPressed;

  const ToolCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.button,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return FluentCard(
      child: Row(
        children: [
          Image.asset(icon, width: 40, height: 40),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          BloretButton(
            onPressed: onPressed,
            text: button,
          ),
        ],
      ),
    );
  }
}

class QueryCard extends StatelessWidget {
  final String title;
  final String hint;
  final TextEditingController controller;
  final String result;
  final String? extraResult;
  final VoidCallback onQuery;
  final VoidCallback onCopy;

  const QueryCard({
    super.key,
    required this.title,
    required this.hint,
    required this.controller,
    required this.result,
    required this.onQuery,
    required this.onCopy,
    this.extraResult,
  });

  @override
  Widget build(BuildContext context) {

    Widget resultRow(String label, String value) {
      return Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                "$label$value",
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              tooltip: "复制",
              icon: const Icon(
                Icons.copy,
                size: 16,
              ),
              onPressed: onCopy,
            ),
          ],
        ),
      );
    }


    return FluentCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),

          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    hintText: hint,
                    border: const OutlineInputBorder(
                      gapPadding: 0,
                    ),
                  ),
                )
              ),

              const SizedBox(width: 12),

              BloretButton(
                onPressed: onQuery,
                text: "查询",
              ),
            ],
          ),


          const SizedBox(height: 8),

          resultRow(
            "结果：",
            result,
          ),

          if (extraResult != null)
            resultRow(
              "",
              extraResult!,
            ),
        ],
      ),
    );
  }
}

Future<void> takeScreenCut() async {
  try {
    final image = await screenCapturer.capture(
      mode: CaptureMode.region,
    );

    if (image == null) {
      return;
    }

    final dir = await getApplicationSupportDirectory();

    final saveDir = Directory(
      p.join(dir.path, "screenshot"),
    );

    if (!await saveDir.exists()) {
      await saveDir.create(recursive: true);
    }


    final file = File(
      p.join(
        saveDir.path,
        "screenshot_${DateTime.now().millisecondsSinceEpoch}.png",
      ),
    );

    final decoded = image.imageBytes != null ?
      decodeImage(
        image.imageBytes!,
      ) : null;

    if (decoded != null) {
      Pasteboard.writeImage(
        image.imageBytes,
      );
    }


    if (image.imageBytes != null) {
      await file.writeAsBytes(image.imageBytes!);
    }


    // TODO: 写入系统图片剪贴板

    print(
      "Screenshot saved: ${file.path}",
    );

  } catch (e) {
    print(
      "Screenshot failed: $e",
    );
  }
}