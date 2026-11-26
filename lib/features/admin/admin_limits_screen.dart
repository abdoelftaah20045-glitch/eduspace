import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../core/remote_ui.dart';
import 'data/admin_tools_repo.dart';

/// Admin: every number the app uses for levels and badges.
class AdminLimitsScreen extends StatefulWidget {
  const AdminLimitsScreen({super.key});

  @override
  State<AdminLimitsScreen> createState() => _AdminLimitsScreenState();
}

class _AdminLimitsScreenState extends State<AdminLimitsScreen> {
  // key, label key, default
  static const _defs = [
    ('lesson_watch_percent', 'lim_lesson_watch', 90),
    ('lvl_excellent', 'lim_lvl_excellent', 80),
    ('lvl_good', 'lim_lvl_good', 60),
    ('lvl_average', 'lim_lvl_average', 40),
    ('lb_bronze', 'lim_lb_bronze', 100),
    ('lb_silver', 'lim_lb_silver', 300),
    ('lb_gold', 'lim_lb_gold', 700),
    ('lb_trophy', 'lim_lb_trophy', 1500),
  ];
  final Map<String, TextEditingController> _c = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    for (final d in _defs) {
      _c[d.$1] = TextEditingController(text: '${RemoteUi.limit(d.$1, d.$3)}');
    }
    RemoteUi.load().then((_) {
      if (!mounted) return;
      for (final d in _defs) {
        _c[d.$1]!.text = '${RemoteUi.limit(d.$1, d.$3)}';
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final s = S.of(context);
    setState(() => _saving = true);
    try {
      final m = <String, num>{};
      for (final d in _defs) {
        final v = num.tryParse(_c[d.$1]!.text.trim());
        if (v != null) m[d.$1] = v;
      }
      RemoteUi.limits = m;
      RemoteUi.version.value++;
      await AdminToolsRepository.saveSetting('ui_limits', m);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(s.t('saved'))));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(s.t('generic_error'))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('ui_limits'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final d in _defs)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextField(
                controller: _c[d.$1],
                keyboardType: TextInputType.number,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(labelText: s.t(d.$2)),
              ),
            ),
          const SizedBox(height: 8),
          FilledButton(
              onPressed: _saving ? null : _save, child: Text(s.t('save'))),
        ],
      ),
    );
  }
}
