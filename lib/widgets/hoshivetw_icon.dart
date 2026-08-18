import 'package:flutter/material.dart';

class HoshivetwIcon extends StatefulWidget {
  final double size;
  final Color color;
  final VoidCallback? onAnimationComplete;
  final bool noAnim;
  final bool noShade;

  const HoshivetwIcon({super.key, this.size = 24, this.color = Colors.white, this.onAnimationComplete, this.noAnim = false, this.noShade = false,});

  @override
  State<HoshivetwIcon> createState() => _HoshivetwIconState();
}

class _HoshivetwIconState extends State<HoshivetwIcon> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  late List<Animation<double>> _opacityAnimations;
  late Animation<double> _wingScale;
  late Animation<double> _holeScale;
  late Animation<double> _spineMove;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _opacityAnimations = List.generate(6, (index) {
      double start = index * 0.12;
      double end = start + 0.3;
      return CurvedAnimation(
        parent: _controller,
        curve: Interval(start.clamp(0, 1), end.clamp(0, 1), curve: Curves.easeIn),
      );
    });

    _wingScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.15).chain(CurveTween(curve: Curves.easeOut)),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.15, end: 1.0).chain(CurveTween(curve: Curves.easeIn)),
        weight: 50,
      ),
    ]).animate(CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.8)));

    _holeScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.1).chain(CurveTween(curve: Curves.easeOut)),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.1, end: 1.0).chain(CurveTween(curve: Curves.easeIn)),
        weight: 50,
      ),
    ]).animate(CurvedAnimation(parent: _controller, curve: const Interval(0.3, 0.5)));

    _spineMove = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 2.0).chain(CurveTween(curve: Curves.easeOut)),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 2.0, end: 0.0).chain(CurveTween(curve: Curves.easeIn)),
        weight: 50,
      ),
    ]).animate(CurvedAnimation(parent: _controller, curve: const Interval(0.5, 0.9)));

    _controller.addListener(() {
      if (_controller.value >= 0.6) {
        widget.onAnimationComplete?.call();
      }
    });

    if (widget.noAnim) {
      _controller.forward(from: 0.99);
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _buildPart({
    required Widget child,
    required Animation<double> opacity,
    Animation<double>? scale,
    double offsetX = 0,
    bool rotate = false,
  }) {
    Widget current = FadeTransition(opacity: opacity, child: child);

    if (scale != null) {
      current = Transform.scale(scale: scale.value, child: current);
    }

    if (offsetX != 0) {
      current = Transform.translate(offset: Offset(offsetX, 0), child: current);
    }

    if (rotate) {
      current = RotatedBox(quarterTurns: 2, child: current);
    }

    return current;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            if (!widget.noShade) Positioned(
              top: 5,
              left: 5,
              child: Opacity(
                opacity: 0.7,
                child: _buildMainBody(isShadow: true),
              ),
            ),
            _buildMainBody(isShadow: false),
          ],
        );
      },
    );
  }

  Widget _buildMainBody({bool isShadow = false}) {
    final color = isShadow ? widget.color.withAlpha(55) : widget.color;
    final size = widget.size;

    return Stack(
      alignment: Alignment.center,
      children: [
        // 1. Wing
        _buildPart(opacity: _opacityAnimations[0], scale: _wingScale, child: CustomPaint(size: Size(size, size), painter: Wing(color: color))),
        _buildPart(opacity: _opacityAnimations[0], scale: _wingScale, rotate: true, child: CustomPaint(size: Size(size, size), painter: Wing(color: color))),

        // 2. OuterHoleWing
        _buildPart(opacity: _opacityAnimations[1], scale: _wingScale, child: CustomPaint(size: Size(size, size), painter: OuterHoleWing(color: color))),
        _buildPart(opacity: _opacityAnimations[1], scale: _wingScale, rotate: true, child: CustomPaint(size: Size(size, size), painter: OuterHoleWing(color: color))),

        // 3. InnerHole
        _buildPart(opacity: _opacityAnimations[2], scale: _holeScale, child: CustomPaint(size: Size(size, size), painter: InnerHole(color: color))),
        _buildPart(opacity: _opacityAnimations[2], scale: _holeScale, rotate: true, child: CustomPaint(size: Size(size, size), painter: InnerHole(color: color))),

        // 4. InnerWing
        _buildPart(opacity: _opacityAnimations[3], scale: _wingScale, child: CustomPaint(size: Size(size, size), painter: InnerWing(color: color))),
        _buildPart(opacity: _opacityAnimations[3], scale: _wingScale, rotate: true, child: CustomPaint(size: Size(size, size), painter: InnerWing(color: color))),

        // 5. SpineIconUpperDowner (左右移动)
        _buildPart(opacity: _opacityAnimations[4], offsetX: -_spineMove.value, child: CustomPaint(size: Size(size, size), painter: SpineIconUpperDowner(color: color))),
        _buildPart(opacity: _opacityAnimations[4], offsetX: _spineMove.value, rotate: true, child: CustomPaint(size: Size(size, size), painter: SpineIconUpperDowner(color: color))),

        // 6. SpineIconCenter
        _buildPart(opacity: _opacityAnimations[5], child: CustomPaint(size: Size(size, size), painter: SpineIconCenter(color: color))),
      ],
    );
  }
}


