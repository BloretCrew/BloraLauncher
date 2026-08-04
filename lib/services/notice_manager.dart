import 'package:flutter/material.dart';

import '../widgets/notice.dart';

final noticeManager = NoticeManager.instance;

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

    final notice = Notice(message: message, icon: icon);

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


  /// Remove and destroy the floating layer
  void dispose() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }
}
