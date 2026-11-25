import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/l10n.dart';
import '../../core/tenant.dart';
import '../exams/data/exams_repo.dart';
import '../lives/data/lives_repo.dart';
import '../lives/lives_screen.dart';

class _Entry {
  _Entry(this.kind, this.title, this.at, {this.live});
  final String kind; // live | exam | assignment
  final String title;
  final DateTime at;
  final LiveSession? live;
}

/// Student: one timeline of live sessions, exam deadlines and assignment
/// due dates, grouped by day (screen 10).
class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  List<_Entry>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final out = <_Entry>[];
    try {
      for (final l in await LivesRepository.fetchUpcoming(limit: 50)) {
        out.add(_Entry('live', l.title, l.startsAt, live: l));
      }
    } catch (_) {}
    try {
      for (final e in await ExamsRepository.fetchExams()) {
        final at = e.availableUntil ?? e.availableFrom;
        if (at != null && at.isAfter(DateTime.now().subtract(const Duration(days: 1)))) {
          out.add(_Entry('exam', e.title, at));
        }
      }
    } catch (_) {}
    try {
      final rows = await Supabase.instance.client
          .from('assignments')
          .select('title, due_at')
          .eq('tenant_id', TenantContext.id)
          .not('due_at', 'is', null)
          .gte('due_at',
              DateTime.now().subtract(const Duration(days: 1)).toUtc().toIso8601String())
          .order('due_at')
          .limit(50);
      for (final r in rows) {
        final d = DateTime.tryParse((r['due_at'] ?? '').toString())?.toLocal();
        if (d != null) out.add(_Entry('assignment', (r['title'] as String?) ?? '', d));
      }
    } catch (_) {}
    out.sort((a, b) => a.at.compareTo(b.at));
    if (mounted) setState(() => _items = out);
  }

  IconData _icon(String k) => switch (k) {
        'live' => Icons.videocam_outlined,
        'exam' => Icons.quiz_outlined,
        _ => Icons.assignment_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final items = _items;
    final dayFmt = DateFormat('EEEE d MMMM', s.locale.languageCode);
    final timeFmt = DateFormat('h:mm a', s.locale.languageCode);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('sch_title'))),
      body: items == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: items.isEmpty
                  ? ListView(children: [
                      const SizedBox(height: 120),
                      Center(child: Text(s.t('sch_empty'))),
                    ])
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: items.length,
                      itemBuilder: (context, i) {
                        final e = items[i];
                        final newDay = i == 0 ||
                            dayFmt.format(items[i - 1].at) != dayFmt.format(e.at);
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (newDay)
                              Padding(
                                padding: const EdgeInsets.only(top: 12, bottom: 6),
                                child: Text(dayFmt.format(e.at),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(fontWeight: FontWeight.bold)),
                              ),
                            Card(
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: Theme.of(context)
                                      .colorScheme
                                      .primaryContainer,
                                  child: Icon(_icon(e.kind)),
                                ),
                                title: Text(e.title,
                                    maxLines: 1, overflow: TextOverflow.ellipsis),
                                subtitle: Text(
                                    '${s.t('sch_${e.kind}')} · ${timeFmt.format(e.at)}'),
                                onTap: e.live == null
                                    ? null
                                    : () => Navigator.of(context).push(
                                        MaterialPageRoute(
                                            builder: (_) => LiveDetailScreen(
                                                session: e.live!))),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
            ),
    );
  }
}
