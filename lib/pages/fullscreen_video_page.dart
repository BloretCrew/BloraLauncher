import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class FullScreenVideoPage extends StatelessWidget {
  final RTCVideoRenderer? renderer;
  final String title;

  const FullScreenVideoPage({super.key, this.renderer, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
            Navigator.pop(context);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Stack(
          children: [
            Hero(
              tag: 'video-$title',
              child: SizedBox.expand(
                child: renderer != null ? RTCVideoView(
                  renderer!,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                ) : const Center(child: Icon(Icons.person, size: 48, color: Colors.white)),
              ),
            ),
            if (Platform.isAndroid) Positioned(
              top: 40,
              left: 20,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white, size: 30),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
