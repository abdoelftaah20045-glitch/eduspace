import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';

import 'recovery.dart';

/// Checks for a Shorebird code update on launch and when the app comes back
/// to the foreground, downloads it with a visible message, then asks the user
/// to close the app so the next open runs the new code.
class CodePush with WidgetsBindingObserver {
  CodePush._();
  static final CodePush instance = CodePush._();

  final ShorebirdUpdater _updater = ShorebirdUpdater();
  bool _busy = false;
  bool _readyShown = false;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  void start() {
    if (!Platform.isAndroid) return;
    WidgetsBinding.instance.addObserver(this);
    Future<void>.delayed(const Duration(seconds: 3), check);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (DateTime.now().difference(_last).inMinutes >= 10) check();
    }
  }

  Future<void> check() async {
    if (_busy || _readyShown) return;
    _busy = true;
    _last = DateTime.now();
    try {
      if (!_updater.isAvailable) return;
      final status = await _updater.checkForUpdate();
      if (status == UpdateStatus.restartRequired) {
        _showReady();
      } else if (status == UpdateStatus.outdated) {
        final state = ValueNotifier<int>(0);
        _show(state);
        try {
          await _updater.update();
          state.value = 1;
        } catch (_) {
          state.value = 2;
        }
      }
    } catch (_) {
      // Offline or updater unavailable: stay silent.
    } finally {
      _busy = false;
    }
  }

  void _showReady() {
    _show(ValueNotifier<int>(1));
  }

  void _show(ValueNotifier<int> state) {
    final ctx = rootNavigatorKey.currentState?.overlay?.context;
    if (ctx == null || !ctx.mounted) return;
    if (state.value == 1) _readyShown = true;
    showDialog<void>(
      context: ctx,
      barrierDismissible: false,
      builder: (_) => _CodePushDialog(state: state, onReady: () => _readyShown = true),
    );
  }
}

class _CodePushDialog extends StatelessWidget {
  const _CodePushDialog({required this.state, required this.onReady});
  final ValueNotifier<int> state;
  final VoidCallback onReady;

  @override
  Widget build(BuildContext context) {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    return ValueListenableBuilder<int>(
      valueListenable: state,
      builder: (ctx, v, _) {
        if (v == 1) onReady();
        final title = v == 0
            ? (ar ? 'جاري تحميل التحديث...' : 'Downloading update...')
            : v == 1
                ? (ar ? 'التحديث جاهز' : 'Update ready')
                : (ar ? 'تعذر تحميل التحديث' : 'Update failed');
        final body = v == 0
            ? (ar ? 'ثواني بسيطة، متقفلش التطبيق.' : 'Just a few seconds, keep the app open.')
            : v == 1
                ? (ar
                    ? 'اقفل التطبيق وافتحه تاني عشان يشتغل التحديث الجديد.'
                    : 'Close the app and open it again to use the new update.')
                : (ar ? 'هنحاول تاني في المرة الجاية.' : 'We will try again next time.');
        return AlertDialog(
          title: Text(title),
          content: v == 0
              ? Column(mainAxisSize: MainAxisSize.min, children: [
                  const LinearProgressIndicator(),
                  const SizedBox(height: 12),
                  Text(body),
                ])
              : Text(body),
          actions: [
            if (v == 1)
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(ar ? 'لاحقاً' : 'Later'),
              ),
            if (v == 1)
              FilledButton(
                onPressed: () => SystemNavigator.pop(),
                child: Text(ar ? 'اقفل التطبيق الآن' : 'Close app now'),
              ),
            if (v == 2)
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(ar ? 'تمام' : 'OK'),
              ),
          ],
        );
      },
    );
  }
}
