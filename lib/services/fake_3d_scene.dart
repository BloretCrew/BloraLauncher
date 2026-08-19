import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as vmath hide Colors;

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

  Future<void> initialize() async { _fallbackTexture ??= await _createMissingTexture(); }

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

  ui.Image getTexture(String? key) => _textures[key] ?? _fallbackTexture!;

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
  final double fov, viewerDistance;
  final bool showGrid;

  Fake3DScenePainter({
    required this.model,
    required this.sceneRotation,
    this.fov = 500,
    this.viewerDistance = 50,
    this.showGrid = true,
  });

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    TextureRegistry.instance.initialize();
    
    final sceneMatrix = vmath.Matrix4.identity()
      ..translateByVector3(vmath.Vector3(size.width / 2, size.height / 2, 0))
      ..rotateX(sceneRotation.x)
      ..rotateY(sceneRotation.y)
      ..rotateZ(sceneRotation.z)
      ..translateByVector3(vmath.Vector3(model.pos.x, model.pos.y, model.pos.z));

    if (showGrid) _drawWorldGrid(canvas, size, sceneMatrix);

    final sortedCubes = List<Cube>.from(model.cubes)
      ..sort((a, b) => b.getDepth(sceneMatrix, model.cubes).compareTo(a.getDepth(sceneMatrix, model.cubes)));

    for (var cube in sortedCubes) {
      _drawCube(canvas, size, sceneMatrix, cube);
    }
  }

  void _drawWorldGrid(ui.Canvas canvas, ui.Size size, vmath.Matrix4 sceneMatrix) {
    final paint = Paint()..color = Colors.grey.withValues(alpha: 0.2)..strokeWidth = 1;
    const int lines = 10;
    const double step = 5.0;
    for (int i = -lines; i <= lines; i++) {
      _drawLine3D(canvas, sceneMatrix, Vector3(i * step, 0, -lines * step), Vector3(i * step, 0, lines * step), paint);
      _drawLine3D(canvas, sceneMatrix, Vector3(-lines * step, 0, i * step), Vector3(lines * step, 0, i * step), paint);
    }
  }

  void _drawLine3D(ui.Canvas canvas, vmath.Matrix4 sceneMatrix, Vector3 start, Vector3 end, Paint paint) {
    final pStart = _project(sceneMatrix.transform3(start.toVector3()));
    final pEnd = _project(sceneMatrix.transform3(end.toVector3()));
    canvas.drawLine(pStart, pEnd, paint);
  }

  Offset _project(vmath.Vector3 v) {
    double factor = fov / (viewerDistance + v.z);
    return Offset(v.x * factor, -v.y * factor);
  }

  void _drawCube(ui.Canvas canvas, ui.Size size, vmath.Matrix4 sceneMatrix, Cube cube) {
    final worldMatrix = sceneMatrix * cube.computeWorldMatrix(model.cubes);
    final s = cube.size;
    
    final List<vmath.Vector3> localPts = [
      vmath.Vector3(-s.x/2,  s.y/2, -s.z/2), vmath.Vector3( s.x/2,  s.y/2, -s.z/2),
      vmath.Vector3( s.x/2, -s.y/2, -s.z/2), vmath.Vector3(-s.x/2, -s.y/2, -s.z/2),
      vmath.Vector3(-s.x/2,  s.y/2,  s.z/2), vmath.Vector3( s.x/2,  s.y/2,  s.z/2),
      vmath.Vector3( s.x/2, -s.y/2,  s.z/2), vmath.Vector3(-s.x/2, -s.y/2,  s.z/2),
    ];

    final projected = localPts.map((p) => _project(worldMatrix.transform3(p))).toList();

    void drawFace(List<int> indices, vmath.Vector3 faceCenterLocal, String faceKey) {
      final centerProjected = _project(worldMatrix.transform3(faceCenterLocal));
      _drawFaceIfVisible(canvas, projected, indices, centerProjected, cube.faces[faceKey]);
    }

    drawFace([0, 1, 2, 3], vmath.Vector3(0, 0, -s.z/2), 'front');
    drawFace([1, 5, 6, 2], vmath.Vector3(s.x/2, 0, 0), 'right');
    drawFace([5, 4, 7, 6], vmath.Vector3(0, 0, s.z/2), 'back');
    drawFace([4, 0, 3, 7], vmath.Vector3(-s.x/2, 0, 0), 'left');
    drawFace([4, 5, 1, 0], vmath.Vector3(0, s.y/2, 0), 'top');
    drawFace([3, 2, 6, 7], vmath.Vector3(0, -s.y/2, 0), 'bottom');
  }

  void _drawFaceIfVisible(ui.Canvas canvas, List<Offset> points, List<int> indices, Offset center, FaceData? face) {
    double area = 0;
    for (int i = 0; i < indices.length; i++) {
      final p1 = points[indices[i]], p2 = points[indices[(i + 1) % indices.length]];
      area += (p2.dx - p1.dx) * (p2.dy + p1.dy);
    }
    if (area >= 0) return;

    final img = TextureRegistry.instance.getTexture(face?.textureKey);
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

    canvas.drawVertices(verts, ui.BlendMode.srcOver, Paint()..shader = ImageShader(img, ui.TileMode.clamp, ui.TileMode.clamp, vmath.Matrix4.identity().storage));
  }

  @override
  bool shouldRepaint(covariant Fake3DScenePainter oldDelegate) => true;
}