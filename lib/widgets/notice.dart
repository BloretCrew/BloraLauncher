import 'dart:async';
import 'package:flutter/material.dart';

import '../core/i18n.dart';
import 'log_viewer.dart';

@immutable
class Notice {
  final String id;
  final String message;
  final IconData icon;

  Notice({
    required this.message,
    required this.icon,
  }) : id = UniqueKey().toString();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is Notice && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

final GlobalKey<NoticeOverlayState> noticeOverlayKey = GlobalKey<
    NoticeOverlayState>();


class NoticeOverlay extends StatefulWidget {
  const NoticeOverlay({super.key});

  @override
  State<NoticeOverlay> createState() => NoticeOverlayState();
}

class NoticeOverlayState extends State<NoticeOverlay> with SingleTickerProviderStateMixin {
  final List<Notice> _notices = [];
  final Map<String, DateTime> _timestamps = {};
  final Set<String> _entryAnimationPlayedIds = <String>{};

  Timer? _ticker;

  static const _noticeDuration = Duration(seconds: 3);

  late final AnimationController _listController;
  late Animation<double> _listAnimation;
  double _previousColumnHeight = 0.0;
  double _currentColumnHeight = 0.0;

  final Set<String> _dismissingIds = <String>{};

  static const double _cardHeightWithPadding = 50.0 + 8.0;

  void _onEntryAnimationCompleted(String noticeId) {
    _entryAnimationPlayedIds.add(noticeId);
  }

