import 'package:flutter/material.dart';

import 'l10n.dart';

/// Logo + name lockup (Arabic version when the app language is Arabic).
class AppLockup extends StatelessWidget {
  const AppLockup({super.key, this.width = 240});

  final double width;

  @override
  Widget build(BuildContext context) {
    final ar = S.of(context).locale.languageCode == 'ar';
    return Image.asset(
      ar ? 'assets/brand/lockup_ar_1600x480.png' : 'assets/brand/lockup_en_1600x480.png',
      width: width,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Text(S.of(context).t('app_name'),
          style: Theme.of(context).textTheme.headlineMedium),
    );
  }
}
