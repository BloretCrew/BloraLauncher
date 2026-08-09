import 'dart:math' as math;
import 'package:bloret_launcher/core/grammer_candy.dart';
import 'package:flutter/material.dart';

// Google's Sperm Slider
class GoogleSquigglySlider extends StatefulWidget {
  final double value;
  final double max;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double>? onChangeEnd;
  final Color? activeColor;
  final Color? inactiveColor;
  final bool isPlaying;
  final bool hasThumb;

  const GoogleSquigglySlider({
    super.key,
    required this.value,
    this.max = 100.0,
    this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
    this.activeColor,
    this.inactiveColor,
    this.isPlaying = true,
    this.hasThumb = true,
  });

  @override
  State<GoogleSquigglySlider> createState() => _GoogleSquigglySliderState();
}

class _GoogleSquigglySliderState extends State<GoogleSquigglySlider> with TickerProviderStateMixin {
  late AnimationController _waveController;
  late AnimationController _transitionController;
  late AnimationController _thumbTransitionController;
  late AnimationController _smoothValueController;
  late Animation<double> _thumbAnimation;
  late Animation<double> _smoothValueAnimation;
  bool _isDragging = false;
  double _dragValue = 0.0;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _transitionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _thumbTransitionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _smoothValueController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _thumbAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _thumbTransitionController, curve: Curves.linearToEaseOut));
    _smoothValueAnimation = Tween<double>(begin: widget.value, end: widget.value).animate(CurvedAnimation(parent: _smoothValueController, curve: Curves.easeOutCubic));

    if (widget.isPlaying) {
      _waveController.repeat();
      _transitionController.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(GoogleSquigglySlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _waveController.repeat();
        _transitionController.forward();
      } else {
        _transitionController.reverse().then((_) {
          if (!widget.isPlaying) {
            _waveController.stop();
          }
        });
      }
    }
    if (widget.value != oldWidget.value) {
      _smoothValueAnimation = Tween<double>(
        begin: _smoothValueAnimation.value,
        end: widget.value,
      ).animate(CurvedAnimation(parent: _smoothValueController, curve: Curves.easeOutCubic));
      _smoothValueController.forward(from: 0.0);

      if (widget.value < 0.025 * widget.max || widget.value > 0.975 * widget.max || !widget.isPlaying) {
        _transitionController.reverse().then((_) {
          if (!widget.isPlaying) {
            _waveController.stop();
          }
        });
      } else if (!_waveController.isAnimating || !_transitionController.isAnimating) {
        _waveController.repeat();
        _transitionController.forward();
      }
    }
    if (widget.hasThumb != oldWidget.hasThumb) {
      if (widget.hasThumb) {
        _thumbTransitionController.forward();
      } else {
        _thumbTransitionController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _waveController.dispose();
    _transitionController.dispose();
    _thumbTransitionController.dispose();
    _smoothValueController.dispose();
    super.dispose();
  }

  void _handleDragUpdate(double localX, double totalWidth) {
    double percent = (localX / totalWidth).clamp(0.0, 1.0);
    double newValue = percent * widget.max;
    setState(() {
      _dragValue = newValue;
    });
    widget.onChanged?.call(newValue);
  }

  @override
  Widget build(BuildContext context) {
    final activeColor = widget.activeColor ?? Theme.of(context).colorScheme.primary;
    final inactiveColor = widget.inactiveColor ?? Theme.of(context).colorScheme.secondary;
    return GestureDetector(
      onHorizontalDragStart: (details) {
        setState(() {
          _isDragging = true;
          _dragValue = widget.value;
        });
        widget.onChangeStart?.call(_dragValue);
      },
      onHorizontalDragUpdate: (details) {
        final RenderBox renderBox = context.findRenderObject() as RenderBox;
        _handleDragUpdate(details.localPosition.dx, renderBox.size.width);
      },
      onHorizontalDragEnd: (details) {
        setState(() {
          _isDragging = false;
        });
        widget.onChangeEnd?.call(_dragValue);
      },
      onTapDown: (details) {
        final RenderBox renderBox = context.findRenderObject() as RenderBox;
        _handleDragUpdate(details.localPosition.dx, renderBox.size.width);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: AnimatedBuilder(
          animation: Listenable.merge([_waveController, _transitionController, _smoothValueAnimation, _thumbAnimation]),
          builder: (context, child) {
            double currentValue = _isDragging ? _dragValue : _smoothValueAnimation.value;
            double progressPercent = (currentValue / widget.max).clamp(0.0, 1.0);

            return CustomPaint(
              size: const Size(double.infinity, 48),
              painter: _SquigglySliderPainter(
                progressPercent: progressPercent,
                wavePhase: _waveController.value * 2 * math.pi,
                activeColor: activeColor,
                inactiveColor: inactiveColor,
                squggleProgress: _transitionController.value,
                thumbOpacity: _thumbAnimation.value.clamp(0, 1),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SquigglySliderPainter extends CustomPainter {
  final double progressPercent;
  final double wavePhase;
  final Color activeColor;
  final Color inactiveColor;
  final double squggleProgress;
  final double thumbOpacity;

  _SquigglySliderPainter({
    required this.progressPercent,
    required this.wavePhase,
    required this.activeColor,
    required this.inactiveColor,
    required this.squggleProgress,
    required this.thumbOpacity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double cy = size.height / 2;
    final double trackWidth = size.width;
    final double thumbX = trackWidth * progressPercent;

    final Paint activePaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    final Paint inactivePaint = Paint()
      ..color = inactiveColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    final Paint thumbPaint = Paint()
      ..color = activeColor.withOpacityEx(thumbOpacity)
      ..style = PaintingStyle.fill;

    const double wavelength = 32.0;
    const double amplitude = 3.0;

    double thumbY = cy;
    if (squggleProgress > 0.0) {
      thumbY = cy + math.sin((thumbX / wavelength) * 2 * math.pi + wavePhase) * amplitude * squggleProgress;
    }

    if (thumbX > 0) {
      final Path activePath = Path();

      double startY = cy + math.sin((0 / wavelength) * 2 * math.pi + wavePhase) * amplitude * squggleProgress;
      activePath.moveTo(0, startY);

      for (double x = 1.0; x <= thumbX; x += 1.0) {
        double progress = x / wavelength;
        double y = cy + math.sin(progress * 2 * math.pi + wavePhase) * amplitude * squggleProgress;
        activePath.lineTo(x, y);
      }

      activePath.lineTo(thumbX, thumbY);
      canvas.drawPath(activePath, activePaint);
    }

    if (thumbX + 7 + (thumbOpacity * 5) < trackWidth) {
      canvas.drawLine(Offset(thumbX + 7 + (thumbOpacity * 5), cy), Offset(trackWidth, cy), inactivePaint);
    }

    if (thumbOpacity > 0) canvas.drawCircle(Offset(thumbX, thumbY), 8.0 * thumbOpacity, thumbPaint);
  }

  @override
  bool shouldRepaint(covariant _SquigglySliderPainter oldDelegate) {
    return oldDelegate.progressPercent != progressPercent ||
        oldDelegate.wavePhase != wavePhase ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor ||
        oldDelegate.squggleProgress != squggleProgress ||
        oldDelegate.thumbOpacity != thumbOpacity;
  }
}