import 'dart:ffi';
import 'package:bloret_launcher/services/launch_service.dart';
import 'package:bloret_launcher/widgets/button.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:bloret_launcher/services/config_service.dart';

import 'i18n.dart';

class WindowBridge {
  static const _channel = BasicMessageChannel('bloret/window_event', StringCodec());
  
  static final DynamicLibrary _dylib = DynamicLibrary.executable();
  static final void Function() _destroyApp = _dylib.lookup<NativeFunction<Void Function()>>('DestroyApp').asFunction();
  static final void Function() _hideApp = _dylib.lookup<NativeFunction<Void Function()>>('HideApp').asFunction();

  static Future<void> quit() async {
    await CoreManager.instance.killCoresOnExit();
    _destroyApp();
  }

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
                    Text("Close Bloret Launcher".tl),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "${"Are you sure you want to exit?".tl}\n${"Hiding to background will keep the launcher running for faster startup.".tl}",
                      style: const TextStyle(height: 1.5),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: CheckboxListTile(
                        value: remember,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        title: Text("Don't ask again, remember my choice".tl, style: const TextStyle(fontSize: 14)),
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
                    text: "Hide to background".tl,
                  ),
                  const SizedBox(width: 8),
                  BloretButton(
                    onPressed: () => Navigator.pop(context, true),
                    height: 42,
                    text: "Quit".tl,
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
          await quit();
        } else {
          _hideApp();
        }
      } else if (cleanMessage == "on_quit") {
        await quit();
      }
      return "null";
    });
  }
}
