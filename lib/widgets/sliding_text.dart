import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class SlidingTextCycle extends StatefulWidget {
  final List<String> sentences;
  final TextStyle style;
  final Duration interval;
  final Duration duration;
  final double? width;

  const SlidingTextCycle({
    super.key,
    required this.sentences,
    this.style = const TextStyle(fontSize: 18, color: Colors.white70),
    this.interval = const Duration(seconds: 5),
    this.duration = const Duration(milliseconds: 1500),
    this.width,
  });

  @override
  State<SlidingTextCycle> createState() => _SlidingTextCycleState();
}

class _SlidingTextCycleState extends State<SlidingTextCycle> {
  int _currentIndex = 0;
  Timer? _timer;

  static final _enteringOffsetTween = Tween<Offset>(begin: const Offset(0, 1.0), end: Offset.zero);
  static final _exitingOffsetTween = Tween<Offset>(begin: const Offset(0, -1.0), end: Offset.zero);

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void didUpdateWidget(SlidingTextCycle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(widget.sentences, oldWidget.sentences)) {
      _timer?.cancel();
      setState(() {
        _currentIndex = 0;
      });
      _startTimer();
    }
  }

  void _startTimer() {
    if (widget.sentences.isEmpty) return;
    if (widget.sentences.length <= 1) return;

    _timer = Timer.periodic(widget.interval, (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _currentIndex = (_currentIndex + 1) % widget.sentences.length;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.sentences.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      width: widget.width ?? double.infinity,
      height: (widget.style.fontSize ?? 18) * 1.5,
      child: ClipRect(
        child: AnimatedSwitcher(
          duration: widget.duration,
          switchInCurve: Curves.easeOutQuart,
          switchOutCurve: Curves.easeInQuart,
          transitionBuilder: (Widget child, Animation<double> animation) {
            final isEntering = child.key == ValueKey(_currentIndex);

            final Animation<Offset> offsetAnimation = (isEntering
                ? _enteringOffsetTween.animate(CurvedAnimation(parent: animation, curve: Curves.easeOutQuart))
                : _exitingOffsetTween.animate(CurvedAnimation(parent: animation, curve: Curves.easeInQuart)));

            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: offsetAnimation,
                child: child,
              ),
            );
          },
          layoutBuilder: (Widget? currentChild, List<Widget> previousChildren) {
            return Stack(
              alignment: Alignment.centerLeft,
              children: <Widget>[
                ...previousChildren,
                ?currentChild,
              ],
            );
          },
          child: Container(
            key: ValueKey(_currentIndex),
            width: widget.width ?? double.infinity,
            alignment: Alignment.centerLeft,
            child: Text(
              widget.sentences[_currentIndex.clamp(0, widget.sentences.length - 1)],
              style: widget.style,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }
}