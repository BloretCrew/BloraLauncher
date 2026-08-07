import 'dart:io';

import 'package:bloret_launcher/main.dart';
import 'package:bloret_launcher/widgets/button.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' hide Image;
import 'package:pasteboard/pasteboard.dart';
import 'package:path/path.dart' as p;
import 'package:screen_capturer/screen_capturer.dart';

import '../core/i18n.dart';
import '../services/config_service.dart';

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

  String uuidResult = "Query results will be displayed here".tl;
  String nameResult = "Query results will be displayed here".tl;
  String skinResult = "Skin query results".tl;
  String capeResult = "Cape query results".tl;

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
        padding: EdgeInsets.only(
          left: Platform.isAndroid ? 16 : 32,
          right: 16,
          top: 16,
          bottom: 16,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 8),
            child: Text(
              "Tools".tl,
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          if (pluginToolCards.isNotEmpty) ...[
            sectionTitle("Plugin Tools".tl),
            // TODO PluginHost Widget
          ],

          if (Platform.isWindows) ...[
            sectionTitle("Resource Pack Tools".tl),
            const SizedBox(height: 4),
            ToolCard(
              icon: "assets/icons/resource_editor.png",
              title: "Bloret Launcher Resource Pack Editor".tl,
              subtitle: "Create and edit Minecraft resource packs with built-in Git, no coding needed.".tl,
              button: "Incompatible".tl,
              onPressed: null,
            ),

            sectionTitle("Screenshots".tl),
            const SizedBox(height: 4),
            ToolCard(
              icon: "assets/icons/screen_cap.png",
              title: "Native Windows Screenshot".tl,
              subtitle: "Easily capture screen content, including Minecraft windows.".tl,
              button: "Capture".tl,
              onPressed: () async {
                await takeScreenCut();
              },
            ),
          ],

          sectionTitle("Minecraft Data Query".tl),

          const SizedBox(height: 4),
          QueryCard(
            title: "Query Player UUID".tl,
            hint: "Player Name (Official)".tl,
            controller: uuidController,
            result: uuidResult,
            onQuery: () {
              setState(() {
                uuidResult = "Querying...".tl;
              });
              // TODO Backend.queryUUID()
            },
            onCopy: () {
              // TODO copy
            },
          ),

          QueryCard(
            title: "Query Player Name".tl,
            hint: "Player UUID".tl,
            controller: nameController,
            result: nameResult,
            onQuery: () {
              setState(() {
                nameResult = "Querying...".tl;
              });
              // TODO Backend.queryName()
            },
            onCopy: () {},
          ),

          QueryCard(
            title: "Get Player Skin & Cape".tl,
            hint: "Player UUID".tl,
            controller: skinController,
            result: skinResult,
            extraResult: capeResult,
            onQuery: () {
              setState(() {
                skinResult = "Querying...".tl;
                capeResult = "Querying...".tl;
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
              tooltip: "Copy".tl,
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
                text: "Query".tl,
              ),
            ],
          ),


          const SizedBox(height: 8),

          resultRow(
            "Result: ".tl,
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

    final dir = await getSupportData();

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

    logger.info(
      "Screenshot saved: ${file.path}",
      .tool
    );

  } catch (e) {
    logger.error(
      "Screenshot failed: $e",
      .tool
    );
  }
}