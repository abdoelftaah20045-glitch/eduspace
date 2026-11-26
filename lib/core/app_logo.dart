import 'package:flutter/material.dart';

/// The app logo. Reads assets/logo.png (replace that file with the real
/// logo and rebuild); falls back to an icon if the asset is missing.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 88, this.radius});

  final double size;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius ?? size * .28),
      child: Image.asset(
        'assets/logo.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: size,
          height: size,
          color: scheme.primary,
          child: Icon(Icons.school_rounded,
              size: size * .5, color: scheme.onPrimary),
        ),
      ),
    );
  }
}
