import 'package:flutter/material.dart';
import '../services/notice_manager.dart';

extension NoticeStateExtension on State {
  void showError(String message, {int duration = 5000}) {
    if (!mounted) return;
    noticeManager.showError(context, message, duration: duration);
  }

  void showWarning(String message, {int duration = 5000}) {
    if (!mounted) return;
    noticeManager.showWarning(context, message, duration: duration);
  }

  void showSuccess(String message, {int duration = 5000}) {
    if (!mounted) return;
    noticeManager.showSuccess(context, message, duration: duration);
  }

  void showInfo(String message, {int duration = 5000}) {
    if (!mounted) return;
    noticeManager.showInfo(context, message, duration: duration);
  }
}

extension NoticeContextExtension on BuildContext {
  void showError(String message, {int duration = 5000}) =>
      noticeManager.showError(this, message, duration: duration);

  void showWarning(String message, {int duration = 5000}) =>
      noticeManager.showWarning(this, message, duration: duration);

  void showSuccess(String message, {int duration = 5000}) =>
      noticeManager.showSuccess(this, message, duration: duration);

  void showInfo(String message, {int duration = 5000}) =>
      noticeManager.showInfo(this, message, duration: duration);
}

extension WithOpacity on Color {
  Color withOpacityEx(double opacity) => withAlpha((opacity * 255).toInt());
}