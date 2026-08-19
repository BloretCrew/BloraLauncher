import 'dart:ui';

class Vector3 {
  final double x;
  final double y;
  final double z;

  const Vector3(this.x, this.y, this.z);

  const Vector3.zero() : x = 0, y = 0, z = 0;

  const Vector3.all(double value) : x = value, y = value, z = value;
}

class Cube {
  final Map<String, Image> images;
  final Vector3 pos;
  final Vector3 rot;
  final Vector3 anchor;
  final Vector3 scale;

  const Cube(this.images, this.pos, this.rot, {this.anchor = const Vector3.zero(), this.scale = const Vector3.all(1)});
}

class Polygon {
  final List<Cube> cubes;
  final Vector3 pos;
  final Vector3 rot;
  final Vector3 anchor;
  final Vector3 scale;

  const Polygon(this.cubes, this.pos, this.rot, {this.anchor = const Vector3.zero(), this.scale = const Vector3.all(1)});
}