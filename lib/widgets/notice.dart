import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

enum NoticeType { info, warning, error, success }

@immutable
class Notice {
  final String id;
  final String message;
  final IconData icon;
  final bool continueOnHover;
  final int durationMs;
  final NoticeType type;

  Notice({
    required this.message,
    required this.icon,
    this.continueOnHover = false,
    this.durationMs = 5000,
    this.type = NoticeType.info,
  }) : id = UniqueKey().toString();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Notice && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

final GlobalKey<NoticeOverlayState> noticeOverlayKey = GlobalKey<NoticeOverlayState>();

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

  static const double _cardHeight = 64.0;
  static const double _stackOffset = 6.0;

  @override
  void initState() {
    super.initState();
    _checkApiStatus();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (_notices.isEmpty) return;

      final activeNotice = _notices.first;
      if (_isHovered && !activeNotice.continueOnHover) return;

      setState(() {
        // Only the bottom-most (first in list) notice's timer counts down
        final activeId = activeNotice.id;
        if (!_enteringIds.contains(activeId)) {
          _remainingMs[activeId] = (_remainingMs[activeId] ?? activeNotice.durationMs) - 100;
          if (_remainingMs[activeId]! <= 0) {
            _removeWithAnimation(activeId);
          }
        }
      });
    });
  }

  Future<void> _checkApiStatus() async {
    try {
      final dio = Dio();
      final response = await dio.get(
        "https://translate.googleapis.com/translate_a/single",
        queryParameters: {
          "client": "gtx",
          "sl": "auto",
          "tl": "zh-CN",
          "dt": "t",
          "q": "ping",
        },
      ).timeout(const Duration(seconds: 3));

      if (mounted) {
        setState(() {
          _apiAvailable = response.statusCode == 200;
        });
      }
    } catch (_) {}
  }

  void addNotice(Notice notice) {
    if (!mounted) return;
    setState(() {
      _notices.add(notice); 
      _remainingMs[notice.id] = notice.durationMs;
      _enteringIds.add(notice.id);
    });
    
    // Trigger the slide-in animation immediately in the next frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _enteringIds.remove(notice.id));
    });
  }

  void showError(String message) {
    addNotice(Notice(
      message: message,
      icon: Icons.error_outline,
      type: NoticeType.error,
    ));
  }

  void showWarning(String message) {
    addNotice(Notice(
      message: message,
      icon: Icons.warning_amber_rounded,
      type: NoticeType.warning,
    ));
  }

  void showSuccess(String message) {
    addNotice(Notice(
      message: message,
      icon: Icons.check_circle_outline,
      type: NoticeType.success,
    ));
  }

  void showInfo(String message) {
    addNotice(Notice(
      message: message,
      icon: Icons.info_outline,
      type: NoticeType.info,
    ));
  }

  void _removeWithAnimation(String id) {
    if (_leavingIds.contains(id)) return;
    setState(() => _leavingIds.add(id));
    
    Future.delayed(const Duration(milliseconds: 400), () {
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
            duration: const Duration(milliseconds: 400),
            switchInCurve: Curves.easeOutBack,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: animation.drive(Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)),
                child: child,
              ),
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
              crossAxisAlignment: isPortrait ? CrossAxisAlignment.center : CrossAxisAlignment.end,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  switchInCurve: Curves.easeOutBack,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: animation.drive(Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)),
                      child: child,
                    ),
                  ),
                  child: (_notices.length > 2 && isPortrait)
                      ? Padding(
                          key: const ValueKey('clear_button_portrait'),
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _buildClearButton(theme),
                        )
                      : const SizedBox.shrink(key: ValueKey('clear_button_none_portrait')),
                ),
                MouseRegion(
                  onEnter: (_) => setState(() => _isHovered = true),
                  onExit: (_) => setState(() => _isHovered = false),
                  child: Material(
                    type: MaterialType.transparency,
                    child: SizedBox(
                      width: isPortrait ? null : 360,
                      height: _isHovered 
                          ? (_notices.length * (_cardHeight + 6)) 
                          : (_cardHeight + (_notices.length > 1 ? (_notices.length - 1) * _stackOffset : 0)),
                      child: Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.bottomCenter,
                        children: _notices.asMap().entries.map((entry) {
                          final index = entry.key;
                          final notice = entry.value;
                          
                          final isEntering = _enteringIds.contains(notice.id);
                          final isLeaving = _leavingIds.contains(notice.id);
                          
                          // Stack logic: index 0 is at bottom (active), index 1+ are behind
                          double bottomOffset = 0;
                          double scale = 1.0;
                          double opacity = 1.0;
                          double xOffset = 0;

                          if (_isHovered) {
                            bottomOffset = index * (_cardHeight + 6);
                          } else {
                            bottomOffset = index * _stackOffset;
                            scale = 1.0 - (index * 0.02);
                            // Ensure current active one is fully opaque, others behind are slightly transparent
                            opacity = (1.0 - (index * 0.1)).clamp(0.6, 1.0);
                          }

                          // Entry animation: Slide from right
                          if (isEntering) {
                            xOffset = 200;
                            opacity = 0;
                          }
                          
                          // Exit animation: Slide to right and fade
                          if (isLeaving) {
                            xOffset = 200;
                            opacity = 0;
                          }

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
                                  onClose: () => _removeWithAnimation(notice.id),
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
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.95),
                border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ],
              ),
              child: Icon(Icons.delete_sweep_outlined, size: 20, color: theme.colorScheme.onSurface),
            ),
          ),
        )
      ),
    );
  }
}

class NoticeCard extends StatefulWidget {
  final Notice notice;
  final VoidCallback onClose;
  final bool apiAvailable;

  const NoticeCard({
    super.key,
    required this.notice,
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
      final dio = Dio();
      final response = await dio.get(
        "https://translate.googleapis.com/translate_a/single",
        queryParameters: {
          "client": "gtx",
          "sl": "auto",
          "tl": "zh-CN",
          "dt": "t",
          "q": widget.notice.message,
        },
      );

      if (response.statusCode == 200 && response.data is List) {
        final List parts = response.data[0];
        final translated = parts.map((p) => p[0]).join();
        if (mounted) {
          setState(() {
            _translatedText = translated;
          });
        }
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
      case NoticeType.error: accentColor = Colors.redAccent; break;
      case NoticeType.warning: accentColor = Colors.orangeAccent; break;
      case NoticeType.success: accentColor = Colors.green; break;
      case NoticeType.info: accentColor = colorScheme.primary; break;
    }

    final bool showTranslate = widget.apiAvailable && 
        _translatedText == null && 
        _isLikelyEnglish(widget.notice.message);

    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.98),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          )
        ],
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 4,
            decoration: BoxDecoration(
              color: accentColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                bottomLeft: Radius.circular(8),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                      ),
                    ),
                  ),
                  if (showTranslate) ...[
                    const SizedBox(width: 4),
                    _isTranslating 
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : IconButton(
                          icon: const Icon(Icons.translate, size: 16),
                          onPressed: _translate,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
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
                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
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
    );
  }
}

