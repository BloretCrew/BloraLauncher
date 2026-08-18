import 'package:flutter/material.dart';

import '../widgets/notice.dart';

class NoticeManager {

  NoticeManager._private();

  static final NoticeManager _instance = NoticeManager._private();

  static NoticeManager get instance => _instance;

  OverlayEntry? _overlayEntry;

  /// View a new notice
  ///
  /// [context] or [overlay] is required.
  /// [message] is notice's content.
  /// [icon] is notice's icon.

  void show(BuildContext? context, {
    OverlayState? overlay,
    required String message,
    required IconData icon,
    bool continueOnHover = false,
    int duration = 5000,
    NoticeType type = NoticeType.info,
  }) {
    bool isFirstTime = false;
    if (_overlayEntry == null) {
      isFirstTime = true;
      OverlayState? overlayState = overlay ?? (context != null ? Overlay.maybeOf(context) : null);
      if (overlayState == null) return;

      _overlayEntry = OverlayEntry(
        builder: (context) => NoticeOverlay(key: noticeOverlayKey),
      );
      overlayState.insert(_overlayEntry!);
    }

    final notice = Notice(
      message: message, 
      icon: icon, 
      continueOnHover: continueOnHover, 
      durationMs: duration,
      type: type,
    );

    if (isFirstTime) {
      // Need one frame to ensure NoticeOverlay is mounted
      WidgetsBinding.instance.addPostFrameCallback((_) {
        noticeOverlayKey.currentState?.addNotice(notice);
      });
    } else {
      // If already exists, try to add immediately. 
      // If it fails (e.g. called during build), fallback to post frame.
      if (noticeOverlayKey.currentState != null) {
        noticeOverlayKey.currentState!.addNotice(notice);
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          noticeOverlayKey.currentState?.addNotice(notice);
        });
      }
    }
  }

  void showError(BuildContext? context, String message, {int duration = 5000}) {
    show(context, message: message, icon: Icons.error_outline, type: NoticeType.error, duration: duration);
  }

  void showWarning(BuildContext? context, String message, {int duration = 5000}) {
    show(context, message: message, icon: Icons.warning_amber_rounded, type: NoticeType.warning, duration: duration);
  }

  void showSuccess(BuildContext? context, String message, {int duration = 5000}) {
    show(context, message: message, icon: Icons.check_circle_outline, type: NoticeType.success, duration: duration);
  }

  void showInfo(BuildContext? context, String message, {int duration = 5000}) {
    show(context, message: message, icon: Icons.info_outline, type: NoticeType.info, duration: duration);
  }


  /// Remove and destroy the floating layer
  void dispose() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }
}
