import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/fake_3d_scene.dart';
import '../widgets/button.dart';
import '../core/i18n.dart';

class Fake3DEditorPage extends StatefulWidget {
  const Fake3DEditorPage({super.key});

  @override
  State<Fake3DEditorPage> createState() => _Fake3DEditorPageState();
}

class _Fake3DEditorPageState extends State<Fake3DEditorPage> {
  Polygon _model = const Polygon([], Vector3.zero(), Vector3.zero());
  Vector3 _cameraRot = const Vector3(-0.5, 0.8, 0);
  Cube? _selectedCube;
  
  final TextEditingController _jsonController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _addBasePlane();
  }

  void _addBasePlane() {
    // 不再自动添加硬编码的基准面，保持模型纯净
    setState(() {
      _model = const Polygon([], Vector3.zero(), Vector3.zero());
    });
  }

  void _addGroundHelper() {
    final floor = Cube(
      id: "ground_${DateTime.now().millisecondsSinceEpoch}",
      size: const Vector3(20, 0.2, 20),
      pos: const Vector3(0, -10, 0),
      faces: {
        'top': const FaceData(textureKey: "block/grass_block_top"),
        'bottom': const FaceData(textureKey: "block/dirt"),
      },
    );
    setState(() {
      final List<Cube> newCubes = List.from(_model.cubes)..add(floor);
      _model = Polygon(newCubes, _model.pos, _model.rot);
      _selectedCube = floor;
    });
  }

  void _addNewCube() {
    final newCube = Cube(
      id: "cube_${DateTime.now().millisecondsSinceEpoch}",
      faces: {},
      size: const Vector3.all(2),
      pos: const Vector3.zero(),
    );
    setState(() {
      final List<Cube> newCubes = List.from(_model.cubes)..add(newCube);
      _model = Polygon(newCubes, _model.pos, _model.rot);
      _selectedCube = newCube;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: Text("3D Model Editor".tl),
        actions: [
          IconButton(
            icon: const Icon(Icons.code),
            onPressed: () {
              _jsonController.text = const JsonEncoder.withIndent("  ").convert(_model.toJson());
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text("Model JSON".tl),
                  content: TextField(
                    controller: _jsonController,
                    maxLines: 15,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context), child: Text("Close".tl)),
                  ],
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.grid_4x4),
            tooltip: "Add Ground Plane".tl,
            onPressed: _addGroundHelper,
          ),
          IconButton(
            icon: const Icon(Icons.add_box_outlined),
            onPressed: _addNewCube,
          ),
        ],
      ),
      body: Row(
        children: [
          // 3D Viewport
          Expanded(
            flex: 3,
            child: Stack(
              children: [
                GestureDetector(
                  onPanUpdate: (details) {
                    setState(() {
                      // 修正操作：翻转增量符号。
                      // Y轴拖拽影响X旋转（仰角），X轴拖拽影响Y旋转（方位角）
                      _cameraRot = Vector3(
                        (_cameraRot.x - details.delta.dy * 0.01).clamp(-1.5, 1.5),
                        _cameraRot.y - details.delta.dx * 0.01,
                        _cameraRot.z,
                      );
                    });
                  },
                  child: Container(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                    child: CustomPaint(
                      painter: Fake3DScenePainter(
                        model: _model,
                        sceneRotation: _cameraRot,
                      ),
                      size: Size.infinite,
                    ),
                  ),
                ),
                // Directional Axis Gizmo
                Positioned(
                  right: 20,
                  bottom: 20,
                  child: GestureDetector(
                    onPanUpdate: (details) {
                      setState(() {
                        _cameraRot = Vector3(
                          (_cameraRot.x - details.delta.dy * 0.01).clamp(-1.5, 1.5),
                          _cameraRot.y - details.delta.dx * 0.01,
                          _cameraRot.z,
                        );
                      });
                    },
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: CustomPaint(
                        painter: _GizmoPainter(rotation: _cameraRot),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Sidebar Editor
          Container(
            width: 300,
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: theme.dividerColor)),
              color: theme.colorScheme.surface,
            ),
            child: _selectedCube == null 
              ? Center(child: Text("Select a cube to edit".tl))
              : _buildCubeEditor(theme),
          ),
        ],
      ),
    );
  }

  Widget _buildCubeEditor(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text("Editing: ${_selectedCube!.id}", style: theme.textTheme.titleMedium),
        const Divider(),
        _buildVectorEditor("Position", _selectedCube!.pos, (v) {
          _updateSelectedCube(pos: v);
        }),
        _buildVectorEditor("Rotation", _selectedCube!.rot, (v) {
          _updateSelectedCube(rot: v);
        }),
        _buildVectorEditor("Size", _selectedCube!.size, (v) {
          _updateSelectedCube(size: v);
        }),
        const SizedBox(height: 20),
        Text("Textures".tl, style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        _buildTextureInput("Front", 'front'),
        _buildTextureInput("Top", 'top'),
        const SizedBox(height: 32),
        BloretButton(
          text: "Delete Cube".tl,
          onPressed: () {
            setState(() {
              final newCubes = _model.cubes.where((c) => c.id != _selectedCube!.id).toList();
              _model = Polygon(newCubes, _model.pos, _model.rot);
              _selectedCube = null;
            });
          },
        ),
      ],
    );
  }

  Widget _buildTextureInput(String label, String side) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: TextField(
        decoration: InputDecoration(labelText: label, isDense: true),
        onChanged: (val) {
          final newFaces = Map<String, FaceData>.from(_selectedCube!.faces);
          newFaces[side] = FaceData(textureKey: val);
          _updateSelectedCube(faces: newFaces);
        },
      ),
    );
  }

  void _updateSelectedCube({Vector3? pos, Vector3? rot, Vector3? size, Map<String, FaceData>? faces}) {
    setState(() {
      final updated = Cube(
        id: _selectedCube!.id,
        parentId: _selectedCube!.parentId,
        pos: pos ?? _selectedCube!.pos,
        rot: rot ?? _selectedCube!.rot,
        size: size ?? _selectedCube!.size,
        faces: faces ?? _selectedCube!.faces,
      );
      
      final index = _model.cubes.indexWhere((c) => c.id == updated.id);
      final List<Cube> newCubes = List.from(_model.cubes);
      newCubes[index] = updated;
      _model = Polygon(newCubes, _model.pos, _model.rot);
      _selectedCube = updated;
    });
  }

  Widget _buildVectorEditor(String label, Vector3 value, Function(Vector3) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        Row(
          children: [
            Expanded(child: _buildSlider("X", value.x, -20, 20, (v) => onChanged(Vector3(v, value.y, value.z)))),
            Expanded(child: _buildSlider("Y", value.y, -20, 20, (v) => onChanged(Vector3(value.x, v, value.z)))),
            Expanded(child: _buildSlider("Z", value.z, -20, 20, (v) => onChanged(Vector3(value.x, value.y, v)))),
          ],
        ),
      ],
    );
  }

  Widget _buildSlider(String label, double value, double min, double max, Function(double) onChanged) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 10)),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _GizmoPainter extends CustomPainter {
  final Vector3 rotation;

  _GizmoPainter({required this.rotation});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const radius = 35.0;

    final xEnd = const Vector3(radius, 0, 0).rotateX(rotation.x).rotateY(rotation.y).rotateZ(rotation.z);
    final yEnd = const Vector3(0, radius, 0).rotateX(rotation.x).rotateY(rotation.y).rotateZ(rotation.z);
    final zEnd = const Vector3(0, 0, radius).rotateX(rotation.x).rotateY(rotation.y).rotateZ(rotation.z);

    void drawAxis(Vector3 end, Color color, String label) {
      final paint = Paint()
        ..color = color
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;
      
      final endOffset = center + Offset(end.x, -end.y);
      canvas.drawLine(center, endOffset, paint);
      
      final tp = TextPainter(
        text: TextSpan(text: label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 10)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, endOffset);
    }

    // Sort by depth (simplistic)
    final axes = [
      (xEnd, Colors.red, "X"),
      (yEnd, Colors.green, "Y"),
      (zEnd, Colors.blue, "Z"),
    ]..sort((a, b) => a.$1.z.compareTo(b.$1.z));

    for (var axis in axes) {
      drawAxis(axis.$1, axis.$2, axis.$3);
    }
  }

  @override
  bool shouldRepaint(covariant _GizmoPainter oldDelegate) => oldDelegate.rotation != rotation;
}
