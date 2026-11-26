import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/recovery.dart';
import 'ai_assistant_screen.dart';

/// Wraps the whole app: a draggable glowing assistant button on every page
/// once the user is signed in. Tap opens the chat sheet.
class AiOverlay extends StatefulWidget {
  const AiOverlay({super.key, required this.child});

  final Widget child;

  @override
  State<AiOverlay> createState() => _AiOverlayState();
}

class _AiOverlayState extends State<AiOverlay>
    with SingleTickerProviderStateMixin {
  StreamSubscription<AuthState>? _sub;
  bool _signedIn = false;
  bool _open = false;
  Offset? _pos; // from top-left
  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1800))
    ..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    try {
      _signedIn = Supabase.instance.client.auth.currentSession != null;
      _sub = Supabase.instance.client.auth.onAuthStateChange.listen((e) {
        final v = e.session != null;
        if (mounted && v != _signedIn) setState(() => _signedIn = v);
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _sub?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _openChat() async {
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null || _open) return;
    _open = true;
    setState(() {});
    await showModalBottomSheet<void>(
      context: ctx,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const AiChatSheet(),
    );
    _open = false;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    const d = 56.0;
    final pos = _pos ?? Offset(size.width - d - 16, size.height - d - 110);
    final clamped = Offset(
      pos.dx.clamp(8.0, size.width - d - 8),
      pos.dy.clamp(MediaQuery.of(context).padding.top + 8, size.height - d - 8),
    );
    return Stack(
      children: [
        widget.child,
        if (!_open)
          Positioned(
            left: clamped.dx,
            top: clamped.dy,
            child: GestureDetector(
              onPanUpdate: (u) => setState(() => _pos = clamped + u.delta),
              onTap: _openChat,
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (_, child) => Container(
                  width: d,
                  height: d,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF2563EB), Color(0xFF7C3AED)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF7C3AED)
                            .withValues(alpha: .25 + .25 * _pulse.value),
                        blurRadius: 14 + 12 * _pulse.value,
                        spreadRadius: 1 + 3 * _pulse.value,
                      ),
                      const BoxShadow(
                          color: Color(0x332563EB),
                          blurRadius: 10,
                          offset: Offset(0, 6)),
                    ],
                  ),
                  child: child,
                ),
                child: const Icon(Icons.auto_awesome,
                    color: Colors.white, size: 28),
              ),
            ),
          ),
      ],
    );
  }
}
