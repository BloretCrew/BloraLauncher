import 'dart:async';

import 'package:flutter/material.dart';
import '../core/translate_api.dart';

enum NoticeType { info, warning, error, success }

@immutable
class Notice {
  final String id;
  final String message;
  final IconData icon;
  final bool continueOnHover;
  final bool reusable;
  final int durationMs;
  final NoticeType type;

  Notice({
    required this.message,
    required this.icon,
    this.continueOnHover = false,
    this.reusable = true,
    this.durationMs = 2000,
    this.type = NoticeType.info,
  }) : id = UniqueKey().toString();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Notice && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

final GlobalKey<NoticeOverlayState> noticeOverlayKey =
    GlobalKey<NoticeOverlayState>();

class NoticeOverlay extends StatefulWidget {
  const NoticeOverlay({super.key});

  @override
  State<NoticeOverlay> createState() => NoticeOverlayState();
}

class NoticeOverlayState extends State<NoticeOverlay> {
  final List<Notice> _notices = [];
  final Map<String, int> _remainingMs = {};
  final Set<String> _enteringIds = {};
  final Set<String> _leavingIds = {};
  bool _isHovered = false;
  Timer? _ticker;
  static bool _apiAvailable = false;

  static const double _cardHeight = 60.0;
  static const double _stackOffset = 45.0;

