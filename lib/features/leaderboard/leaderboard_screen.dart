import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/l10n.dart';
import '../../core/remote_ui.dart';
import '../../core/tenant.dart';

class _Row {
  _Row(this.id, this.name, this.avatar, this.points, this.lessons, this.exams);
  final String id;
  final String name;
  final String? avatar;
  final int points;
  final int lessons;
  final int exams;
}

/// Leaderboard + level/badges (gamification). Points: 10 per completed
/// lesson + best percent per exam. Needs SQL part 17.
class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  List<_Row>? _rows;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _rows = null;
      _error = null;
    });
    try {
      final res = await Supabase.instance.client
          .rpc('leaderboard_top',
              params: {'p_tenant': TenantContext.id, 'p_limit': 50})
          .timeout(const Duration(seconds: 20));
      final list = [
        for (final m in res as List)
          _Row(
              m['user_id'] as String,
              (m['full_name'] ?? '').toString(),
              m['avatar_url'] as String?,
              (m['points'] as num?)?.toInt() ?? 0,
              (m['lessons_done'] as num?)?.toInt() ?? 0,
              (m['exams_taken'] as num?)?.toInt() ?? 0)
      ];
      if (mounted) setState(() => _rows = list);
    } catch (e) {
      final msg = e.toString();
      if (mounted) {
        setState(() => _error =
            msg.contains('leaderboard_top') ? 'lb_sql_needed' : 'generic_error');
      }
    }
  }

  static (String, Color) _badge(int pts) {
    if (pts >= RemoteUi.limit('lb_trophy', 1500)) return ('🏆', const Color(0xFFC9A227));
    if (pts >= RemoteUi.limit('lb_gold', 700)) return ('🥇', const Color(0xFFF29900));
    if (pts >= RemoteUi.limit('lb_silver', 300)) return ('🥈', const Color(0xFF607D8B));
    if (pts >= RemoteUi.limit('lb_bronze', 100)) return ('🥉', const Color(0xFF8D6E63));
    return ('🌱', const Color(0xFF2E9E5B));
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final me = Supabase.instance.client.auth.currentUser?.id;
    return Scaffold(
      appBar: AppBar(title: Text(s.t('lb_title'))),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(s.t(_error!), textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _load, child: Text(s.t('retry'))),
                ]),
              ),
            )
          : _rows == null
              ? const Center(child: CircularProgressIndicator())
              : _rows!.isEmpty
                  ? Center(child: Text(s.t('lb_empty')))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _rows!.length,
                        itemBuilder: (_, i) {
                          final r = _rows![i];
                          final (emoji, col) = _badge(r.points);
                          final mine = r.id == me;
                          final level = r.points ~/ 200 + 1;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: mine
                                  ? const Color(0xFFE8F0FF)
                                  : Theme.of(context).colorScheme.surface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                  color: mine
                                      ? const Color(0xFF2563EB)
                                      : Colors.transparent),
                              boxShadow: [
                                BoxShadow(
                                    color: col.withValues(alpha: .12),
                                    blurRadius: 12,
                                    offset: const Offset(0, 6)),
                              ],
                            ),
                            child: Row(children: [
                              SizedBox(
                                width: 34,
                                child: Text(
                                    i < 3 ? ['🥇', '🥈', '🥉'][i] : '${i + 1}',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w800)),
                              ),
                              CircleAvatar(
                                backgroundImage:
                                    (r.avatar != null && r.avatar!.isNotEmpty)
                                        ? NetworkImage(r.avatar!)
                                        : null,
                                child: (r.avatar == null || r.avatar!.isEmpty)
                                    ? const Icon(Icons.person)
                                    : null,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(r.name.isEmpty ? '-' : r.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700)),
                                    Text(
                                        '${s.t('lb_level')} $level · ${r.lessons} ${s.t('lessons')} · ${r.exams} ${s.t('tab_exams')}',
                                        style: const TextStyle(
                                            fontSize: 11.5,
                                            color: Color(0xFF6B7A99))),
                                  ],
                                ),
                              ),
                              Column(children: [
                                Text(emoji, style: const TextStyle(fontSize: 18)),
                                Text('${r.points}',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: col)),
                              ]),
                            ]),
                          );
                        },
                      ),
                    ),
    );
  }
}
