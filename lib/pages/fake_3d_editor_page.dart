import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as vmath show Vector3, Matrix3;
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
  Vector3 _cameraPan = const Vector3.zero();
  double _viewerDistance = 100.0;
  double _startViewerDistance = 100.0;
  Cube? _selectedCube;
  String? _hoveredCubeId;
  String? _hoveredGizmoAxis;
  bool _enableLighting = true;
  GizmoMode _gizmoMode = GizmoMode.move;
  String? _activeGizmoAxis;
  
  final TextEditingController _jsonController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _addBasePlane();
    TextureRegistry.instance.initialize().then((_) => setState(() {}));
  }

  void _addBasePlane() => setState(() => _model = const Polygon([], Vector3.zero(), Vector3.zero()));

  void _addGroundHelper() {
    final floor = Cube(id: "ground_${DateTime.now().millisecondsSinceEpoch}", size: const Vector3(24, 0.2, 24), pos: const Vector3(0, -8.1, 0), faces: {'top': const FaceData(textureKey: "block/grass_block_top"), 'bottom': const FaceData(textureKey: "block/dirt")});
    setState(() { _model = Polygon(List.from(_model.cubes)..add(floor), _model.pos, _model.rot); _selectedCube = floor; });
  }

  void _addNewCube() {
    final newCube = Cube(id: "cube_${DateTime.now().millisecondsSinceEpoch}", faces: {}, size: const Vector3.all(2), pos: const Vector3.zero());
    setState(() { _model = Polygon(List.from(_model.cubes)..add(newCube), _model.pos, _model.rot); _selectedCube = newCube; });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text("${"3D Model Editor".tl} (WIP)"),
        actions: [
          _buildGizmoToggle(),
          const SizedBox(width: 4,),
          IconButton(icon: Icon(_enableLighting ? Icons.lightbulb : Icons.lightbulb_outline), tooltip: "Toggle Lighting".tl, onPressed: () => setState(() => _enableLighting = !_enableLighting)),
          IconButton(icon: const Icon(Icons.code), onPressed: () { _jsonController.text = const JsonEncoder.withIndent("  ").convert(_model.toJson()); showDialog(context: context, builder: (context) => AlertDialog(title: Text("Model JSON".tl), content: TextField(controller: _jsonController, maxLines: 15, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)), actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text("Close".tl))])); }),
          IconButton(icon: const Icon(Icons.grid_4x4), tooltip: "Add Ground Plane".tl, onPressed: _addGroundHelper),
          IconButton(icon: const Icon(Icons.add_box_outlined), onPressed: _addNewCube),
        ],
      ),
      body: Row(
        children: [
          Expanded(flex: 3, child: LayoutBuilder(builder: (context, constraints) {
            final viewportSize = Size(constraints.maxWidth, constraints.maxHeight);
            return Stack(children: [
              Listener(
                behavior: HitTestBehavior.opaque,
                onPointerPanZoomStart: (event) => _startViewerDistance = _viewerDistance,
                onPointerPanZoomUpdate: (event) { setState(() { double effectiveScale = 1.0 + (event.scale - 1.0) * 2; _viewerDistance = (_startViewerDistance / effectiveScale).clamp(50.0, 600.0); if (event.scale == 1.0) _cameraPan = Vector3(_cameraPan.x + event.panDelta.dx, _cameraPan.y + event.panDelta.dy, 0); }); },
                onPointerHover: (event) {
                  final hitCube = Fake3DScenePainter.getCubeAtPoint(event.localPosition, viewportSize, _model, _cameraRot, _cameraPan, _viewerDistance, 600);
                  String? hitAxis;
                  if (_selectedCube != null) hitAxis = Fake3DScenePainter.getGizmoAxisAtPoint(event.localPosition, viewportSize, _selectedCube!, _model, _cameraRot, _cameraPan, _viewerDistance, 600, _gizmoMode);
                  if (hitCube != _hoveredCubeId || hitAxis != _hoveredGizmoAxis) setState(() { _hoveredCubeId = hitCube; _hoveredGizmoAxis = hitAxis; });
                },
                onPointerDown: (event) {
                  if (event.buttons == kPrimaryMouseButton) {
                    if (_selectedCube != null) _activeGizmoAxis = Fake3DScenePainter.getGizmoAxisAtPoint(event.localPosition, viewportSize, _selectedCube!, _model, _cameraRot, _cameraPan, _viewerDistance, 600, _gizmoMode);
                    if (_activeGizmoAxis == null) {
                      final hitId = Fake3DScenePainter.getCubeAtPoint(event.localPosition, viewportSize, _model, _cameraRot, _cameraPan, _viewerDistance, 600);
                      if (hitId != null) setState(() => _selectedCube = _model.cubes.firstWhere((c) => c.id == hitId));
                    }
                  }
                },
                onPointerUp: (event) => _activeGizmoAxis = null,
                onPointerMove: (event) {
                  if (_activeGizmoAxis != null && _selectedCube != null) {
                    _handleGizmoDrag(event.delta, viewportSize);
                  } else {
                    setState(() {
                    if (event.buttons == kPrimaryMouseButton) {
                      _cameraRot = Vector3((_cameraRot.x - event.delta.dy * 0.01).clamp(-1.5, 1.5), _cameraRot.y - event.delta.dx * 0.01, _cameraRot.z);
                    } else if (event.buttons == kSecondaryMouseButton) {
                      _cameraPan = Vector3(_cameraPan.x + event.delta.dx,
                          _cameraPan.y + event.delta.dy, 0);
                    }
                  });
                  }
                },
                child: Container(color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3), child: CustomPaint(painter: Fake3DScenePainter(model: _model, sceneRotation: _cameraRot, cameraPan: _cameraPan, viewerDistance: _viewerDistance, fov: 600, selectedCubeId: _selectedCube?.id, hoveredCubeId: _hoveredCubeId, hoveredGizmoAxis: _hoveredGizmoAxis, enableLighting: _enableLighting, themeColor: theme.colorScheme.primary, gizmoMode: _gizmoMode), size: Size.infinite)),
              ),
              Positioned(right: 20, bottom: 20, child: Listener(onPointerMove: (event) { if (event.buttons == 1) setState(() { _cameraRot = Vector3((_cameraRot.x - event.delta.dy * 0.05).clamp(-1.5, 1.5), _cameraRot.y - event.delta.dx * 0.05, _cameraRot.z); }); }, child: Container(width: 100, height: 100, decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.1), shape: BoxShape.circle), child: CustomPaint(painter: _GizmoPainter(rotation: _cameraRot))))),
            ]);
          })),
          Container(width: 300, decoration: BoxDecoration(border: Border(left: BorderSide(color: theme.dividerColor)), color: theme.colorScheme.surface), child: _selectedCube == null ? Center(child: Text("Select a cube to edit".tl)) : _buildCubeEditor(theme)),
        ],
      ),
    );
  }

  Widget _buildGizmoToggle() {
    return ToggleButtons(
      isSelected: [ _gizmoMode == GizmoMode.move, _gizmoMode == GizmoMode.scale, _gizmoMode == GizmoMode.rotate ],
      onPressed: (idx) => setState(() => _gizmoMode = GizmoMode.values[idx]),
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      children: const [ Icon(Icons.open_with), Icon(Icons.aspect_ratio), Icon(Icons.rotate_left) ],
    );
  }

  void _handleGizmoDrag(Offset delta, Size size) {
    if (_selectedCube == null || _activeGizmoAxis == null) return;
    final sceneMatrix = Matrix4.identity()..rotateX(_cameraRot.x)..rotateY(_cameraRot.y)..translateByVector3(vmath.Vector3(_model.pos.x, _model.pos.y, _model.pos.z));
    final worldMatrix = sceneMatrix * _selectedCube!.computeWorldMatrix(_model.cubes);
    final rotation = _gizmoMode == GizmoMode.move ? vmath.Matrix3.identity() : worldMatrix.getRotation();
    final center = worldMatrix.getTranslation();
    
    vmath.Vector3 localDir = _activeGizmoAxis == 'x' ? vmath.Vector3(1,0,0) : (_activeGizmoAxis == 'y' ? vmath.Vector3(0,1,0) : vmath.Vector3(0,0,1));
    final worldDir = rotation * localDir;
    
    final pCenter = _projectStatic(center, _cameraPan, _viewerDistance, 600, Offset(size.width/2, size.height/2));
    final pEnd = _projectStatic(center + worldDir * 10, _cameraPan, _viewerDistance, 600, Offset(size.width/2, size.height/2));
    if (pCenter == null || pEnd == null) return;
    
    final screenDir = Offset(pEnd.dx - pCenter.dx, pEnd.dy - pCenter.dy);
    double lenSq = screenDir.dx * screenDir.dx + screenDir.dy * screenDir.dy;
    if (lenSq < 1e-6) return;
    double moveVal = (delta.dx * screenDir.dx + delta.dy * screenDir.dy) / math.sqrt(lenSq) * 0.2;

    Vector3 dPos = Vector3.zero(); Vector3 dSize = Vector3.zero(); Vector3 dRot = Vector3.zero();
    if (_activeGizmoAxis == 'x') {
      if (_gizmoMode == GizmoMode.move) {
        dPos = Vector3(moveVal, 0, 0);
      } else if (_gizmoMode == GizmoMode.scale) {
        dSize = Vector3(moveVal, 0, 0);
      } else {
        dRot = Vector3(moveVal * 0.1, 0, 0);
      }
    } else if (_activeGizmoAxis == 'y') {
      if (_gizmoMode == GizmoMode.move) {
        dPos = Vector3(0, -moveVal, 0);
      } else if (_gizmoMode == GizmoMode.scale) {
        dSize = Vector3(0, moveVal, 0);
      } else {
        dRot = Vector3(0, moveVal * 0.1, 0);
      }
    } else {
      if (_gizmoMode == GizmoMode.move) {
        dPos = Vector3(0, 0, moveVal);
      } else if (_gizmoMode == GizmoMode.scale) {
        dSize = Vector3(0, 0, moveVal);
      } else {
        dRot = Vector3(0, 0, moveVal * 0.1);
      }
    }
    _updateSelectedCube(
      pos: Vector3(_selectedCube!.pos.x + dPos.x, _selectedCube!.pos.y + dPos.y, _selectedCube!.pos.z + dPos.z),
      size: Vector3((_selectedCube!.size.x + dSize.x).clamp(0.1, 100), (_selectedCube!.size.y + dSize.y).clamp(0.1, 100), (_selectedCube!.size.z + dSize.z).clamp(0.1, 100)),
      rot: Vector3(_selectedCube!.rot.x + dRot.x, _selectedCube!.rot.y + dRot.y, _selectedCube!.rot.z + dRot.z)
    );
  }

  Offset? _projectStatic(vmath.Vector3 v, Vector3 cameraPan, double viewerDistance, double fov, Offset center) {
    double z = v.z + viewerDistance; if (z <= 1.0) return null; double factor = fov / z; return Offset(v.x * factor + cameraPan.x + center.dx, -v.y * factor + cameraPan.y + center.dy);
  }

  void _updateSelectedCube({Vector3? pos, Vector3? rot, Vector3? size, Map<String, FaceData>? faces}) {
    setState(() {
      final updated = Cube(id: _selectedCube!.id, parentId: _selectedCube!.parentId, pos: pos ?? _selectedCube!.pos, rot: rot ?? _selectedCube!.rot, size: size ?? _selectedCube!.size, faces: faces ?? _selectedCube!.faces);
      final index = _model.cubes.indexWhere((c) => c.id == updated.id);
      final List<Cube> newCubes = List.from(_model.cubes);
      newCubes[index] = updated;
      _model = Polygon(newCubes, _model.pos, _model.rot);
      _selectedCube = updated;
    });
  }

  Widget _buildCubeEditor(ThemeData theme) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text("Editing: ${_selectedCube!.id}", style: theme.textTheme.titleMedium),
      const Divider(),
      _buildVectorEditor("Position", _selectedCube!.pos, (v) => _updateSelectedCube(pos: v)),
      _buildVectorEditor("Rotation", _selectedCube!.rot, (v) => _updateSelectedCube(rot: v)),
      _buildVectorEditor("Size", _selectedCube!.size, (v) => _updateSelectedCube(size: v)),
      const SizedBox(height: 20),
      Text("Textures".tl, style: theme.textTheme.labelLarge),
      const SizedBox(height: 8),
      _buildTextureInput("Front", 'front'), _buildTextureInput("Top", 'top'),
      const SizedBox(height: 32),
      BloretButton(text: "Delete Cube".tl, onPressed: () { setState(() { final newCubes = _model.cubes.where((c) => c.id != _selectedCube!.id).toList(); _model = Polygon(newCubes, _model.pos, _model.rot); _selectedCube = null; }); }),
    ]);
  }

  Widget _buildTextureInput(String label, String side) {
    return Padding(padding: const EdgeInsets.only(bottom: 8.0), child: TextField(decoration: InputDecoration(labelText: label, isDense: true), onChanged: (val) { final newFaces = Map<String, FaceData>.from(_selectedCube!.faces); newFaces[side] = FaceData(textureKey: val); _updateSelectedCube(faces: newFaces); }));
  }

  Widget _buildVectorEditor(String label, Vector3 value, Function(Vector3) onChanged) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 12),
      Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
      Row(children: [
        Expanded(child: _buildSlider("X", value.x, -24, 24, (v) => onChanged(Vector3(v, value.y, value.z)))),
        Expanded(child: _buildSlider("Y", value.y, -24, 24, (v) => onChanged(Vector3(value.x, v, value.z)))),
        Expanded(child: _buildSlider("Z", value.z, -24, 24, (v) => onChanged(Vector3(value.x, value.y, v)))),
      ]),
    ]);
  }

  Widget _buildSlider(String label, double value, double min, double max, Function(double) onChanged) {
    return Column(children: [
      Text(label, style: const TextStyle(fontSize: 10)),
      Slider(value: value.clamp(min, max), min: min, max: max, onChanged: onChanged),
    ]);
  }
}

