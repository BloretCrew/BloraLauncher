import 'package:flutter/material.dart';

class BloretButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final IconData? icon;
  final double? height;
  final Color? color;

  const BloretButton({
    super.key,
    required this.text,
    this.onPressed,
    this.icon,
    this.height,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool isDisabled = onPressed == null;
    final style = ButtonStyle(
      padding: WidgetStateProperty.all(
        const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
      ),
      minimumSize: WidgetStateProperty.all(Size(0, height ?? 42)),
      shape: WidgetStateProperty.all(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
      ),
      side: WidgetStateProperty.all(
        BorderSide(
          color: Colors.white.withValues(alpha: isDisabled ? 0.02 : 0.1),
        ),
      ),
      backgroundColor: WidgetStateProperty.all(
        isDisabled
            ? Colors.white.withValues(alpha: 0.04)
            : theme.colorScheme.outline.withValues(alpha: 0.1),
      ),
      foregroundColor: WidgetStateProperty.all(
        isDisabled
            ? Colors.white.withValues(alpha: 0.3)
            : (color ?? theme.colorScheme.onSurface),
      ),
      elevation: WidgetStateProperty.all(0),
      textStyle: WidgetStateProperty.all(
        theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
      ),
      overlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.hovered)) {
          return theme.colorScheme.primary.withValues(alpha: 0.12);
        }

        if (states.contains(WidgetState.pressed)) {
          return theme.colorScheme.primary.withValues(alpha: 0.18);
        }

        return null;
      }),
    );

    if (icon != null) {
      return ElevatedButton.icon(
        onPressed: onPressed,
        style: style,
        icon: Icon(icon, size: 18),
        label: Text(text),
      );
    }

    return ElevatedButton(
      onPressed: onPressed,
      style: style,
      child: Text(text),
    );
  }
}

class BloretIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;

  const BloretIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          hoverColor: theme.colorScheme.primary.withValues(alpha: 0.12),
          child: Ink(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: theme.colorScheme.outline.withValues(alpha: 0.1),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Icon(icon, size: 20, color: color ?? theme.colorScheme.onSurface),
          ),
        ),
      ),
    );
  }
}
