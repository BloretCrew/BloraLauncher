import 'dart:ffi';
import 'package:bloret_launcher/widgets/button.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:bloret_launcher/services/config_service.dart';

class WindowBridge {
  static const _channel = BasicMessageChannel('bloret/window_event', StringCodec());
  
  static final DynamicLibrary _dylib = DynamicLibrary.executable();
  static final void Function() _destroyApp = _dylib.lookup<NativeFunction<Void Function()>>('DestroyApp').asFunction();
  static final void Function() _hideApp = _dylib.lookup<NativeFunction<Void Function()>>('HideApp').asFunction();

  static void init(BuildContext context) {
    _channel.setMessageHandler((message) async {
      final cleanMessage = message?.toString().trim();
      
      if (cleanMessage == "on_close") {
        String behavior = ConfigService.getExitBehavior();

        if (behavior == "ask") {
          bool remember = false;
          final shouldExit = await showDialog<bool>(
            context: context,
            builder: (context) => StatefulBuilder(builder: (context, setInnerState) {
              return AlertDialog(
                title: Row(
                  children: [
                    const Icon(Icons.exit_to_app,),
                    const SizedBox(width: 12),
                    const Text("关闭 Bloret Launcher"),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "确定要退出吗？\n隐藏到后台可以继续保持运行，方便下次快速启动。",
                      style: TextStyle(height: 1.5),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.grey.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: CheckboxListTile(
                        value: remember,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        title: const Text("不再询问，记住我的选择", style: TextStyle(fontSize: 14)),
                        onChanged: (v) => setInnerState(() => remember = v!),
                      ),
                    ),
                  ],
                ),
                actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                actions: [
                  BloretButton(
                    onPressed: () => Navigator.pop(context, false),
                    height: 42,
                    text: "隐藏到后台",
                  ),
                  const SizedBox(width: 8),
                  BloretButton(
                    onPressed: () => Navigator.pop(context, true),
                    height: 42,
                    text: "彻底退出",
                  ),
                ],
              );
            }),
          );

          if (shouldExit != null) {
            behavior = shouldExit ? "exit" : "hide";
            if (remember) {
              await ConfigService.setExitBehavior(behavior);
            }
          } else {
            return "null";
          }
        }

        if (behavior == "exit") {
          _destroyApp();
        } else {
          _hideApp();
        }
      }
      return "null";
    });
  }
}
