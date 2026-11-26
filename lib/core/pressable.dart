import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Raised card with layered soft shadows that presses down (scale + shadow
/// shrink) on touch. Use for tiles, course cards and buttons.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.color = Colors.white,
    this.radius = 18,
    this.padding,
    this.shadowColor = const Color(0xFF2563EB),
    this.haptic = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final Color color;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final Color shadowColor;
  final bool haptic;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (mounted && _down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(widget.radius);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapCancel: () => _set(false),
      onTapUp: (_) => _set(false),
      onTap: widget.onTap == null
          ? null
          : () {
              if (widget.haptic) HapticFeedback.selectionClick();
              widget.onTap!();
            },
      child: AnimatedScale(
        scale: _down ? .96 : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          decoration: BoxDecoration(
            color: widget.color,
            borderRadius: r,
            boxShadow: _down
                ? [
                    BoxShadow(
                        color: widget.shadowColor.withValues(alpha: .10),
                        blurRadius: 4,
                        offset: const Offset(0, 1)),
                  ]
                : [
                    BoxShadow(
                        color: widget.shadowColor.withValues(alpha: .08),
                        blurRadius: 4,
                        offset: const Offset(0, 2)),
                    BoxShadow(
                        color: widget.shadowColor.withValues(alpha: .10),
                        blurRadius: 14,
                        offset: const Offset(0, 8)),
                    BoxShadow(
                        color: widget.shadowColor.withValues(alpha: .06),
                        blurRadius: 30,
                        offset: const Offset(0, 16)),
                  ],
          ),
          child: ClipRRect(
            borderRadius: r,
            child: Padding(
              padding: widget.padding ?? EdgeInsets.zero,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Wraps any tappable (Card + InkWell) with a press-down scale, without
/// touching its own tap handling.
class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.child});

  final Widget child;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => setState(() => _down = true),
      onPointerUp: (_) => setState(() => _down = false),
      onPointerCancel: (_) => setState(() => _down = false),
      child: AnimatedScale(
        scale: _down ? .97 : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
