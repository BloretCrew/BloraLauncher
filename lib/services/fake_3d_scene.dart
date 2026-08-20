import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as vmath hide Colors;

enum GizmoMode { move, scale, rotate }

class Vector3 {
  final double x, y, z;
  const Vector3(this.x, this.y, this.z);
  const Vector3.zero() : x = 0, y = 0, z = 0;
  const Vector3.all(double v) : x = v, y = v, z = v;

  Vector3 rotateX(double radians) {
    if (radians == 0) return this;
    var cos = math.cos(radians);
    var sin = math.sin(radians);
    return Vector3(x, y * cos - z * sin, y * sin + z * cos);
  }

  Vector3 rotateY(double radians) {
    if (radians == 0) return this;
    var cos = math.cos(radians);
    var sin = math.sin(radians);
    return Vector3(x * cos + z * sin, y, -x * sin + z * cos);
  }

  Vector3 rotateZ(double radians) {
    if (radians == 0) return this;
    var cos = math.cos(radians);
    var sin = math.sin(radians);
    return Vector3(x * cos - y * sin, x * sin + y * cos, z);
  }

  Map<String, dynamic> toJson() => {'x': x, 'y': y, 'z': z};
  factory Vector3.fromJson(Map<String, dynamic> json) =>
      Vector3((json['x'] ?? 0).toDouble(), (json['y'] ?? 0).toDouble(), (json['z'] ?? 0).toDouble());
  
  vmath.Vector3 toVector3() => vmath.Vector3(x, y, z);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Vector3 && runtimeType == other.runtimeType && x == other.x && y == other.y && z == other.z;

  @override
  int get hashCode => x.hashCode ^ y.hashCode ^ z.hashCode;
}

class UVRect {
  final double u1, v1, u2, v2;
  const UVRect(this.u1, this.v1, this.u2, this.v2);
  const UVRect.full() : u1 = 0, v1 = 0, u2 = 1, v2 = 1;

  Map<String, dynamic> toJson() => {'u1': u1, 'v1': v1, 'u2': u2, 'v2': v2};
  factory UVRect.fromJson(Map<String, dynamic> json) =>
      UVRect((json['u1'] ?? 0).toDouble(), (json['v1'] ?? 0).toDouble(),
             (json['u2'] ?? 1).toDouble(), (json['v2'] ?? 1).toDouble());
}

class FaceData {
  final String? textureKey;
  final UVRect uv;
  const FaceData({this.textureKey, this.uv = const UVRect.full()});

  Map<String, dynamic> toJson() => {'textureKey': textureKey, 'uv': uv.toJson()};
  factory FaceData.fromJson(Map<String, dynamic> json) =>
      FaceData(textureKey: json['textureKey'], uv: UVRect.fromJson(json['uv'] ?? {}));
}

class Cube {
  final String id;
  final String? parentId;
  final Map<String, FaceData> faces;
  final Vector3 pos, rot, scale, size;

  Cube({
    required this.id,
    this.parentId,
    required this.faces,
    this.pos = const Vector3.zero(),
    this.rot = const Vector3.zero(),
    this.scale = const Vector3.all(1),
    this.size = const Vector3.all(1),
  });

  vmath.Matrix4 computeWorldMatrix(List<Cube> allCubes) {
    final local = vmath.Matrix4.identity()
      ..setTranslationRaw(pos.x, pos.y, pos.z)
      ..rotateX(rot.x)
      ..rotateY(rot.y)
      ..rotateZ(rot.z)
      ..scaleByVector3(vmath.Vector3(scale.x, scale.y, scale.z));

    if (parentId == null) return local;
    final parent = allCubes.where((c) => c.id == parentId).firstOrNull;
    if (parent == null) return local;
    return parent.computeWorldMatrix(allCubes) * local;
  }

  double getDepth(vmath.Matrix4 sceneMatrix, List<Cube> allCubes) {
    final worldPos = computeWorldMatrix(allCubes).getTranslation();
    final viewPos = sceneMatrix.transform3(worldPos);
    return viewPos.z;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'parentId': parentId,
    'faces': faces.map((k, v) => MapEntry(k, v.toJson())),
    'pos': pos.toJson(),
    'rot': rot.toJson(),
    'scale': scale.toJson(),
    'size': size.toJson(),
  };

