import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/l10n.dart';
import '../../core/tenant.dart';
import 'import_job.dart';

/// One place to see every running import with live progress and a Stop button.
class ImportsScreen extends StatefulWidget {
  const ImportsScreen({super.key});

  @override
  State<ImportsScreen> createState() => _ImportsScreenState();
}

class _ImportsScreenState extends State<ImportsScreen> {
  SupabaseClient get _c => Supabase.instance.client;
  Map<String, dynamic>? _books;
  bool _booksMissing = false;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    ImportJob.instance.restore();
    _poll();
    _t = Timer.periodic(const Duration(seconds: 5), (_) => _poll());
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    try {
      final r = await _c.rpc('book_import_progress', params: {'t': TenantContext.id});
      if (!mounted) return;
      setState(() {
        _books = r is Map ? Map<String, dynamic>.from(r) : null;
        _booksMissing = r == null;
      });
    } catch (_) {
      if (mounted) setState(() => _booksMissing = true);
    }
  }

  Future<void> _bookAction(String fn) async {
    try {
      await _c.rpc(fn, params: {'t': TenantContext.id});
    } catch (_) {}
    _poll();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final scheme = Theme.of(context).colorScheme;
    final job = ImportJob.instance;
    return Scaffold(
      appBar: AppBar(title: Text(s.t('imports_title'))),
      body: AnimatedBuilder(
        animation: job,
        builder: (context, _) {
          final total = job.rows.length;
          final done = job.done;
          final srcs = (_books?['sources'] as List?) ?? const [];
          final running = [
            for (final x in srcs)
              if (x is Map && x['enabled'] == true) Map<String, dynamic>.from(x),
          ];
          return ListView(padding: const EdgeInsets.all(16), children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('استيراد الكورسات والملفات',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  const SizedBox(height: 8),
                  if (total == 0)
                    const Text('مفيش استيراد شغال دلوقتي')
                  else ...[
                    LinearProgressIndicator(value: total == 0 ? 0 : done / total),
                    const SizedBox(height: 6),
                    Text('$done / $total  ${job.running ? '(شغال)' : (job.hasPending ? '(واقف)' : '(خلص)')}'),
                    if (job.progress.isNotEmpty)
                      Text(job.progress, maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 8),
                    Row(children: [
                      if (job.running)
                        FilledButton(onPressed: job.stop, child: Text(s.t('bg_stop')))
                      else if (job.hasPending)
                        FilledButton(
                            onPressed: () => job.start(s),
                            child: Text(s.t('yt_import_btn'))),
                    ]),
                  ],
                ]),
              ),
            ),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('استيراد الكتب (على السيرفر، شغال والتطبيق مقفول)',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  const SizedBox(height: 8),
                  if (_booksMissing)
                    const Text('شغّل ملف SQL part42 وانشر دالة book-import الأول.')
                  else if (_books == null)
                    const LinearProgressIndicator()
                  else ...[
                    Text('كتب في المكتبة: ${_books!['books']}   تحت المراجعة: ${_books!['review']}'),
                    const SizedBox(height: 8),
                    Row(children: [
                      FilledButton(
                          onPressed: () => _bookAction('book_import_start'),
                          child: const Text('استيراد كل المصادر')),
                      const SizedBox(width: 8),
                      OutlinedButton(
                          onPressed: () => _bookAction('book_import_pause'),
                          child: Text(s.t('bg_stop'))),
                    ]),
                    const SizedBox(height: 8),
                    for (final x in srcs)
                      if (x is Map)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text('${x['label']}',
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                              '${x['status']}  ·  ${x['imported']}${x['error'] != null ? '  ·  ${x['error']}' : ''}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
                          trailing: Icon(
                              x['enabled'] == true ? Icons.sync : Icons.check_circle_outline,
                              color: x['enabled'] == true ? scheme.primary : Colors.grey),
                        ),
                    if (running.isEmpty) const SizedBox.shrink(),
                  ],
                ]),
              ),
            ),
          ]);
        },
      ),
    );
  }
}
