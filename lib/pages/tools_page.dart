import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bloret_launcher/main.dart';
import 'package:bloret_launcher/services/plugin_service.dart';
import 'package:bloret_launcher/widgets/button.dart';
import 'package:dio/dio.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' hide Image;
import 'package:pasteboard/pasteboard.dart';
import 'package:path/path.dart' as p;
import 'package:screen_capturer/screen_capturer.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors, Matrix4;

import '../core/grammer_candy.dart';
import '../core/i18n.dart';
import '../services/config_service.dart';

class ToolsPage extends StatefulWidget {
  const ToolsPage({super.key});

  @override
  State<ToolsPage> createState() => _ToolsPageState();
}

enum ArmType { normal, thin }

class _ToolsPageState extends State<ToolsPage> with TickerProviderStateMixin {
  final uuidController = TextEditingController();
  final nameController = TextEditingController();
  final skinController = TextEditingController();

  String uuidResult = "Query results will be displayed here".tl;
  String nameResult = "Query results will be displayed here".tl;
  String skinResult = "Skin query results".tl;
  String capeResult = "Cape query results".tl;

  ui.Image? skinImage;
  ui.Image? capeImage;
  bool isQueryingSkin = false;
  ArmType armType = ArmType.normal;

  late AnimationController _skinViewAnimController;

  final Dio _dio = Dio();

  @override
  void initState() {
    super.initState();
    _skinViewAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
  }

  @override
  void dispose() {
    _skinViewAnimController.dispose();
    super.dispose();
  }

  Future<void> _autoDetectArmType(ui.Image image) async {
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) return;

    // 判断 4px/3px 手臂逻辑：
    // 在 64x64 格式下，左臂顶面/底面起始点为 (36, 48)
    // 4px 模型总宽度为 8 (4+4)，3px 模型总宽度为 6 (3+3)
    // 如果 (42, 48) 到 (43, 51) 区域（即 4px 多出的那 2 列）有任何非透明像素，则判定为 4px
    bool isNormal = false;
    for (int x = 42; x <= 43; x++) {
      for (int y = 48; y < 52; y++) {
        int alphaIndex = (y * image.width + x) * 4 + 3;
        if (alphaIndex < byteData.lengthInBytes) {
          if (byteData.getUint8(alphaIndex) > 0) {
            isNormal = true;
            break;
          }
        }
      }
      if (isNormal) break;
    }