  factory Cube.fromJson(Map<String, dynamic> json) => Cube(
    id: json['id'],
    parentId: json['parentId'],
    faces: (json['faces'] as Map<String, dynamic>? ?? {}).map((k, v) => MapEntry(k, FaceData.fromJson(v))),
    pos: Vector3.fromJson(json['pos'] ?? {}),
    rot: Vector3.fromJson(json['rot'] ?? {}),
    scale: Vector3.fromJson(json['scale'] ?? {}),
    size: Vector3.fromJson(json['size'] ?? {}),
  );
}

class TextureRegistry {
  static final TextureRegistry instance = TextureRegistry._();
  TextureRegistry._();
  final Map<String, ui.Image> _textures = {};
  ui.Image? _fallbackTexture;

  Future<void> initialize() async {
    if (_fallbackTexture != null) return;
    _fallbackTexture = await _createMissingTexture();
  }

  Future<void> loadFromJar(String jarPath) async {
    final file = File(jarPath);
    if (!file.existsSync()) return;
    final archive = ZipDecoder().decodeBytes(await file.readAsBytes());
    for (final file in archive) {
      if (file.isFile && file.name.startsWith('assets/minecraft/textures/') && file.name.endsWith('.png')) {
        try {
          final Uint8List imageData = Uint8List.fromList(file.content as List<int>);
          final ui.Codec codec = await ui.instantiateImageCodec(imageData);
          final ui.FrameInfo frameInfo = await codec.getNextFrame();
          final ui.Image image = frameInfo.image;
          _textures[file.name.replaceFirst('assets/minecraft/textures/', '').replaceFirst('.png', '')] = image;
        } catch (_) {}
      }
    }
  }

  ui.Image? getTexture(String? key) {
    final tex = _textures[key];
    if (tex != null) return tex;
    if (_fallbackTexture == null) return null as dynamic;
    return _fallbackTexture!;
  }

  Future<ui.Image> _createMissingTexture() async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final paint = Paint();
    paint.color = Colors.black;
    canvas.drawRect(const Rect.fromLTWH(0, 0, 8, 8), paint);
    canvas.drawRect(const Rect.fromLTWH(8, 8, 8, 8), paint);
    paint.color = const Color(0xFFFF00FF);
    canvas.drawRect(const Rect.fromLTWH(8, 0, 8, 8), paint);
    canvas.drawRect(const Rect.fromLTWH(0, 8, 8, 8), paint);
    return await recorder.endRecording().toImage(16, 16);
  }
}

class Polygon {
  final List<Cube> cubes;
  final Vector3 pos, rot;
  const Polygon(this.cubes, this.pos, this.rot);

  Map<String, dynamic> toJson() => {
    'cubes': cubes.map((c) => c.toJson()).toList(),
    'pos': pos.toJson(),
    'rot': rot.toJson(),
  };

  factory Polygon.fromJson(Map<String, dynamic> json) => Polygon(
    (json['cubes'] as List).map((c) => Cube.fromJson(c)).toList(),
    Vector3.fromJson(json['pos'] ?? {}),
    Vector3.fromJson(json['rot'] ?? {}),
  );
}

class Fake3DScenePainter extends CustomPainter {
  final Polygon model;
  final Vector3 sceneRotation;
  final Vector3 cameraPan;
  final double fov, viewerDistance;
  final bool showGrid;
  final String? selectedCubeId;
  final String? hoveredCubeId;
  final String? hoveredGizmoAxis;
  final bool enableLighting;
  final Color themeColor;
  final GizmoMode gizmoMode;

