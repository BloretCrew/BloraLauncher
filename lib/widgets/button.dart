import 'package:flutter/material.dart';

class BloretButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final IconData? icon;
  final double? height;

  const BloretButton({super.key, required this.text, required this.onPressed, this.icon, this.height});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = ElevatedButton.styleFrom(
      padding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
      minimumSize: Size(0, height ?? 36),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8), 
        side: BorderSide(color: Colors.white.withValues(alpha: 0.1))
      ),
      backgroundColor: theme.colorScheme.outline.withValues(alpha: 0.1),
      foregroundColor: theme.colorScheme.onSurface,
      elevation: 0,
      textStyle: theme.textTheme.bodyMedium?.copyWith(
        fontWeight: FontWeight.bold,
      ),
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

  const BloretIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: theme.colorScheme.outline.withValues(alpha: 0.1),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Icon(icon, size: 20, color: theme.colorScheme.onSurface),
        ),
      ),
    );
  }
}
