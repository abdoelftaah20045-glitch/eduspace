import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import 'data/course_models.dart';

/// Price with an automatic discount: old price struck through, a percent
/// badge and the new price. Falls back to the plain price without discount.
class PriceView extends StatelessWidget {
  const PriceView({super.key, required this.course, this.size = 14, this.color});

  final Course course;
  final double size;
  final Color? color;

  static String _n(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final col = color ?? Theme.of(context).colorScheme.primary;
    final cur = course.currency;
    if (!course.hasDiscount) {
      return Text('${_n(course.price)} $cur',
          style: TextStyle(
              fontWeight: FontWeight.w800, fontSize: size, color: col));
    }
    final pct = course.discountPercent!;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      children: [
        Text('${_n(course.effectivePrice)} $cur',
            style: TextStyle(
                fontWeight: FontWeight.w800, fontSize: size, color: col)),
        Text('${_n(course.price)} $cur',
            style: TextStyle(
                fontSize: size - 3,
                color: Colors.grey,
                decoration: TextDecoration.lineThrough)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
              color: const Color(0xFFE53935),
              borderRadius: BorderRadius.circular(8)),
          child: Text('${_n(pct)}% ${s.t('discount_off')}',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: size - 3,
                  fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}
