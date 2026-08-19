import 'package:bloret_launcher/core/global.dart';
import 'package:flutter/material.dart';
import '../main.dart';

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

void showError(String message, {int duration = 5000}) =>
    noticeManager.showError(globalShellContext, message, duration: duration);

void showWarning(String message, {int duration = 5000}) =>
    noticeManager.showWarning(globalShellContext, message, duration: duration);

void showSuccess(String message, {int duration = 5000}) =>
    noticeManager.showSuccess(globalShellContext, message, duration: duration);

void showInfo(String message, {int duration = 5000}) =>
    noticeManager.showInfo(globalShellContext, message, duration: duration);

extension WithOpacity on Color {
  Color withOpacityEx(double opacity) => withAlpha((opacity * 255).toInt());
}

extension StringFormatExtension on String {
  String format([
    Object? arg0,
    Object? arg1,
    Object? arg2,
    Object? arg3,
    Object? arg4,
  ]) {
    final args = [arg0, arg1, arg2, arg3, arg4];
    var index = 0;

    return replaceAllMapped(RegExp(r'%s'), (match) {
      if (index >= args.length || args[index] == null) {
        return match.group(0)!;
      }

      return '${args[index++]}';
    });
  }
}

extension StringCapitalizeExtension on String {
  String get capitalize {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }
}