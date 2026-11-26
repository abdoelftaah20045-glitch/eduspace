import 'package:flutter/material.dart';

/// Friendly drawn empty state (concentric circles, icon, small sparkles).
class EmptyIllustration extends StatelessWidget {
  const EmptyIllustration({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme.primary;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 170,
          height: 170,
          child: Stack(alignment: Alignment.center, children: [
            Container(
                width: 170,
                height: 170,
                decoration: BoxDecoration(
                    shape: BoxShape.circle, color: c.withValues(alpha: .06))),
            Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                    shape: BoxShape.circle, color: c.withValues(alpha: .12))),
            Container(
                width: 74,
                height: 74,
                decoration: BoxDecoration(shape: BoxShape.circle, color: c),
                child: Icon(icon, color: Colors.white, size: 38)),
            PositionedDirectional(
                top: 14,
                end: 22,
                child: Icon(Icons.auto_awesome,
                    color: const Color(0xFFF29900).withValues(alpha: .9), size: 20)),
            PositionedDirectional(
                bottom: 22,
                start: 16,
                child: Icon(Icons.circle,
                    color: const Color(0xFFE53935).withValues(alpha: .5), size: 10)),
            PositionedDirectional(
                top: 40,
                start: 10,
                child: Icon(Icons.circle,
                    color: const Color(0xFF2E9E5B).withValues(alpha: .5), size: 8)),
          ]),
        ),
        const SizedBox(height: 16),
        Text(text,
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).hintColor, fontSize: 15)),
      ],
    );
  }
}
