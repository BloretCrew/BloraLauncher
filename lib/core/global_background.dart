import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'theme_manager.dart';

class GlobalBackground extends StatelessWidget {
  final Widget child;

  const GlobalBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: ThemeManager.instance,
      builder: (context, _) {
        final config = ThemeManager.instance;
        final imagePath = config.backgroundImage;

        if (imagePath == null || imagePath.isEmpty) {
          return child;
        }

        return Stack(
          children: [
            Positioned.fill(
              child: Container(color: theme.scaffoldBackgroundColor),
            ),
            // Background Image Layer
            Positioned.fill(
              child: ClipRect(
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..translateByDouble(config.backgroundOffsetX, config.backgroundOffsetY, 0.0, 1.0)
                    ..scaleByDouble(config.backgroundScale, config.backgroundScale, config.backgroundScale, 1.0)
                    ..rotateZ(config.backgroundRotation),
                  child: Opacity(
                    opacity: config.backgroundOpacity.clamp(0.0, 1.0),
                    child: ImageFiltered(
                      imageFilter: ImageFilter.blur(
                        sigmaX: config.backgroundBlur,
                        sigmaY: config.backgroundBlur,
                      ),
                      child: _buildImage(imagePath),
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  color: theme.colorScheme.primary.withValues(alpha: 0.05),
                ),
              ),
            ),
            // Content Layer
            Positioned.fill(child: child),
          ],
        );
      },
    );
  }

  Widget _buildImage(String path) {
    if (path.startsWith('http')) {
      return Image.network(path, fit: BoxFit.cover);
    } else if (File(path).existsSync()) {
      return Image.file(File(path), fit: BoxFit.cover);
    } else {
      return const SizedBox.shrink();
    }
  }
}