class _GizmoPainter extends CustomPainter {
  final Vector3 rotation;
  _GizmoPainter({required this.rotation});
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const radius = 35.0;
    final matrix = Matrix4.identity()..rotateX(rotation.x)..rotateY(rotation.y);
    final axes = [ (vmath.Vector3(1, 0, 0), Colors.red, "X"), (vmath.Vector3(-1, 0, 0), Colors.red, "X"), (vmath.Vector3(0, 1, 0), Colors.green, "Y"), (vmath.Vector3(0, -1, 0), Colors.green, "Y"), (vmath.Vector3(0, 0, 1), Colors.blue, "Z"), (vmath.Vector3(0, 0, -1), Colors.blue, "Z") ];
    final transformedAxes = axes.map((a) { final vec = a.$1.clone(); matrix.transform3(vec); return (vec, a.$2, a.$3); }).toList()..sort((a, b) => b.$1.z.compareTo(a.$1.z));
    for (var axis in transformedAxes) {
      final vec = axis.$1;
      final paint = Paint()..color = axis.$2..strokeWidth = 2.5..strokeCap = StrokeCap.round;
      final endOffset = center + Offset(vec.x * radius, -vec.y * radius);
      canvas.drawLine(center, endOffset, paint);
      final tp = TextPainter(text: TextSpan(text: axis.$3, style: TextStyle(color: axis.$2, fontWeight: FontWeight.bold, fontSize: 10)), textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, endOffset);
    }
  }
  @override
  bool shouldRepaint(covariant _GizmoPainter oldDelegate) => oldDelegate.rotation != rotation;
}