  @override
  void initState() {
    super.initState();
    _checkApiStatus();
    _ticker = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (_notices.isEmpty) {
        if (_isHovered) setState(() => _isHovered = false);
        return;
      }

      setState(() {
        final List<String> toRemove = [];
        for (var notice in _notices) {
          if (_isHovered && !notice.continueOnHover) continue;
          if (_leavingIds.contains(notice.id) ||
              _enteringIds.contains(notice.id)) {
            continue;
          }

          final id = notice.id;
          _remainingMs[id] = (_remainingMs[id] ?? notice.durationMs) - 50;
          if (_remainingMs[id]! <= 0) {
            toRemove.add(id);
          }
        }

        for (var id in toRemove) {
          _removeWithAnimation(id);
        }
      });
    });
  }

  Future<void> _checkApiStatus() async {
    try {
      final status = await TranslateApi.checkApiStatus();
      if (mounted) {
        setState(() {
          _apiAvailable = status;
        });
      }
    } catch (_) {}
  }

  void addNotice(Notice notice) {
    if (!mounted) return;

    if (notice.reusable) {
      int existingIndex = _notices.indexWhere(
        (n) =>
            n.message == notice.message && n.type == notice.type && n.reusable,
      );
      if (existingIndex != -1) {
        final existingNotice = _notices[existingIndex];
        if (!_leavingIds.contains(existingNotice.id)) {
          setState(() {
            _remainingMs[existingNotice.id] = notice.durationMs;
            _notices.removeAt(existingIndex);
            _notices.add(existingNotice);
          });
          return;
        }
      }
    }

    setState(() {
      _notices.add(notice);
      _remainingMs[notice.id] = notice.durationMs;
      _enteringIds.add(notice.id);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _enteringIds.remove(notice.id));
    });
  }

  void showError(String message) {
    addNotice(
      Notice(
        message: message,
        icon: Icons.error_outline,
        type: NoticeType.error,
      ),
    );
  }

  void showWarning(String message) {
    addNotice(
      Notice(
        message: message,
        icon: Icons.warning_amber_rounded,
        type: NoticeType.warning,
      ),
    );
  }

  void showSuccess(String message) {
    addNotice(
      Notice(
        message: message,
        icon: Icons.check_circle_outline,
        type: NoticeType.success,
      ),
    );
  }

  void showInfo(String message) {
    addNotice(
      Notice(message: message, icon: Icons.info_outline, type: NoticeType.info),
    );
  }

  void _removeWithAnimation(String id) {
    if (_leavingIds.contains(id)) return;
    setState(() => _leavingIds.add(id));

    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _notices.removeWhere((n) => n.id == id);
          _remainingMs.remove(id);
          _leavingIds.remove(id);
        });
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _clearAll() {
    final ids = _notices.map((n) => n.id).toList();
    for (final id in ids) {
      _removeWithAnimation(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_notices.isEmpty && _leavingIds.isEmpty) return const SizedBox.shrink();

    final mediaQuery = MediaQuery.of(context);
    final isPortrait = mediaQuery.size.height > mediaQuery.size.width;
    final theme = Theme.of(context);

    return Positioned(
      bottom: mediaQuery.padding.bottom + (isPortrait ? 80 : 20),
      right: isPortrait ? 12 : 20,
      left: isPortrait ? 12 : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(scale: animation, child: child),
            ),
            child: (_notices.length > 2 && !isPortrait)
                ? Padding(
                    key: const ValueKey('clear_button'),
                    padding: const EdgeInsets.only(bottom: 12, right: 12),
                    child: _buildClearButton(theme),
                  )
                : const SizedBox.shrink(key: ValueKey('clear_button_none')),
          ),
          Expanded(
            flex: isPortrait ? 1 : 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: isPortrait
                  ? CrossAxisAlignment.center
                  : CrossAxisAlignment.end,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(scale: animation, child: child),
                  ),
                  child: (_notices.length > 2 && isPortrait)
                      ? Padding(
                          key: const ValueKey('clear_button_portrait'),
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _buildClearButton(theme),
                        )
                      : const SizedBox.shrink(
                          key: ValueKey('clear_button_none_portrait'),
                        ),
                ),
                MouseRegion(
                  hitTestBehavior: HitTestBehavior.translucent,
                  onEnter: (_) => setState(() => _isHovered = true),
                  onExit: (_) => setState(() => _isHovered = false),
                  child: Material(
                    type: MaterialType.transparency,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      width: isPortrait ? null : 360,
                      height: _isHovered
                          ? (_notices.length * (_cardHeight + 10))
                          : (_cardHeight +
                                (_notices.length > 1
                                    ? (_notices.length - 1) * _stackOffset
                                    : 0)),
                      child: Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.bottomCenter,
                        children: _notices.asMap().entries.map((entry) {
                          final index = entry.key;
                          final notice = entry.value;

                          final reversedIndex = _notices.length - 1 - index;

                          final isEntering = _enteringIds.contains(notice.id);
                          final isLeaving = _leavingIds.contains(notice.id);

                          double bottomOffset = 0;
                          double scale = 1.0;
                          double opacity = 1.0;
                          double xOffset = 0;

                          if (_isHovered) {
                            bottomOffset = reversedIndex * (_cardHeight + 10);
                          } else {
                            bottomOffset = reversedIndex * _stackOffset;
                            scale = 1.0 - (reversedIndex * 0.008);
                          }

                          if (isEntering) {
                            xOffset = 300;
                            opacity = 0;
                          }

                          if (isLeaving) {
                            xOffset = 300;
                            opacity = 0;
                          }

                          final remaining =
                              _remainingMs[notice.id] ?? notice.durationMs;
                          final progress = (remaining / notice.durationMs)
                              .clamp(0.0, 1.0);

                          return AnimatedPositioned(
                            key: ValueKey(notice.id),
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOutQuart,
                            bottom: bottomOffset,
                            left: xOffset,
                            right: -xOffset,
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 300),
                              opacity: opacity,
                              child: AnimatedScale(
                                duration: const Duration(milliseconds: 300),
                                scale: scale,
                                curve: Curves.easeOutQuart,
                                child: NoticeCard(
                                  notice: notice,
                                  progress: progress,
                                  onClose: () =>
                                      _removeWithAnimation(notice.id),
                                  apiAvailable: _apiAvailable,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClearButton(ThemeData theme) {
    return Material(
      type: MaterialType.transparency,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Tooltip(
          message: "清除全部",
          child: InkWell(
            onTap: _clearAll,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: theme.colorScheme.surfaceContainerHigh.withValues(
                  alpha: 0.95,
                ),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.5,
                  ),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(
                Icons.delete_sweep_outlined,
                size: 18,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class NoticeCard extends StatefulWidget {
  final Notice notice;
  final double progress;
  final VoidCallback onClose;
  final bool apiAvailable;

  const NoticeCard({
    super.key,
    required this.notice,
    required this.progress,
    required this.onClose,
    required this.apiAvailable,
  });

  @override
  State<NoticeCard> createState() => _NoticeCardState();
}

class _NoticeCardState extends State<NoticeCard> {
  String? _translatedText;
  bool _isTranslating = false;

  bool _isLikelyEnglish(String text) {
    final letters = RegExp(r'[a-zA-Z]').allMatches(text).length;
    final total = text.replaceAll(RegExp(r'\s'), '').length;
    if (total == 0) return false;
    return (letters / total) > 0.5;
  }

  Future<void> _translate() async {
    if (_isTranslating || _translatedText != null) return;
    setState(() => _isTranslating = true);

    try {
      final translated = await TranslateApi.translate(widget.notice.message);
      if (mounted && translated != widget.notice.message) {
        setState(() {
          _translatedText = translated;
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isTranslating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    Color accentColor;
    switch (widget.notice.type) {
      case NoticeType.error:
        accentColor = Colors.redAccent;
        break;
      case NoticeType.warning:
        accentColor = Colors.orangeAccent;
        break;
      case NoticeType.success:
        accentColor = Colors.green;
        break;
      case NoticeType.info:
        accentColor = colorScheme.primary;
        break;
    }

    final bool showTranslate =
        widget.apiAvailable &&
        _translatedText == null &&
        _isLikelyEnglish(widget.notice.message);

    return Container(
      height: 60,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.98),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Stack(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: accentColor),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Icon(widget.notice.icon, size: 18, color: accentColor),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _translatedText ?? widget.notice.message,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontSize: 13,
                            color: colorScheme.onSurface,
                            height: 1.2,
                          ),
                        ),
                      ),
                      if (showTranslate) ...[
                        const SizedBox(width: 4),
                        _isTranslating
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : IconButton(
                                icon: const Icon(Icons.translate, size: 16),
                                onPressed: _translate,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 24,
                                  minHeight: 24,
                                ),
                                splashRadius: 16,
                                visualDensity: VisualDensity.compact,
                                color: colorScheme.primary,
                              ),
                      ],
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: widget.onClose,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 24,
                          minHeight: 24,
                        ),
                        splashRadius: 16,
                        visualDensity: VisualDensity.compact,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 3,
              color: accentColor.withValues(alpha: 0.1),
              alignment: Alignment.centerLeft,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 50),
                    curve: Curves.linear,
                    width: constraints.maxWidth * widget.progress,
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.8),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
