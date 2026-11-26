import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import 'l10n.dart';
import 'recovery.dart';

/// Build number baked in by CI (--dart-define=APP_BUILD=<run number>).
/// 0 for builds made before self-update existed, so they always see the
/// newest build as an update.
const int kAppBuild = int.fromEnvironment('APP_BUILD', defaultValue: 0);

/// In-app self-update (Android). CI publishes version.json plus the arm64
/// APK to a public release; the app compares builds on launch, downloads the
/// APK inside the app and hands it to the system installer.
class Updater {
  Updater._();

  static const _base =
      'https://github.com/abdoelftaah20045-glitch/deki-releases/releases/download/latest';
  static bool _shown = false;

  static Future<void> checkOnLaunch() async {
    if (!Platform.isAndroid || _shown) return;
    try {
      final r = await http
          .get(Uri.parse('$_base/version.json?t=${DateTime.now().millisecondsSinceEpoch}'),
              headers: const {'Cache-Control': 'no-cache'})
          .timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) return;
      final m = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      final latest = (m['build'] as num?)?.toInt() ?? 0;
      if (latest <= kAppBuild) return;
      // Mandatory when version.json says force, or this build is older than
      // min_build. min_build comes from ci/min_build.txt (see the workflow).
      final minBuild = (m['min_build'] as num?)?.toInt() ?? 0;
      final force = m['force'] == true || kAppBuild < minBuild;
      final nav = rootNavigatorKey.currentState;
      final ctx = nav?.overlay?.context;
      if (nav == null || ctx == null || !ctx.mounted) return;
      _shown = true;
      final view = _UpdateDialog(
        build: latest,
        version: '${m['version'] ?? ''}',
        notes: '${m['notes'] ?? ''}',
        apkUrl: '$_base/${m['apk'] ?? 'deki.apk'}?b=$latest',
        force: force,
      );
      if (force) {
        // Full-screen, no back, no skip: stays until the app is updated.
        await nav.push(MaterialPageRoute<void>(
            fullscreenDialog: true, builder: (_) => view));
      } else {
        await showDialog<void>(
            context: ctx, barrierDismissible: false, builder: (_) => view);
        _shown = false;
      }
    } catch (_) {
      // Offline or the release is not reachable: stay silent.
    }
  }
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog(
      {required this.build,
      required this.version,
      required this.notes,
      required this.apkUrl,
      this.force = false});
  final int build;
  final String version;
  final String notes;
  final String apkUrl;
  final bool force;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  double? _progress;
  bool _busy = false;
  String? _error;

  Future<void> _install() async {
    setState(() {
      _busy = true;
      _error = null;
      _progress = 0;
    });
    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(widget.apkUrl));
      final res = await client.send(req).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/deki-update-${widget.build}.apk');
      final sink = file.openWrite();
      final total = res.contentLength ?? 0;
      var got = 0;
      await for (final chunk in res.stream) {
        sink.add(chunk);
        got += chunk.length;
        if (total > 0 && mounted) setState(() => _progress = got / total);
      }
      await sink.close();
      if (total > 0 && got != total) {
        throw Exception('incomplete download ($got/$total)');
      }
      if (mounted) setState(() => _progress = 1);
      final result = await OpenFilex.open(file.path,
          type: 'application/vnd.android.package-archive');
      if (mounted) {
        // The installer is now on screen. If the user cancels it, the button
        // must work again.
        setState(() {
          _busy = false;
          _error = result.type == ResultType.done ? null : result.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    } finally {
      client.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.version.isEmpty
            ? s.t('update_body')
            : '${s.t('update_body')}  (${widget.version})'),
        if (widget.notes.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(widget.notes, style: Theme.of(context).textTheme.bodySmall),
        ],
        if (_busy) ...[
          const SizedBox(height: 16),
          LinearProgressIndicator(value: _progress),
          const SizedBox(height: 6),
          Text(s.t('update_downloading')),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text('${s.t('update_failed')}: $_error',
              style: const TextStyle(color: Colors.red, fontSize: 12)),
        ],
      ],
    );
    if (widget.force) {
      final scheme = Theme.of(context).colorScheme;
      return PopScope(
        canPop: false,
        child: Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: .12),
                        shape: BoxShape.circle),
                    child: Icon(Icons.system_update_rounded,
                        size: 52, color: scheme.primary),
                  ),
                  const SizedBox(height: 22),
                  Text(s.t('update_available'),
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  body,
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _busy ? null : _install,
                      child: Text(s.t('update_now')),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
    }
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(s.t('update_available')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.version.isEmpty
                ? s.t('update_body')
                : '${s.t('update_body')}  (${widget.version})'),
            if (widget.notes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(widget.notes, style: Theme.of(context).textTheme.bodySmall),
            ],
            if (_busy) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 6),
              Text(s.t('update_downloading')),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text('${s.t('update_failed')}: $_error',
                  style: const TextStyle(color: Colors.red, fontSize: 12)),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: Text(s.t('update_later')),
          ),
          FilledButton(
            onPressed: _busy ? null : _install,
            child: Text(s.t('update_now')),
          ),
        ],
      ),
    );
  }
}
