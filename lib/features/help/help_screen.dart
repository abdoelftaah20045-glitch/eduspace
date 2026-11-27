import '../../core/maintenance.dart';
import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../core/remote_ui.dart';
import '../support/support_screen.dart';

/// Help center: searchable FAQ plus a shortcut to support.
class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key});

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) =>
      MaintenanceGate(pageKey: 'help', child: Builder(builder: _mtBuild));

  Widget _mtBuild(BuildContext context) {
    final s = S.of(context);
    final lang = s.locale.languageCode;
    String pick(dynamic m) {
      if (m is! Map) return '';
      for (final l in [lang, 'ar', 'en']) {
        final v = m[l]?.toString() ?? '';
        if (v.trim().isNotEmpty) return v;
      }
      return '';
    }

    final all = RemoteUi.faq.isNotEmpty
        ? [for (final e in RemoteUi.faq) (pick(e['q']), pick(e['a']))]
        : [for (var i = 1; i <= 8; i++) (s.t('faq_q$i'), s.t('faq_a$i'))];
    final items = all.where((e) {
      final q = _q.trim().toLowerCase();
      return q.isEmpty ||
          e.$1.toLowerCase().contains(q) ||
          e.$2.toLowerCase().contains(q);
    }).toList();
    return Scaffold(
      appBar: AppBar(title: Text(s.t('help_title'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            onChanged: (v) => setState(() => _q = v),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: s.t('help_search'),
            ),
          ),
          const SizedBox(height: 14),
          for (final e in items)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                boxShadow: const [
                  BoxShadow(
                      color: Color(0x14E8805A),
                      blurRadius: 12,
                      offset: Offset(0, 6)),
                ],
              ),
              child: Theme(
                data: Theme.of(context)
                    .copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  title: Text(e.$1,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  childrenPadding:
                      const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  children: [Text(e.$2)],
                ),
              ),
            ),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(child: Text(s.t('help_none'))),
            ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SupportScreen())),
            icon: const Icon(Icons.support_agent),
            label: Text(s.t('help_contact')),
          ),
        ],
      ),
    );
  }
}