    if (mounted) {
      setState(() {
        armType = isNormal ? ArmType.normal : ArmType.thin;
      });
    }
  }

  Future<void> _queryUUID() async {
    final name = uuidController.text.trim();
    if (name.isEmpty) return;

    setState(() => uuidResult = "Querying...".tl);
    try {
      final response = await _dio.get(
        "https://api.mojang.com/users/profiles/minecraft/$name",
      );
      if (response.statusCode == 200) {
        setState(() => uuidResult = response.data['id'] ?? "No UUID found".tl);
      } else {
        setState(() => uuidResult = "User not found".tl);
      }
    } catch (e) {
      setState(() => uuidResult = "Error: $e".tl);
    }
  }

  Future<void> _queryName() async {
    final uuid = nameController.text.trim();
    if (uuid.isEmpty) return;

    setState(() => nameResult = "Querying...".tl);
    try {
      final response = await _dio.get(
        "https://sessionserver.mojang.com/session/minecraft/profile/$uuid",
      );
      if (response.statusCode == 200) {
        setState(
          () => nameResult = response.data['name'] ?? "No name found".tl,
        );
      } else {
        setState(() => nameResult = "User not found".tl);
      }
    } catch (e) {
      setState(() => nameResult = "Error: $e".tl);
    }
  }

  Future<void> _querySkin() async {
    final input = skinController.text.trim();
    if (input.isEmpty) return;

    setState(() {
      skinResult = "Querying...".tl;
      capeResult = "Querying...".tl;
      isQueryingSkin = true;
      skinImage = null;
      capeImage = null;
    });
    _skinViewAnimController.reset();

    try {
      String uuid = input;
      // If not a standard UUID (length check), try resolving name to UUID
      if (input.length < 32) {
        final nameRes = await _dio.get(
          "https://api.mojang.com/users/profiles/minecraft/$input",
        );
        if (nameRes.statusCode == 200 && nameRes.data['id'] != null) {
          uuid = nameRes.data['id'];
        } else {
          throw Exception("User not found".tl);
        }
      }

      final response = await _dio.get(
        "https://sessionserver.mojang.com/session/minecraft/profile/$uuid",
      );
      if (response.statusCode == 200) {
        final properties = response.data['properties'] as List?;
        if (properties != null) {
          for (var prop in properties) {
            if (prop['name'] == 'textures') {
              final decoded = utf8.decode(base64.decode(prop['value']));
              final textures = jsonDecode(decoded);
              final skinUrl = textures['textures']?['SKIN']?['url'];
              final capeUrl = textures['textures']?['CAPE']?['url'];

              setState(() {
                skinResult = skinUrl ?? "No skin found".tl;
                capeResult = capeUrl ?? "No cape found".tl;
              });

              final List<Future> tasks = [];
              if (skinUrl != null) {
                tasks.add(() async {
                  final skinRes = await _dio.get<List<int>>(
                    skinUrl,
                    options: Options(responseType: ResponseType.bytes),
                  );
                  if (skinRes.data != null) {
                    final codec = await ui.instantiateImageCodec(
                      Uint8List.fromList(skinRes.data!),
                    );
                    final frame = await codec.getNextFrame();
                    skinImage = frame.image;
                    await _autoDetectArmType(frame.image);
                  }
                }());
              }
              if (capeUrl != null) {
                tasks.add(() async {
                  final capeRes = await _dio.get<List<int>>(
                    capeUrl,
                    options: Options(responseType: ResponseType.bytes),
                  );
                  if (capeRes.data != null) {
                    final codec = await ui.instantiateImageCodec(
                      Uint8List.fromList(capeRes.data!),
                    );
                    final frame = await codec.getNextFrame();
                    capeImage = frame.image;
                  }
                }());
              }

              if (tasks.isNotEmpty) {
                await Future.wait(tasks);
                if (mounted) {
                  setState(() {});
                  _skinViewAnimController.forward();
                }
              }
              return;
            }
          }
        }
        setState(() {
          skinResult = "No textures found".tl;
          capeResult = "No textures found".tl;
        });
      } else {
        setState(() {
          skinResult = "User not found".tl;
          capeResult = "User not found".tl;
        });
      }
    } catch (e) {
      setState(() {
        skinResult = "Error: $e".tl;
        capeResult = "Error: $e".tl;
      });
    } finally {
      if (mounted) {
        setState(() {
          isQueryingSkin = false;
        });
      }
    }
  }

  Widget _buildArmOption(ArmType type, String label) {
    final isSelected = armType == type;
    return GestureDetector(
      onTap: () => setState(() => armType = type),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Colors.transparent,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? Theme.of(context).colorScheme.primary : null,
            ),
          ),
        ),
      ),
    );
  }

  Widget sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Text(
        text,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PluginService.instance,
      builder: (context, _) {
        final pluginToolCards = PluginService.instance.getToolsContributions();

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
                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                ),
              ),

              if (pluginToolCards.isNotEmpty) ...[
                sectionTitle("Plugin Tools".tl),
                const SizedBox(height: 4),
                ...pluginToolCards.map((card) {
                  final String? pluginId = card['_pluginId'];
                  final plugin = PluginService.instance.plugins.firstWhere((p) => p.id == pluginId);
                  
                  return ToolCard(
                    icon: card['icon'] ?? "assets/icons/default_plugin.png",
                    title: plugin.resolve(card['title'] ?? "Plugin Tool"),
                    subtitle: plugin.resolve(card['subtitle'] ?? ""),
                    button: plugin.resolve(card['button'] ?? "Open"),
                    onPressed: () => PluginService.instance.runToolAction(card),
                  );
                }),
              ],

          if (Platform.isWindows) ...[
            sectionTitle("Resource Pack Tools".tl),
            const SizedBox(height: 4),
            ToolCard(
              icon: "assets/icons/resource_editor.png",
              title: "Bloret Launcher Resource Pack Editor".tl,
              subtitle:
                  "Create and edit Minecraft resource packs with built-in Git, no coding needed."
                      .tl,
              button: "Incompatible".tl,
              onPressed: null,
            ),

            sectionTitle("Screenshots".tl),
            const SizedBox(height: 4),
            ToolCard(
              icon: "assets/icons/screen_cap.png",
              title: "Native Windows Screenshot".tl,
              subtitle:
                  "Easily capture screen content, including Minecraft windows."
                      .tl,
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
            onQuery: _queryUUID,
            onCopy: () {
              Clipboard.setData(ClipboardData(text: uuidResult));
              showSuccess("UUID copied to clipboard".tl);
            },
          ),

          QueryCard(
            title: "Query Player Name".tl,
            hint: "Player UUID".tl,
            controller: nameController,
            result: nameResult,
            onQuery: _queryName,
            onCopy: () {
              Clipboard.setData(ClipboardData(text: nameResult));
              showSuccess("Player Name copied to clipboard".tl);
            },
          ),

          QueryCard(
            title: "Get Player Skin & Cape".tl,
            hint: "Player Name / UUID".tl,
            controller: skinController,
            result: skinResult,
            extraResult: capeResult,
            onQuery: _querySkin,
            onCopy: () {
              Clipboard.setData(ClipboardData(text: skinResult));
              showSuccess("Skin URL copied to clipboard".tl);
            },
            onCopyExtra: () {
              Clipboard.setData(ClipboardData(text: capeResult));
              showSuccess("Cape URL copied to clipboard".tl);
            },

            bottomWidget: ConfigService.get("Bloret_PassPort_Login") == true ? (skinImage != null
                ? FadeTransition(
                    opacity: _skinViewAnimController,
                    child: SlideTransition(
                      position:
                          Tween<Offset>(
                            begin: const Offset(0, 0.1),
                            end: Offset.zero,
                          ).animate(
                            CurvedAnimation(
                              parent: _skinViewAnimController,
                              curve: Curves.easeOutCubic,
                            ),
                          ),
                      child: Column(
                        mainAxisSize: .min,
                        children: [
                          Container(
                            height: 320,
                            margin: const EdgeInsets.only(top: 12),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                // Left controls
                                Container(
                                  width: 80,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border(
                                      right: BorderSide(
                                        color: Colors.grey.withValues(
                                          alpha: 0.1,
                                        ),
                                      ),
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      Text(
                                        "Arm".tl,
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      _buildArmOption(ArmType.normal, "4px"),
                                      _buildArmOption(ArmType.thin, "3px"),
                                    ],
                                  ),
                                ),
                                // 3D Viewer
                                Expanded(
                                  flex: 3,
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 600),
                                    switchInCurve: Curves.easeInOutCubic,
                                    switchOutCurve: Curves.easeInOutCubic,
                                    transitionBuilder:
                                        (
                                          Widget child,
                                          Animation<double> animation,
                                        ) {
                                          return ScaleTransition(
                                            scale: animation,
                                            child: FadeTransition(
                                              opacity: animation,
                                              child: child,
                                            ),
                                          );
                                        },
                                    child: skinImage != null
                                        ? MinecraftSkinViewer(
                                            key: ValueKey(
                                              "viewer_${skinImage.hashCode}",
                                            ),
                                            image: skinImage!,
                                            capeImage: capeImage,
                                            armType: armType,
                                          )
                                        : const Center(
                                            key: ValueKey("loading"),
                                            child: CircularProgressIndicator(),
                                          ),
                                  ),
                                ),
                                // 2D Plane Preview
                                Container(
                                  width: 100,
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    border: Border(
                                      left: BorderSide(
                                        color: Colors.grey.withValues(
                                          alpha: 0.1,
                                        ),
                                      ),
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      Text(
                                        "Texture".tl,
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Expanded(
                                        child: ListView(
                                          children: [
                                            if (skinImage != null) ...[
                                              Text(
                                                "Skin".tl,
                                                style: const TextStyle(
                                                  fontSize: 8,
                                                  color: Colors.grey,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              RawImage(
                                                image: skinImage,
                                                filterQuality:
                                                    FilterQuality.none,
                                                fit: BoxFit.contain,
                                              ),
                                              const SizedBox(height: 12),
                                            ],
                                            if (capeImage != null) ...[
                                              Text(
                                                "Cape".tl,
                                                style: const TextStyle(
                                                  fontSize: 8,
                                                  color: Colors.grey,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              RawImage(
                                                image: capeImage,
                                                filterQuality:
                                                    FilterQuality.none,
                                                fit: BoxFit.contain,
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : isQueryingSkin
                ? const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : null) : null,
          ),
        ],
      ),
    );
      },
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
                Text(subtitle, style: TextStyle(color: Colors.grey.shade600)),
              ],
            ),
          ),
          BloretButton(onPressed: onPressed, text: button),
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
  final VoidCallback? onCopyExtra;
  final Widget? bottomWidget;

  const QueryCard({
    super.key,
    required this.title,
    required this.hint,
    required this.controller,
    required this.result,
    required this.onQuery,
    required this.onCopy,
    this.onCopyExtra,
    this.extraResult,
    this.bottomWidget,
  });

  @override
  Widget build(BuildContext context) {
    Widget resultRow(String label, String value, VoidCallback copyCallback) {
      return Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (Widget child, Animation<double> animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0.0, 0.2),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: Text(
                  "$label$value",
                  key: ValueKey<String>(value),
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.start,
                ),
              ),
            ),
            IconButton(
              tooltip: "Copy".tl,
              icon: const Icon(Icons.copy, size: 16),
              onPressed: copyCallback,
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
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    hintText: hint,
                    border: const OutlineInputBorder(gapPadding: 0),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              BloretButton(onPressed: onQuery, text: "Query".tl),
            ],
          ),
          const SizedBox(height: 8),
          resultRow("Result: ".tl, result, onCopy),
          if (extraResult != null)
            resultRow("", extraResult!, onCopyExtra ?? onCopy),
          ?bottomWidget,
        ],
      ),
    );
  }
}

class MinecraftSkinViewer extends StatefulWidget {
  final ui.Image image;
  final ui.Image? capeImage;
  final ArmType armType;
  const MinecraftSkinViewer({
    super.key,
    required this.image,
    this.capeImage,
    required this.armType,
  });

  @override
  State<MinecraftSkinViewer> createState() => _MinecraftSkinViewerState();
}

class _MinecraftSkinViewerState extends State<MinecraftSkinViewer> {
  double rotationX = -0.2;
  double rotationY = 0.5;
  double scale = 12.0;
  double _baseScale = 12.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onScaleStart: (details) {
        _baseScale = scale;
      },
      onScaleUpdate: (details) {
        setState(() {
          if (details.scale != 1.0) {
            scale = (_baseScale * details.scale).clamp(4.0, 50.0);
          }
          rotationY += details.focalPointDelta.dx * 0.01;
          rotationX = (rotationX - details.focalPointDelta.dy * 0.01).clamp(
            -math.pi / 2.2,
            math.pi / 2.2,
          );
        });
      },
      child: Listener(
        onPointerSignal: (event) {
          if (event is PointerScrollEvent) {
            setState(() {
              scale = (scale - event.scrollDelta.dy * 0.01).clamp(4.0, 50.0);
            });
          }
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: CustomPaint(
            painter: Skin3DPainter(
              widget.image,
              widget.capeImage,
              rotationX,
              rotationY,
              scale,
              widget.armType,
            ),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }
}

class Skin3DPainter extends CustomPainter {
  final ui.Image image;
  final ui.Image? capeImage;
  final double rotationX;
  final double rotationY;
  final double scale;
  final ArmType armType;

  Skin3DPainter(
    this.image,
    this.capeImage,
    this.rotationX,
    this.rotationY,
    this.scale,
    this.armType,
  );

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    canvas.translate(center.dx, center.dy);

    final matrix = Matrix4.identity()
      ..setEntry(3, 2, 0.0)
      ..rotateX(rotationX)
      ..rotateY(rotationY)
      ..scaleByDouble(scale, scale, scale, 1.0);

    final List<_FaceData> faces = [];
    final double aw = armType == ArmType.thin ? 3 : 4;

    // Head
    _addPart(
      faces,
      8,
      8,
      8,
      0,
      -10,
      0,
      f: const Rect.fromLTWH(8, 8, 8, 8),
      ba: const Rect.fromLTWH(24, 8, 8, 8),
      l: const Rect.fromLTWH(0, 8, 8, 8),
      r: const Rect.fromLTWH(16, 8, 8, 8),
      t: const Rect.fromLTWH(8, 0, 8, 8),
      bo: const Rect.fromLTWH(16, 0, 8, 8),
    );
    // Hat
    _addPart(
      faces,
      8.5,
      8.5,
      8.5,
      0,
      -10,
      0,
      f: const Rect.fromLTWH(40, 8, 8, 8),
      ba: const Rect.fromLTWH(56, 8, 8, 8),
      l: const Rect.fromLTWH(32, 8, 8, 8),
      r: const Rect.fromLTWH(48, 8, 8, 8),
      t: const Rect.fromLTWH(40, 0, 8, 8),
      bo: const Rect.fromLTWH(48, 0, 8, 8),
    );

    // Torso
    _addPart(
      faces,
      8,
      12,
      4,
      0,
      0,
      0,
      f: const Rect.fromLTWH(20, 20, 8, 12),
      ba: const Rect.fromLTWH(32, 20, 8, 12),
      l: const Rect.fromLTWH(16, 20, 4, 12),
      r: const Rect.fromLTWH(28, 20, 4, 12),
      t: const Rect.fromLTWH(20, 16, 8, 4),
      bo: const Rect.fromLTWH(28, 16, 8, 4),
    );
    // Jacket
    _addPart(
      faces,
      8.5,
      12.5,
      4.5,
      0,
      0,
      0,
      f: const Rect.fromLTWH(20, 36, 8, 12),
      ba: const Rect.fromLTWH(32, 36, 8, 12),
      l: const Rect.fromLTWH(16, 36, 4, 12),
      r: const Rect.fromLTWH(28, 36, 4, 12),
      t: const Rect.fromLTWH(20, 32, 8, 4),
      bo: const Rect.fromLTWH(28, 32, 8, 4),
    );

    // Right Arm
    double raX = armType == ArmType.thin ? -5.5 : -6;
    _addPart(
      faces,
      aw,
      12,
      4,
      raX,
      0,
      0,
      f: Rect.fromLTWH(44, 20, aw, 12),
      ba: Rect.fromLTWH(44 + aw + 4, 20, aw, 12),
      l: const Rect.fromLTWH(40, 20, 4, 12),
      r: Rect.fromLTWH(44 + aw, 20, 4, 12),
      t: Rect.fromLTWH(44, 16, aw, 4),
      bo: Rect.fromLTWH(44 + aw, 16, aw, 4),
    );
    // Right Sleeve
    _addPart(
      faces,
      aw + 0.5,
      12.5,
      4.5,
      raX,
      0,
      0,
      f: Rect.fromLTWH(44, 36, aw, 12),
      ba: Rect.fromLTWH(44 + aw + 4, 36, aw, 12),
      l: const Rect.fromLTWH(40, 36, 4, 12),
      r: Rect.fromLTWH(44 + aw, 36, 4, 12),
      t: Rect.fromLTWH(44, 32, aw, 4),
      bo: Rect.fromLTWH(44 + aw, 32, aw, 4),
    );

    // Left Arm
    double laX = armType == ArmType.thin ? 5.5 : 6;
    _addPart(
      faces,
      aw,
      12,
      4,
      laX,
      0,
      0,
      f: Rect.fromLTWH(36, 52, aw, 12),
      ba: Rect.fromLTWH(36 + aw + 4, 52, aw, 12),
      l: const Rect.fromLTWH(32, 52, 4, 12),
      r: Rect.fromLTWH(36 + aw, 52, 4, 12),
      t: Rect.fromLTWH(36, 48, aw, 4),
      bo: Rect.fromLTWH(36 + aw, 48, aw, 4),
    );
    // Left Sleeve
    _addPart(
      faces,
      aw + 0.5,
      12.5,
      4.5,
      laX,
      0,
      0,
      f: Rect.fromLTWH(52, 52, aw, 12),
      ba: Rect.fromLTWH(52 + aw + 4, 52, aw, 12),
      l: const Rect.fromLTWH(48, 52, 4, 12),
      r: Rect.fromLTWH(52 + aw, 52, 4, 12),
      t: Rect.fromLTWH(52, 48, aw, 4),
      bo: Rect.fromLTWH(52 + aw, 48, aw, 4),
    );

    // Right Leg
    _addPart(
      faces,
      4,
      12,
      4,
      -2,
      12,
      0,
      f: const Rect.fromLTWH(4, 20, 4, 12),
      ba: const Rect.fromLTWH(12, 20, 4, 12),
      l: const Rect.fromLTWH(0, 20, 4, 12),
      r: const Rect.fromLTWH(8, 20, 4, 12),
      t: const Rect.fromLTWH(4, 16, 4, 4),
      bo: const Rect.fromLTWH(8, 16, 4, 4),
    );
    // Right Pant Leg
    _addPart(
      faces,
      4.5,
      12.5,
      4.5,
      -2,
      12,
      0,
      f: const Rect.fromLTWH(4, 36, 4, 12),
      ba: const Rect.fromLTWH(12, 36, 4, 12),
      l: const Rect.fromLTWH(0, 36, 4, 12),
      r: const Rect.fromLTWH(8, 36, 4, 12),
      t: const Rect.fromLTWH(4, 32, 4, 4),
      bo: const Rect.fromLTWH(8, 32, 4, 4),
    );

    // Left Leg
    _addPart(
      faces,
      4,
      12,
      4,
      2,
      12,
      0,
      f: const Rect.fromLTWH(20, 52, 4, 12),
      ba: const Rect.fromLTWH(28, 52, 4, 12),
      l: const Rect.fromLTWH(16, 52, 4, 12),
      r: const Rect.fromLTWH(24, 52, 4, 12),
      t: const Rect.fromLTWH(20, 48, 4, 4),
      bo: const Rect.fromLTWH(24, 48, 4, 4),
    );
    // Left Pant Leg
    _addPart(
      faces,
      4.5,
      12.5,
      4.5,
      2,
      12,
      0,
      f: const Rect.fromLTWH(4, 52, 4, 12),
      ba: const Rect.fromLTWH(12, 52, 4, 12),
      l: const Rect.fromLTWH(0, 52, 4, 12),
      r: const Rect.fromLTWH(8, 52, 4, 12),
      t: const Rect.fromLTWH(4, 48, 4, 4),
      bo: const Rect.fromLTWH(8, 48, 4, 4),
    );

    // Cape with Curvature
    if (capeImage != null) {
      _addCape(faces, capeImage!, 0, 0, -2.1);
    }

    // Painter's algorithm
    for (var face in faces) {
      final transformedCenter = matrix.transform3(face.center.clone());
      face.z = transformedCenter.z;
    }
    faces.sort((a, b) => a.z.compareTo(b.z));

    final paint = Paint()..filterQuality = ui.FilterQuality.none;
    for (var face in faces) {
      final worldMatrix = matrix * face.localMatrix;
      final normal = Vector3(0, 0, 1);
      final transformedNormal = worldMatrix.getRotation().transformed(normal);
      if (transformedNormal.z > 0) {
        canvas.save();
        canvas.transform(worldMatrix.storage);
        canvas.drawImageRect(face.img ?? image, face.src, face.dest, paint);
        canvas.restore();
      }
    }
  }

  /// Adds 6 faces of a standard cuboid part (head, torso, limbs) to the [faces] list.
  /// Handles local matrix generation for each face and assigns their world centers for depth sorting.
  ///
  /// `faces` The target list to store generated face data.
  ///
  /// `w` The width (X-axis) of the cuboid.
  ///
  /// `h` The height (Y-axis) of the cuboid.
  ///
  /// `d` The depth (Z-axis) of the cuboid.
  ///
  /// `px` The local X position of the cuboid's center.
  ///
  /// `py` The local Y position of the cuboid's center.
  ///
  /// `pz` The local Z position of the cuboid's center.
  ///
  /// `f` UV [Rect] for the Front face.
  ///
  /// `ba` UV [Rect] for the Back face.
  ///
  /// `l` UV [Rect] for the Left face.
  ///
  /// `r` UV [Rect] for the Right face.
  ///
  /// `t` UV [Rect] for the Top face.
  ///
  /// `bo` UV [Rect] for the Bottom face.
  void _addPart(
    List<_FaceData> faces,
    double w,
    double h,
    double d,
    double px,
    double py,
    double pz, {
    required Rect f,
    required Rect ba,
    required Rect l,
    required Rect r,
    required Rect t,
    required Rect bo,
  }) {
    faces.add(
      _FaceData(
        f,
        Rect.fromLTWH(-w / 2, -h / 2, w, h),
        Matrix4.identity()..translateByDouble(px, py, pz + d / 2, 1.0),
        Vector3(px, py, pz + d / 2),
      ),
    );

    faces.add(
      _FaceData(
        ba,
        Rect.fromLTWH(-w / 2, -h / 2, w, h),
        Matrix4.identity()
          ..translateByDouble(px, py, pz - d / 2, 1.0)
          ..rotateY(math.pi),
        Vector3(px, py, pz - d / 2),
      ),
    );

    faces.add(
      _FaceData(
        l,
        Rect.fromLTWH(-d / 2, -h / 2, d, h),
        Matrix4.identity()
          ..translateByDouble(px - w / 2, py, pz, 1.0)
          ..rotateY(-math.pi / 2),
        Vector3(px - w / 2, py, pz),
      ),
    );

    faces.add(
      _FaceData(
        r,
        Rect.fromLTWH(-d / 2, -h / 2, d, h),
        Matrix4.identity()
          ..translateByDouble(px + w / 2, py, pz, 1.0)
          ..rotateY(math.pi / 2),
        Vector3(px + w / 2, py, pz),
      ),
    );

    faces.add(
      _FaceData(
        t,
        Rect.fromLTWH(-w / 2, -d / 2, w, d),
        Matrix4.identity()
          ..translateByDouble(px, py - h / 2, pz, 1.0)
          ..rotateX(math.pi / 2),
        Vector3(px, py - h / 2, pz),
      ),
    );

    faces.add(
      _FaceData(
        bo,
        Rect.fromLTWH(-w / 2, -d / 2, w, d),
        Matrix4.identity()
          ..translateByDouble(px, py + h / 2, pz, 1.0)
          ..rotateX(-math.pi / 2),
        Vector3(px, py + h / 2, pz),
      ),
    );
  }

  /// Adds a cape as a rigid 6-faced cuboid with a specific pivot-point rotation at the neck.
  /// The internal [swingAngle] determines the "flowing" degree of the cape.
  ///
  /// `faces` The target list to store generated face data.
  ///
  /// `img` The texture image of the cape.
  ///
  /// `px` The attachment X position on the player's back.
  ///
  /// `py` The attachment Y position on the player's back.
  ///
  /// `pz` The attachment Z position on the player's back.
  void _addCape(
    List<_FaceData> faces,
    ui.Image img,
    double px,
    double py,
    double pz,
  ) {
    const double cw = 10.0;
    const double ch = 16.0;
    const double cd = 1.0;

    final double swingAngle = -0.2;

    final Matrix4 baseCapeMatrix = Matrix4.identity()
      ..translateByDouble(px, py - 6, pz, 1.0)
      ..rotateX(swingAngle)
      ..translateByDouble(0, ch / 2, -cd / 2, 1.0);

    void addCapeFace(Rect src, Rect dest, Matrix4 offset, Vector3 localCenter) {
      final finalMatrix = baseCapeMatrix * offset;
      final worldCenter = baseCapeMatrix.transform3(localCenter.clone());
      faces.add(_FaceData(src, dest, finalMatrix, worldCenter, img: img));
    }

    addCapeFace(
      const Rect.fromLTWH(1, 1, 10, 16),
      const Rect.fromLTWH(-cw / 2, -ch / 2, cw, ch),
      Matrix4.identity()
        ..translateByDouble(0, 0, -cd / 2, 1.0)
        ..rotateY(math.pi),
      Vector3(0, 0, -cd / 2),
    );
    addCapeFace(
      const Rect.fromLTWH(12, 1, 10, 16),
      const Rect.fromLTWH(-cw / 2, -ch / 2, cw, ch),
      Matrix4.identity()..translateByDouble(0, 0, cd / 2, 1.0),
      Vector3(0, 0, cd / 2),
    );
    // Top Face
    addCapeFace(
      const Rect.fromLTWH(1, 0, 10, 1),
      const Rect.fromLTWH(-cw / 2, -cd / 2, cw, cd),
      Matrix4.identity()
        ..translateByDouble(0, -ch / 2, 0, 1.0)
        ..rotateX(math.pi / 2),
      Vector3(0, -ch / 2, 0),
    );
    // Bottom Face
    addCapeFace(
      const Rect.fromLTWH(11, 0, 10, 1),
      const Rect.fromLTWH(-cw / 2, -cd / 2, cw, cd),
      Matrix4.identity()
        ..translateByDouble(0, ch / 2, 0, 1.0)
        ..rotateX(-math.pi / 2),
      Vector3(0, ch / 2, 0),
    );
    // Left Side
    addCapeFace(
      const Rect.fromLTWH(0, 1, 1, 16),
      const Rect.fromLTWH(-cd / 2, -ch / 2, cd, ch),
      Matrix4.identity()
        ..translateByDouble(-cw / 2, 0, 0, 1.0)
        ..rotateY(-math.pi / 2),
      Vector3(-cw / 2, 0, 0),
    );
    // Right Side
    addCapeFace(
      const Rect.fromLTWH(11, 1, 1, 16),
      const Rect.fromLTWH(-cd / 2, -ch / 2, cd, ch),
      Matrix4.identity()
        ..translateByDouble(cw / 2, 0, 0, 1.0)
        ..rotateY(math.pi / 2),
      Vector3(cw / 2, 0, 0),
    );
  }

  @override
  bool shouldRepaint(covariant Skin3DPainter oldDelegate) =>
      oldDelegate.rotationX != rotationX ||
      oldDelegate.rotationY != rotationY ||
      oldDelegate.scale != scale ||
      oldDelegate.image != image ||
      oldDelegate.capeImage != capeImage ||
      oldDelegate.armType != armType;
}

class _FaceData {
  final Rect src;
  final Rect dest;
  final Matrix4 localMatrix;
  final Vector3 center;
  final ui.Image? img;
  final int priority;
  double z = 0;

  _FaceData(this.src, this.dest, this.localMatrix, this.center, {this.img})
    : priority = 0;
}

Future<void> takeScreenCut() async {
  try {
    final image = await screenCapturer.capture(mode: CaptureMode.region);

    if (image == null) {
      return;
    }

    final dir = await getSupportData();

    final saveDir = Directory(p.join(dir.path, "screenshot"));

    if (!await saveDir.exists()) {
      await saveDir.create(recursive: true);
    }

    final file = File(
      p.join(
        saveDir.path,
        "screenshot_${DateTime.now().millisecondsSinceEpoch}.png",
      ),
    );

    final decoded = image.imageBytes != null
        ? decodeImage(image.imageBytes!)
        : null;

    if (decoded != null) {
      Pasteboard.writeImage(image.imageBytes);
    }

    if (image.imageBytes != null) {
      await file.writeAsBytes(image.imageBytes!);
    }

    logger.info("Screenshot saved: ${file.path}", .tool);
  } catch (e) {
    logger.error("Screenshot failed: $e", .tool);
  }
}
