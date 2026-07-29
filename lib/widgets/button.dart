import 'package:flutter/material.dart';

class BloretButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;

  const BloretButton({super.key, required this.text, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Colors.white.withOpacity(0.1))),
        backgroundColor: Theme.of(context).colorScheme.outline.withOpacity(0.1),
        textStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold, color: onPressed != null ? Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black : Colors.grey),
      ),
      child: Text(text),
    );
  }
}