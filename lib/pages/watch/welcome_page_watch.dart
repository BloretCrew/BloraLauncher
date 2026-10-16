import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:bloret_launcher/core/i18n.dart';
import 'package:bloret_launcher/services/config_service.dart';
import 'package:bloret_launcher/widgets/windows_widgets.dart';

import '../../main.dart';

class WelcomeSetupScreenWatch extends StatelessWidget {
  final bool isRound;
  final int currentStep;
  final bool loginSkipped;
  final int totalSteps = 6;
  final Function(int) onStepChanged;
  final String selectedLanguage;
  final Function(String) onLanguageChanged;
  final Map<String, String> availableLanguages;
  final bool isWaitingForLogin;
  final VoidCallback onLoginPressed;
  final VoidCallback onFinish;
  final VoidCallback onBack;
  final bool nextDisabled;

  const WelcomeSetupScreenWatch({
    super.key,
    required this.isRound,
    required this.currentStep,
    required this.loginSkipped,
    required this.onStepChanged,
    required this.selectedLanguage,
    required this.onLanguageChanged,
    required this.availableLanguages,
    required this.isWaitingForLogin,
    required this.onLoginPressed,
    required this.onFinish,
    required this.onBack,
    this.nextDisabled = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Stack(
        children: [
          Positioned(
            top: isRound ? 0 : 8,
            left: 0,
            right: 0,
            child: _buildWatchProgressIndicator(context),
          ),

          Padding(
            padding: EdgeInsets.fromLTRB(
              isRound ? 20 : 12, 
              isRound ? 36 : 28, 
              isRound ? 20 : 12, 
              8
            ),
            child: Column(
              children: [
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 500),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (Widget child, Animation<double> animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.05),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      );
                    },
                    child: SingleChildScrollView(
                      key: ValueKey<int>(currentStep),
                      physics: const BouncingScrollPhysics(),
                      child: _buildStepContent(context),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                _buildButtons(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWatchProgressIndicator(BuildContext context) {
    final theme = Theme.of(context);
    
    if (isRound) {
      return SizedBox(
        height: 40,
        child: TweenAnimationBuilder<double>(
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOutBack,
          tween: Tween<double>(end: currentStep.toDouble()),
          builder: (context, value, child) {
            return CustomPaint(
              painter: _ArcDotsPainter(
                animatedStep: value,
                totalSteps: totalSteps,
                loginSkipped: loginSkipped,
                color: theme.colorScheme.primary,
                inactiveColor: theme.colorScheme.outlineVariant,
              ),
            );
          },
        ),
      );
    } else {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(totalSteps, (index) {
            final bool isCurrent = index == currentStep;
            final bool isCompleted = index < currentStep;
            
            Color dotColor = isCurrent ? theme.colorScheme.primary : theme.colorScheme.outlineVariant;
            if (isCompleted) {
              dotColor = (index == 2 && loginSkipped) ? Colors.orange : Colors.green;
            }

            return AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutBack,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: isCurrent ? 7 : 4,
              height: isCurrent ? 7 : 4,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: dotColor,
              ),
            );
          }),
        ),
      );
    }
  }

  Widget _buildStepContent(BuildContext context) {
    final theme = Theme.of(context);
    final headerStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w900,
      fontSize: 14,
    );
    final bodyStyle = const TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
    );
    final hintStyle = TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w500,
      color: Colors.grey[600],
    );

