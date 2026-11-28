import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/l10n.dart';
import '../../core/tenant.dart';
import 'data/admin_tools_repo.dart';

/// Admin home: top courses by enrollments (bars) + recent activity.
/// Never blocks the dashboard: any failure just hides a section.
class AdminInsights extends StatefulWidget {
  const AdminInsights({super.key});

  @override
  State<AdminInsights> createState() => _AdminInsightsState();
}

class _AdminInsightsState extends State<AdminInsights> {
  List<(String, int)> _top = [];
  List<Map<String, dynamic>> _recent = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await Supabase.instance.client
          .from('enrollments')
          .select('course_id, courses(title)')
          .eq('tenant_id', TenantContext.id)
          .limit(1000)
          .timeout(const Duration(seconds: 15));
      final counts = <String, (String, int)>{};
      for (final r in rows) {
        final id = r['course_id']?.toString() ?? '';
        final title = (r['courses'] is Map
                ? (r['courses'] as Map)['title']
                : null)
            ?.toString();
        if (id.isEmpty || title == null) continue;
        counts[id] = (title, (counts[id]?.$2 ?? 0) + 1);
      }
      final list = counts.values.toList()
        ..sort((a, b) => b.$2.compareTo(a.$2));
      _top = list.take(5).toList();
    } catch (_) {}
    try {
      _recent = (await AdminToolsRepository.fetchAudit(limit: 5)
              .timeout(const Duration(seconds: 15)))
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {}
    if (mounted) setState(() => _loaded = true);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    if (!_loaded || (_top.isEmpty && _recent.isEmpty)) {
      return const SizedBox.shrink();
    }
    final maxV = _top.isEmpty ? 1 : _top.first.$2;
    final navy = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_top.isNotEmpty) ...[
            Text(s.t('ins_top_courses'),
                style: TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w800, color: navy)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(18),
                boxShadow: const [
                  BoxShadow(
                      color: Color(0x14E8805A),
                      blurRadius: 14,
                      offset: Offset(0, 8)),
                ],
              ),
              child: Column(children: [
                for (final t in _top)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(children: [
                      Expanded(
                        flex: 4,
                        child: Text(t.$1,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12.5)),
                      ),
                      Expanded(
                        flex: 5,
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: t.$2 / maxV),
                          duration: const Duration(milliseconds: 700),
                          builder: (_, v, __) => ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: v,
                              minHeight: 10,
                              backgroundColor: const Color(0xFFE8F0FF),
                              color: const Color(0xFFE8805A),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 34,
                        child: Text('${t.$2}',
                            textAlign: TextAlign.end,
                            style: TextStyle(
                                fontWeight: FontWeight.w800, color: navy)),
                      ),
                    ]),
                  ),
              ]),
            ),
            const SizedBox(height: 18),
          ],
          if (_recent.isNotEmpty) ...[
            Text(s.t('ins_recent'),
                style: TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w800, color: navy)),
            const SizedBox(height: 10),
            for (final r in _recent)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE3EAF7)),
                ),
                child: Row(children: [
                  const Icon(Icons.history, size: 18, color: Color(0xFF6B7A99)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${(r['profiles'] is Map ? ((r['profiles'] as Map)['full_name'] ?? (r['profiles'] as Map)['email']) : '') ?? ''} · ${r['action'] ?? ''}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ]),
              ),
          ],
        ],
      ),
    );
  }
}