  @override
  void initState() {
    super.initState();
    _listController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _listAnimation = CurvedAnimation(parent: _listController, curve: Curves.easeOut);

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final now = DateTime.now();
      final expiredIds = _timestamps.entries
          .where((entry) =>
            now.difference(entry.value) > _noticeDuration &&
            !_dismissingIds.contains(entry.key))
          .map((entry) => entry.key)
          .toList();

      if (expiredIds.isNotEmpty) {
        setState(() {
          _dismissingIds.addAll(expiredIds);
        });
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _listController.dispose();
    super.dispose();
  }

  void addNotice(Notice notice) {
    if (!mounted || _notices.any((n) => n.id == notice.id)) return;

    _animateColumnTransition(() {
      _timestamps[notice.id] = DateTime.now();
      _notices.insert(0, notice);
    });
  }

  void _removeNotice(Notice notice) {
    final int index = _notices.indexWhere((n) => n.id == notice.id);
    if (!mounted || index == -1) return;

    setState(() {
      _timestamps.remove(notice.id);
      _dismissingIds.remove(notice.id);
      _notices.removeWhere((n) => n.id == notice.id);
      _entryAnimationPlayedIds.remove(notice.id);

      _previousColumnHeight = _currentColumnHeight;
      _currentColumnHeight = _notices.length * _cardHeightWithPadding;
    });
  }

  void _animateColumnTransition(VoidCallback action) {
    _previousColumnHeight = _notices.length * _cardHeightWithPadding;

    setState(action);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _currentColumnHeight = _notices
          .where((n) => !_dismissingIds.contains(n.id))
          .length * _cardHeightWithPadding;

      if (_previousColumnHeight != _currentColumnHeight) {
        _listController.forward(from: 0.0);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: MediaQuery.of(context).padding.bottom + 10,
      left: 12,
      right: 12,
      child: Material(
        type: MaterialType.transparency,
        child: AnimatedBuilder(
          animation: _listAnimation,
          builder: (context, child) {
            final double heightDifference = _currentColumnHeight - _previousColumnHeight;
            final double dy = heightDifference * (1.0 - _listAnimation.value);

            return Transform.translate(
              offset: Offset(0, -dy/4),
              child: child,
            );
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: _notices.reversed.map((notice) {
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: NoticeCard(
                  key: ValueKey(notice.id),
                  notice: notice,
                  isDismissing: _dismissingIds.contains(notice.id),
                  onDismissed: () => _removeNotice(notice),
                  hasEntryAnimationPlayed: _entryAnimationPlayedIds.contains(notice.id),
                  onEntryAnimationCompleted: () => _onEntryAnimationCompleted(notice.id),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

}

class NoticeCard extends StatefulWidget {
  final Notice notice;
  final VoidCallback onDismissed;
  final bool isDismissing;
  final bool hasEntryAnimationPlayed;
  final VoidCallback onEntryAnimationCompleted;

  const NoticeCard({
    super.key,
    required this.notice,
    required this.onDismissed,
    this.isDismissing = false,
    required this.hasEntryAnimationPlayed,
    required this.onEntryAnimationCompleted,
  });

  @override
  State<NoticeCard> createState() => _NoticeCardState();
}

class _NoticeCardState extends State<NoticeCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _offsetAnimation;
  Animation<double>? _widthAnimation;

  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _offsetAnimation = Tween<double>(begin: 50.0, end: 0.0)
        .animate(
        CurvedAnimation(parent: _controller, curve: Curves.linearToEaseOut));

    if (widget.hasEntryAnimationPlayed) {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(covariant NoticeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isDismissing && !oldWidget.isDismissing) {
      _startDismiss();
    }
  }

  void _startDismiss() {
    if (mounted) {
      _controller.reverse().whenComplete(() {
        widget.onDismissed();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _showDetailsDialog() {
    showDialog(
      context: context,
      builder: (_) => NoticeDetailDialog(notice: widget.notice),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (!_isInitialized) {
      _isInitialized = true;
    }
    if (_widthAnimation == null) {
      final TextPainter textPainter = TextPainter(
        text: TextSpan(text: widget.notice.message, style: TextStyle(color: colorScheme.onSurface)),
        maxLines: 1,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: double.infinity);

      const double padding = 12.0 * 2;
      const double iconWidth = 24.0;
      const double spacing = 10.0;
      const double detailsButtonWidth = 80.0; // Estimate for 'Details' button

      double contentWidth = textPainter.width + padding * 1.2 + iconWidth + spacing;
      if (textPainter.width > 150) {
        contentWidth += detailsButtonWidth;
      }

      final double screenWidth = MediaQuery.of(context).size.width;
      final double targetWidth = contentWidth.clamp(
        screenWidth * 0.4, // Increased min width to prevent overflow during animation
        screenWidth * 0.9, // max width
      );

      _widthAnimation = Tween<double>(begin: screenWidth * 0.4, end: targetWidth)
          .animate(CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.7, curve: Curves.linearToEaseOut),
      ));

      if (!widget.hasEntryAnimationPlayed) {
        _controller.forward().whenComplete(() {
          widget.onEntryAnimationCompleted();
        });
      }
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final double currentWidth = _widthAnimation!.value;

        return Transform.translate(
          offset: Offset(0, _offsetAnimation.value),
          child: Align(
            alignment: Alignment.center,
            child: SizedBox(
              width: currentWidth,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    )
                  ],
                ),
                child: ClipRect(
                  child: Row(
                    mainAxisSize: MainAxisSize.max,
                    children: [
                      Icon(widget.notice.icon, color: colorScheme.onSurface),
                      const SizedBox(width: 10),

                      Expanded(
                        child: Text(
                          widget.notice.message,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: colorScheme.onSurface),
                        ),
                      ),

                      LayoutBuilder(
                        builder: (context, textConstraints) {
                          final painter = TextPainter(
                            text: TextSpan(
                              text: widget.notice.message,
                              style: TextStyle(color: colorScheme.onSurface),
                            ),
                            maxLines: 1,
                            textDirection: TextDirection.ltr,
                          )..layout(maxWidth: double.infinity);

                          const double otherElementsWidth = 24.0 + 10.0 + 24.0;
                          if (painter.width > (currentWidth - otherElementsWidth)) {
                            return TextButton(
                              onPressed: _showDetailsDialog,
                              style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap
                              ),
                              child: Text("Details".tl),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class NoticeDetailDialog extends StatelessWidget {
  final Notice notice;

  const NoticeDetailDialog({super.key, required this.notice});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return HoshivetwDialog(
      title: "Details".tl,
      icon: Icon(notice.icon, color: colorScheme.primary),
      content: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        child: SingleChildScrollView(
          child: Text(notice.message),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text("Close".tl),
        ),
      ],
    );
  }
}