  Fake3DScenePainter({
    required this.model,
    required this.sceneRotation,
    this.cameraPan = const Vector3.zero(),
    this.fov = 600,
    this.viewerDistance = 100,
    this.showGrid = true,
    this.selectedCubeId,
    this.hoveredCubeId,
    this.hoveredGizmoAxis,
    this.enableLighting = true,
    this.themeColor = Colors.blue,
    this.gizmoMode = GizmoMode.move,
  });

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    TextureRegistry.instance.initialize();
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);

    final sceneMatrix = vmath.Matrix4.identity()
      ..rotateX(sceneRotation.x)
      ..rotateY(sceneRotation.y)
      ..translateByVector3(vmath.Vector3(model.pos.x, model.pos.y, model.pos.z));

    if (showGrid) _drawWorldGrid(canvas, sceneMatrix);

    final sortedCubes = List<Cube>.from(model.cubes)
      ..sort((a, b) => b.getDepth(sceneMatrix, model.cubes).compareTo(a.getDepth(sceneMatrix, model.cubes)));

    for (var cube in sortedCubes) {
      _drawCube(canvas, sceneMatrix, cube);
    }
    
    if (selectedCubeId != null) {
      final sel = model.cubes.where((c) => c.id == selectedCubeId).firstOrNull;
      if (sel != null) _drawGizmo(canvas, sceneMatrix, sel);
    }

    canvas.restore();
  }

  void _drawWorldGrid(ui.Canvas canvas, vmath.Matrix4 sceneMatrix) {
    final largePaint = Paint()..color = Colors.grey.withValues(alpha: 0.3)..strokeWidth = 1.2;
    final smallPaint = Paint()..color = Colors.grey.withValues(alpha: 0.1)..strokeWidth = 0.8;
    for (double i = -24; i <= 24; i += 16) {
      _drawLine3D(canvas, sceneMatrix, Vector3(i, 0, -24), Vector3(i, 0, 24), largePaint);
      _drawLine3D(canvas, sceneMatrix, Vector3(-24, 0, i), Vector3(24, 0, i), largePaint);
    }
    for (double i = -8; i <= 8; i += 1) {
      if (i == -8 || i == 8) continue;
      _drawLine3D(canvas, sceneMatrix, Vector3(i, 0, -8), Vector3(i, 0, 8), smallPaint);
      _drawLine3D(canvas, sceneMatrix, Vector3(-8, 0, i), Vector3(8, 0, i), smallPaint);
    }
  }

  void _drawLine3D(ui.Canvas canvas, vmath.Matrix4 sceneMatrix, Vector3 start, Vector3 end, Paint paint) {
    final pStart = _project(sceneMatrix.transform3(start.toVector3()));
    final pEnd = _project(sceneMatrix.transform3(end.toVector3()));
    if (pStart == null || pEnd == null) return;
    canvas.drawLine(pStart, pEnd, paint);
  }

  Offset? _project(vmath.Vector3 v) {
    double z = v.z + viewerDistance;
    if (z <= 1.0) return null; 
    double factor = fov / z;
    return Offset(v.x * factor + cameraPan.x, -v.y * factor + cameraPan.y);
  }

  void _drawCube(ui.Canvas canvas, vmath.Matrix4 sceneMatrix, Cube cube) {
    final worldMatrix = sceneMatrix * cube.computeWorldMatrix(model.cubes);
    final s = cube.size;
    final isSelected = cube.id == selectedCubeId;
    final isHovered = cube.id == hoveredCubeId;
    final List<vmath.Vector3> localPts = [
      vmath.Vector3(-s.x/2,  s.y/2, -s.z/2), vmath.Vector3( s.x/2,  s.y/2, -s.z/2),
      vmath.Vector3( s.x/2, -s.y/2, -s.z/2), vmath.Vector3(-s.x/2, -s.y/2, -s.z/2),
      vmath.Vector3(-s.x/2,  s.y/2,  s.z/2), vmath.Vector3( s.x/2,  s.y/2,  s.z/2),
      vmath.Vector3( s.x/2, -s.y/2,  s.z/2), vmath.Vector3(-s.x/2, -s.y/2,  s.z/2),
    ];
    final projected = localPts.map((p) => _project(worldMatrix.transform3(p))).toList();
    if (projected.any((p) => p == null)) return;
    final points = projected.cast<Offset>();
    void drawFace(List<int> indices, vmath.Vector3 normal, String faceKey) {
      final centerLocal = vmath.Vector3(normal.x * s.x/2, normal.y * s.y/2, normal.z * s.z/2);
      final centerProj = _project(worldMatrix.transform3(centerLocal));
      if (centerProj == null) return;
      _drawFace(canvas, points, indices, centerProj, cube.faces[faceKey], worldMatrix, normal, isSelected, isHovered);
    }
    drawFace([0, 1, 2, 3], vmath.Vector3(0, 0, -1), 'front');
    drawFace([1, 5, 6, 2], vmath.Vector3(1, 0, 0), 'right');
    drawFace([5, 4, 7, 6], vmath.Vector3(0, 0, 1), 'back');
    drawFace([4, 0, 3, 7], vmath.Vector3(-1, 0, 0), 'left');
    drawFace([4, 5, 1, 0], vmath.Vector3(0, 1, 0), 'top');
    drawFace([3, 2, 6, 7], vmath.Vector3(0, -1, 0), 'bottom');
    if (isSelected) {
      final paint = Paint()..color = themeColor..strokeWidth = 2..style = PaintingStyle.stroke;
      for (int i = 0; i < 4; i++) {
        canvas.drawLine(points[i], points[(i + 1) % 4], paint);
        canvas.drawLine(points[i + 4], points[(i + 1) % 4 + 4], paint);
        canvas.drawLine(points[i], points[i + 4], paint);
      }
    }
  }

  void _drawFace(ui.Canvas canvas, List<Offset> points, List<int> indices, Offset center, FaceData? face, vmath.Matrix4 worldMatrix, vmath.Vector3 normal, bool isSelected, bool isHovered) {
    double area = 0;
    for (int i = 0; i < indices.length; i++) {
      final p1 = points[indices[i]], p2 = points[indices[(i + 1) % indices.length]];
      area += (p1.dx * p2.dy) - (p2.dx * p1.dy);
    }
    if (area <= 0) return;
    double shading = 1.0;
    if (enableLighting) {
      final worldNormal = (worldMatrix.getRotation() * normal).normalized();
      final lightDir = vmath.Vector3(0.5, 1.0, -0.5).normalized();
      shading = (worldNormal.dot(lightDir) * 0.4 + 0.6).clamp(0.2, 1.0);
    }
    final img = TextureRegistry.instance.getTexture(face?.textureKey);
    final paint = Paint()..color = Colors.white.withValues(alpha: shading);
    if (img == null) {
      final fallbackPaint = Paint()..color = Colors.grey.withValues(alpha: 0.5 * shading);
      final path = Path()..moveTo(points[indices[0]].dx, points[indices[0]].dy);
      for (int i = 1; i < indices.length; i++) path.lineTo(points[indices[i]].dx, points[indices[i]].dy);
      path.close();
      canvas.drawPath(path, fallbackPaint);
    } else {
      final uv = face?.uv ?? const UVRect.full();
      final uvC = Offset(img.width * (uv.u1 + uv.u2) / 2, img.height * (uv.v1 + uv.v2) / 2);
      final verts = ui.Vertices(ui.VertexMode.triangles, [
        points[indices[0]], points[indices[1]], center,
        points[indices[1]], points[indices[2]], center,
        points[indices[2]], points[indices[3]], center,
        points[indices[3]], points[indices[0]], center,
      ], textureCoordinates: [
        Offset(img.width * uv.u1, img.height * uv.v1), Offset(img.width * uv.u2, img.height * uv.v1), uvC,
        Offset(img.width * uv.u2, img.height * uv.v1), Offset(img.width * uv.u2, img.height * uv.v2), uvC,
        Offset(img.width * uv.u2, img.height * uv.v2), Offset(img.width * uv.u1, img.height * uv.v2), uvC,
        Offset(img.width * uv.u1, img.height * uv.v2), Offset(img.width * uv.u1, img.height * uv.v1), uvC,
      ]);
      canvas.drawVertices(verts, ui.BlendMode.modulate, paint..shader = ImageShader(img, ui.TileMode.clamp, ui.TileMode.clamp, vmath.Matrix4.identity().storage));
    }
    if (isSelected || isHovered) {
      final overlayPaint = Paint()
        ..color = themeColor.withValues(alpha: isSelected ? (isHovered ? 0.25 : 0.15) : 0.08)
        ..style = PaintingStyle.fill;
      final path = Path()..moveTo(points[indices[0]].dx, points[indices[0]].dy);
      for (int i = 1; i < indices.length; i++) path.lineTo(points[indices[i]].dx, points[indices[i]].dy);
      path.close();
      canvas.drawPath(path, overlayPaint);
    }
  }

  void _drawGizmo(ui.Canvas canvas, vmath.Matrix4 sceneMatrix, Cube cube) {
    final worldMatrix = sceneMatrix * cube.computeWorldMatrix(model.cubes);
    final center = worldMatrix.getTranslation();
    final rotation = gizmoMode == GizmoMode.move ? vmath.Matrix3.identity() : worldMatrix.getRotation();
    final pCenter = _project(center);
    if (pCenter == null) return;
    const double len = 15.0;
    void drawAxis(String axisId, vmath.Vector3 localDir, Color color) {
      final isHovered = hoveredGizmoAxis == axisId;
      final c = isHovered ? Colors.white : color;
      final worldDir = rotation * localDir;
      final pEnd = _project(center + worldDir * len);
      if (pEnd == null) return;
      final paint = Paint()..color = c..strokeWidth = 3..strokeCap = StrokeCap.round;
      canvas.drawLine(pCenter, pEnd, paint);
      if (gizmoMode == GizmoMode.move) canvas.drawCircle(pEnd, 4, paint..style = PaintingStyle.fill);
      else if (gizmoMode == GizmoMode.scale) {
        canvas.drawRect(Rect.fromCenter(center: pEnd, width: 8, height: 8), paint..style = PaintingStyle.fill);
        final pOtherEnd = _project(center - worldDir * len);
        if (pOtherEnd != null) { canvas.drawLine(pCenter, pOtherEnd, paint); canvas.drawRect(Rect.fromCenter(center: pOtherEnd, width: 8, height: 8), paint); }
      }
    }
    if (gizmoMode == GizmoMode.rotate) {
      void drawCircle(String axisId, vmath.Vector3 axis, Color color) {
        final isHovered = hoveredGizmoAxis == axisId;
        final paint = Paint()..color = (isHovered ? Colors.white : color).withValues(alpha: 0.5)..strokeWidth = 2..style = PaintingStyle.stroke;
        final path = Path();
        for (int i = 0; i <= 32; i++) {
          double angle = i * 2 * math.pi / 32;
          vmath.Vector3 p;
          if (axis.x > 0) p = vmath.Vector3(0, math.cos(angle), math.sin(angle));
          else if (axis.y > 0) p = vmath.Vector3(math.cos(angle), 0, math.sin(angle));
          else p = vmath.Vector3(math.cos(angle), math.sin(angle), 0);
          final proj = _project(center + (rotation * p) * len);
          if (proj == null) continue;
          if (i == 0) path.moveTo(proj.dx, proj.dy); else path.lineTo(proj.dx, proj.dy);
        }
        canvas.drawPath(path, paint);
      }
      drawCircle('x', vmath.Vector3(1,0,0), Colors.red); drawCircle('y', vmath.Vector3(0,1,0), Colors.green); drawCircle('z', vmath.Vector3(0,0,1), Colors.blue);
    } else {
      drawAxis('x', vmath.Vector3(1, 0, 0), Colors.red); drawAxis('y', vmath.Vector3(0, 1, 0), Colors.green); drawAxis('z', vmath.Vector3(0, 0, 1), Colors.blue);
    }
  }

  static String? getCubeAtPoint(Offset localPos, Size size, Polygon model, Vector3 sceneRotation, Vector3 cameraPan, double viewerDistance, double fov) {
    final center = Offset(size.width / 2, size.height / 2);
    final sceneMatrix = vmath.Matrix4.identity()..rotateX(sceneRotation.x)..rotateY(sceneRotation.y)..translateByVector3(vmath.Vector3(model.pos.x, model.pos.y, model.pos.z));
    final sortedCubes = List<Cube>.from(model.cubes)..sort((a, b) => a.getDepth(sceneMatrix, model.cubes).compareTo(b.getDepth(sceneMatrix, model.cubes)));
    for (var cube in sortedCubes) {
      final worldMatrix = sceneMatrix * cube.computeWorldMatrix(model.cubes);
      final s = cube.size;
      final List<vmath.Vector3> localPts = [vmath.Vector3(-s.x/2, s.y/2, -s.z/2), vmath.Vector3(s.x/2, s.y/2, -s.z/2), vmath.Vector3(s.x/2, -s.y/2, -s.z/2), vmath.Vector3(-s.x/2, -s.y/2, -s.z/2), vmath.Vector3(-s.x/2, s.y/2, s.z/2), vmath.Vector3(s.x/2, s.y/2, s.z/2), vmath.Vector3(s.x/2, -s.y/2, s.z/2), vmath.Vector3(-s.x/2, -s.y/2, s.z/2)];
      final projected = localPts.map((p) { final v = worldMatrix.transform3(p); double z = v.z + viewerDistance; if (z <= 1.0) return null; double factor = fov / z; return Offset(v.x * factor + cameraPan.x + center.dx, -v.y * factor + cameraPan.y + center.dy); }).toList();
      if (projected.any((p) => p == null)) continue;
      final points = projected.cast<Offset>();
      for (var indices in [[0,1,2,3], [1,5,6,2], [5,4,7,6], [4,0,3,7], [4,5,1,0], [3,2,6,7]]) {
        double area = 0;
        for (int i = 0; i < indices.length; i++) { final p1 = points[indices[i]], p2 = points[indices[(i + 1) % indices.length]]; area += (p1.dx * p2.dy) - (p2.dx * p1.dy); }
        if (area > 0 && _isPointInPolygon(localPos, indices.map((i) => points[i]).toList())) return cube.id;
      }
    }
    return null;
  }

  static String? getGizmoAxisAtPoint(Offset localPos, Size size, Cube cube, Polygon model, Vector3 sceneRotation, Vector3 cameraPan, double viewerDistance, double fov, GizmoMode mode) {
    final centerOffset = Offset(size.width / 2, size.height / 2);
    final sceneMatrix = vmath.Matrix4.identity()..rotateX(sceneRotation.x)..rotateY(sceneRotation.y)..translateByVector3(vmath.Vector3(model.pos.x, model.pos.y, model.pos.z));
    final worldMatrix = sceneMatrix * cube.computeWorldMatrix(model.cubes);
    final center = worldMatrix.getTranslation();
    final rotation = mode == GizmoMode.move ? vmath.Matrix3.identity() : worldMatrix.getRotation();
    const double len = 15.0;
    for (var axis in [('x', vmath.Vector3(1,0,0)), ('y', vmath.Vector3(0,1,0)), ('z', vmath.Vector3(0,0,1))]) {
      final pEnd = _projectStatic(center + (rotation * axis.$2) * len, cameraPan, viewerDistance, fov, centerOffset);
      if (pEnd != null && (localPos - pEnd).distance < 15.0) return axis.$1;
      if (mode == GizmoMode.scale) {
        final pOtherEnd = _projectStatic(center - (rotation * axis.$2) * len, cameraPan, viewerDistance, fov, centerOffset);
        if (pOtherEnd != null && (localPos - pOtherEnd).distance < 15.0) return axis.$1;
      }
    }
    return null;
  }

  static Offset? _projectStatic(vmath.Vector3 v, Vector3 cameraPan, double viewerDistance, double fov, Offset center) {
    double z = v.z + viewerDistance; if (z <= 1.0) return null; double factor = fov / z; return Offset(v.x * factor + cameraPan.x + center.dx, -v.y * factor + cameraPan.y + center.dy);
  }

  static bool _isPointInPolygon(Offset p, List<Offset> poly) {
    bool isInside = false;
    for (int i = 0, j = poly.length - 1; i < poly.length; j = i++) { if (((poly[i].dy > p.dy) != (poly[j].dy > p.dy)) && (p.dx < (poly[j].dx - poly[i].dx) * (p.dy - poly[i].dy) / (poly[j].dy - poly[i].dy) + poly[i].dx)) isInside = !isInside; }
    return isInside;
  }

  @override
  bool shouldRepaint(covariant Fake3DScenePainter oldDelegate) => true;
}
