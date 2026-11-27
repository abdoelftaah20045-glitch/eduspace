import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';

import '../features/ai/ai_fab.dart' show aiFabHidden;
import 'recovery.dart';

/// Downloads a Shorebird code update silently in the background (on launch and
/// when the app returns to the foreground), then shows a small non-blocking
/// banner. It never closes or restarts the app by itself and never shows over
/// a lesson, exam or the splash (aiFabHidden > 0 there). The update applies
/// the next time the app is opened.
class CodePush with WidgetsBindingObserver {
  CodePush._();
  static final CodePush instance = CodePush._();

  final ShorebirdUpdater _updater = ShorebirdUpdater();
  bool _busy = false;
  bool _ready = false;
  OverlayEntry? _entry;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  void start() {
    if (!Platform.isAndroid) return;
    WidgetsBinding.instance.addObserver(this);
    aiFabHidden.addListener(_refresh);
    Future<void>.delayed(const Duration(seconds: 3), check);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        DateTime.now().difference(_last).inMinutes >= 10) {
      check();
    }
  }

  Future<void> check() async {
    if (_busy || _ready) return;
    _busy = true;
    _last = DateTime.now();
    try {
      if (!_updater.isAvailable) return;
      var status = await _updater.checkForUpdate();
      if (status == UpdateStatus.outdated) {
        await _updater.update();
        status = UpdateStatus.restartRequired;
      }
      if (status == UpdateStatus.restartRequired) {
        _ready = true;
        _refresh();
      }
    } catch (_) {
      // Offline or updater unavailable: stay silent, try again later.
    } finally {
      _busy = false;
    }
  }

  void _dismiss() {
    _entry?.remove();
    _entry = null;
    aiFabHidden.removeListener(_refresh);
  }

  void _refresh() {
    if (!_ready) return;
    final overlay = rootNavigatorKey.currentState?.overlay;
    if (overlay == null) return;
    if (aiFabHidden.value > 0) {
      _entry?.remove();
      _entry = null;
      return;
    }
    if (_entry != null) return;
    _entry = OverlayEntry(builder: (ctx) {
      final ar = Localizations.localeOf(ctx).languageCode == 'ar';
      return Positioned(
        left: 12,
        right: 12,
        bottom: 84,
        child: Material(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(14),
          elevation: 6,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
            child: Row(children: [
              Expanded(
                child: Text(
                  ar
                      ? 'تحديث جاهز، هيشتغل أول ما تفتح التطبيق تاني.'
                      : 'Update ready. It applies the next time you open the app.',
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
              TextButton(
                onPressed: _dismiss,
                child: Text(ar ? 'تمام' : 'OK'),
              ),
            ]),
          ),
        ),
      );
    });
    overlay.insert(_entry!);
  }
}