class Wing extends CustomPainter {
  final Color color;

  const Wing({this.color = Colors.white});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 17 * 2, 0)
      ..lineTo(size.width / 17 * 2, size.height / 17)
      ..lineTo(size.width / 17 * 3, size.height / 17)
      ..lineTo(size.width / 17 * 3, size.height / 17 * 3)
      ..lineTo(size.width / 17, size.height / 17 * 3)
      ..lineTo(size.width / 17, size.height / 17 * 2)
      ..lineTo(0, size.height / 17 * 2)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}

class OuterHoleWing extends CustomPainter {
  final Color color;

  const OuterHoleWing({this.color = Colors.white});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;

    canvas.drawRect(Rect.fromLTWH(size.width / 17 * 7, size.height / 17, size.width / 17 * 8, size.height / 17), paint);
    canvas.drawRect(Rect.fromLTWH(size.width / 17 * 15, size.height / 17 * 2, size.width / 17, size.height / 17 * 8), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}

class InnerHole extends CustomPainter {
  final Color color;

  const InnerHole({this.color = Colors.white});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(size.width / 17 * 4, size.height / 17 * 3)
      ..lineTo(size.width / 17 * 14, size.height / 17 * 3)
      ..lineTo(size.width / 17 * 14, size.height / 17 * 13)
      ..lineTo(size.width / 17 * 13, size.height / 17 * 13)
      ..lineTo(size.width / 17 * 13, size.height / 17 * 4)
      ..lineTo(size.width / 17 * 4, size.height / 17 * 4)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}

class InnerWing extends CustomPainter {
  final Color color;

  const InnerWing({this.color = Colors.white});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(size.width / 17 * 5, size.height / 17 * 5)
      ..lineTo(size.width / 17 * 7, size.height / 17 * 5)
      ..lineTo(size.width / 17 * 7, size.height / 17 * 6)
      ..lineTo(size.width / 17 * 6, size.height / 17 * 6)
      ..lineTo(size.width / 17 * 6, size.height / 17 * 7)
      ..lineTo(size.width / 17 * 5, size.height / 17 * 7)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}

class SpineIconUpperDowner extends CustomPainter {
  final Color color;

  const SpineIconUpperDowner({this.color = Colors.white});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(size.width / 17 * 8, size.width / 17 * 5)
      ..lineTo(size.width / 17 * 12, size.width / 17 * 5)
      ..lineTo(size.width / 17 * 12, size.width / 17 * 7)
      ..lineTo(size.width / 17 * 8, size.width / 17 * 7)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}

class SpineIconCenter extends CustomPainter {
  final Color color;

  const SpineIconCenter({this.color = Colors.white});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(size.width / 17 * 6, size.height / 17 * 8)
      ..lineTo(size.width / 17 * 11, size.height / 17 * 8)
      ..lineTo(size.width / 17 * 11, size.height / 17 * 9)
      ..lineTo(size.width / 17 * 6, size.height / 17 * 9)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}