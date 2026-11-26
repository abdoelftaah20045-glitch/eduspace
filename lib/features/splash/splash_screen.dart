import 'package:flutter/material.dart';

import '../ai/ai_fab.dart';

import '../../core/app_lockup.dart';
import '../../core/l10n.dart';
import '../auth/auth_gate.dart';

/// Animated splash: logo scales and fades in over a brand gradient,
/// tagline slides up, then routes to the auth gate.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => aiFabHidden.value++);
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..forward();
    Future.delayed(const Duration(milliseconds: 3200), _goNext);
  }

  void _goNext() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const AuthGate(),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.addPostFrameCallback((_) => aiFabHidden.value--);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final slogan = s.t('splash_tagline');
    final h = MediaQuery.of(context).size.height;
    // Logo: falls from above and lands with a bounce and a small squash.
    final drop = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.42, curve: Curves.bounceOut),
    );
    final squash = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween(0.0), weight: 22),
      TweenSequenceItem(
          tween: Tween(begin: 0.0, end: 1.0)
              .chain(CurveTween(curve: Curves.easeOut)),
          weight: 4),
      TweenSequenceItem(
          tween: Tween(begin: 1.0, end: 0.0)
              .chain(CurveTween(curve: Curves.easeOutBack)),
          weight: 10),
      TweenSequenceItem(tween: ConstantTween(0.0), weight: 64),
    ]).animate(_controller);
    // Slogan: written live, letter by letter.
    final write = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.5, 0.95, curve: Curves.easeInOut),
    );
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [Color(0xFFEFF6FF), Color(0xFFDBEAFE)],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedBuilder(
                animation: _controller,
                builder: (_, child) {
                  final y = (1 - drop.value) * -(h * 0.6);
                  final q = squash.value;
                  return Transform.translate(
                    offset: Offset(0, y),
                    child: Transform(
                      alignment: Alignment.bottomCenter,
                      transform: Matrix4.diagonal3Values(
                          1 + 0.10 * q, 1 - 0.14 * q, 1),
                      child: child,
                    ),
                  );
                },
                child: const AppLockup(width: 280),
              ),
              const SizedBox(height: 28),
              AnimatedBuilder(
                animation: write,
                builder: (_, __) {
                  final n = (slogan.characters.length * write.value).ceil();
                  final shown = slogan.characters.take(n).toString();
                  return SizedBox(
                    height: 36,
                    child: Text(
                      shown,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFFD96A43),
                        fontFamily: 'Marhey',
                        fontSize: 22,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