    switch (currentStep) {
      case 0:
        return Column(
          children: [
            const SizedBox(height: 8),
            Hero(
              tag: "launcher_logo",
              child: SizedBox(
                width: 48,
                height: 48,
                child: Image.asset(
                  theme.brightness == Brightness.light
                      ? "assets/bloret_light.png"
                      : "assets/bloret_dark.png",
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              "${"Welcome to".tl} $name Launcher",
              textAlign: TextAlign.center,
              style: headerStyle,
            ),
            const SizedBox(height: 2),
            Text(
              "Flutter WearOS Edition".tl,
              textAlign: TextAlign.center,
              style: hintStyle.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              "${"Welcome! Let's start the journey with".tl} $name Launcher!\n${"Next, we need to perform some essential operations.".tl}",
              textAlign: TextAlign.center,
              style: bodyStyle,
            ),
          ],
        );
      case 1:
        return Column(
          children: [
            Text("Select Language".tl, textAlign: TextAlign.center, style: headerStyle),
            const SizedBox(height: 8),
            Text(
              "Please select the interface language you wish to use:".tl,
              textAlign: TextAlign.center,
              style: hintStyle,
            ),
            const SizedBox(height: 16),
            Win11Dropdown(
              items: availableLanguages.entries.map((e) {
                return Win11DropdownItem(label: e.value, value: e.key);
              }).toList(),
              initialValue: selectedLanguage,
              onChanged: (val) {
                if (val != null) onLanguageChanged(val);
              },
              height: 38,
              textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ],
        );
      case 2:
        final bool isLoggedIn = ConfigService.get('Bloret_PassPort_Login') ?? false;
        return Column(
          children: [
            Text("Login to Bloret PassPort".tl, textAlign: TextAlign.center, style: headerStyle),
            const SizedBox(height: 8),
            Text(
              "Login to Bloret PassPort to sync your Minecraft accounts and settings.".tl,
              textAlign: TextAlign.center,
              style: bodyStyle,
            ),
            const SizedBox(height: 20),
            if (isWaitingForLogin)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            else
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: onLoginPressed,
                child: Text(isLoggedIn ? "Continue".tl : "Go to login".tl, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            const SizedBox(height: 12),
            Text(
              "Tip: You must log in to Bloret PassPort to get full service.".tl,
              textAlign: TextAlign.center,
              style: hintStyle,
            ),
          ],
        );
      default:
        return Column(
          children: [
            const Icon(Icons.auto_awesome_rounded, size: 36, color: Colors.orangeAccent),
            const SizedBox(height: 8),
            Text("Ready to go!".tl, style: headerStyle),
            const SizedBox(height: 8),
            Text(
              "Java environment and folders can be managed in settings later.".tl,
              textAlign: TextAlign.center,
              style: bodyStyle,
            ),
          ],
        );
    }
  }

  Widget _buildButtons(BuildContext context) {
    final bool showBack = currentStep > 0;
    final theme = Theme.of(context);

    return SizedBox(
      height: 48,
      child: Stack(
        children: [
          AnimatedAlign(
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutBack,
            alignment: showBack ? const Alignment(-0.6, 0) : Alignment.center,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 400),
              opacity: showBack ? 1.0 : 0.0,
              child: IgnorePointer(
                ignoring: !showBack,
                child: IconButton(
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                  visualDensity: VisualDensity.compact,
                  color: Colors.grey,
                ),
              ),
            ),
          ),

          AnimatedAlign(
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutBack,
            alignment: showBack ? const Alignment(0.6, 0) : Alignment.center,
            child: IconButton(
              onPressed: nextDisabled
                  ? null
                  : (currentStep >= 3 ? onFinish : () => onStepChanged(currentStep + 1)),
              icon: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Icon(
                  currentStep >= 3
                      ? Icons.check_circle_rounded
                      : Icons.arrow_forward_ios_rounded,
                  key: ValueKey(currentStep >= 3),
                  size: currentStep >= 3 ? 32 : 18,
                ),
              ),
              color: theme.colorScheme.primary,
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
    );
  }
}

class _ArcDotsPainter extends CustomPainter {
  final double animatedStep;
  final int totalSteps;
  final bool loginSkipped;
  final Color color;
  final Color inactiveColor;

  _ArcDotsPainter({
    required this.animatedStep,
    required this.totalSteps,
    required this.loginSkipped,
    required this.color,
    required this.inactiveColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double radius = size.width / 2;
    final Offset center = Offset(radius, radius);
    
    const double startAngle = -math.pi * 0.75;
    const double sweepAngle = math.pi * 0.5;
    
    for (int i = 0; i < totalSteps; i++) {
      final double angle = startAngle + (sweepAngle / (totalSteps - 1)) * i;
      
      // 动画插值计算大小
      double distance = (animatedStep - i).abs();
      double t = (1.0 - distance).clamp(0.0, 1.0);
      t = math.pow(t, 2).toDouble(); 

      final double dotRadius = 2.2 + (2.3 * t);
      final double offsetRadius = radius - 8;
      
      final Offset dotCenter = Offset(
        center.dx + offsetRadius * math.cos(angle),
        center.dy + offsetRadius * math.sin(angle),
      );
      
      // 颜色逻辑
      Color drawColor = inactiveColor;
      if (i < animatedStep.round()) {
        // 已完成步骤的颜色逻辑
        drawColor = (i == 2 && loginSkipped) ? Colors.orange : Colors.green;
      } else if (i == animatedStep.round()) {
        // 当前步骤颜色
        drawColor = color;
      }
      
      final Paint paint = Paint()
        ..color = drawColor
        ..style = PaintingStyle.fill;
      
      canvas.drawCircle(dotCenter, dotRadius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ArcDotsPainter oldDelegate) {
    return oldDelegate.animatedStep != animatedStep || oldDelegate.loginSkipped != loginSkipped;
  }
}
