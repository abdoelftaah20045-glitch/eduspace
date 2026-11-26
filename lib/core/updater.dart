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
          .get(Uri.parse('$_base/version.json'))
          .timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) return;
      final m = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      final latest = (m['build'] as num?)?.toInt() ?? 0;
      if (latest <= kAppBuild) return;
      final ctx = rootNavigatorKey.currentState?.overlay?.context;
      if (ctx == null || !ctx.mounted) return;
      _shown = true;
      await showDialog<void>(
        context: ctx,
        barrierDismissible: false,
        builder: (_) => _UpdateDialog(
          build: latest,
          version: '${m['version'] ?? ''}',
          notes: '${m['notes'] ?? ''}',
          apkUrl: '$_base/${m['apk'] ?? 'deki.apk'}',
        ),
      );
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
      required this.apkUrl});
  final int build;
  final String version;
  final String notes;
  final String apkUrl;

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
      if (mounted) setState(() => _progress = 1);
      final result = await OpenFilex.open(file.path,
          type: 'application/vnd.android.package-archive');
      if (result.type != ResultType.done && mounted) {
        setState(() {
          _busy = false;
          _error = result.message;
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
