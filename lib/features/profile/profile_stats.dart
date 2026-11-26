import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/l10n.dart';

/// Learning stats and achievement badges (reference: profile with stats and
/// achievements). Badges unlock from real counts.
class ProfileStats extends StatefulWidget {
  const ProfileStats({super.key});

  @override
  State<ProfileStats> createState() => _ProfileStatsState();
}

class _ProfileStatsState extends State<ProfileStats> {
  int _courses = 0, _lessons = 0, _certs = 0;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = Supabase.instance.client;
    final uid = c.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final e = await c.from('enrollments').select('id').eq('user_id', uid).eq('status', 'active');
      final l = await c.from('lesson_progress').select('lesson_id').eq('user_id', uid).eq('completed', true);
      final k = await c.from('certificates').select('id').eq('user_id', uid).eq('status', 'valid');
      _courses = e.length;
      _lessons = l.length;
      _certs = k.length;
    } catch (_) {}
    if (mounted) setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const SizedBox.shrink();
    final s = S.of(context);
    final theme = Theme.of(context);
    Widget stat(IconData i, Color col, int v, String label) => Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: col.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(children: [
              Icon(i, color: col),
              const SizedBox(height: 6),
              Text('$v',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold)),
              Text(label,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall),
            ]),
          ),
        );
    final badges = <(IconData, String, bool)>[
      (Icons.flag_outlined, 'ach_first_lesson', _lessons >= 1),
      (Icons.local_fire_department_outlined, 'ach_ten_lessons', _lessons >= 10),
      (Icons.workspace_premium_outlined, 'ach_first_cert', _certs >= 1),
      (Icons.school_outlined, 'ach_three_courses', _courses >= 3),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          stat(Icons.menu_book_outlined, const Color(0xFF2563EB), _courses, s.t('stat_courses')),
          stat(Icons.check_circle_outline, const Color(0xFF2E9E5B), _lessons, s.t('stat_lessons')),
          stat(Icons.workspace_premium_outlined, const Color(0xFFF29900), _certs, s.t('pref_certificates')),
        ]),
        const SizedBox(height: 16),
        Text(s.t('achievements'), style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final b in badges)
            Chip(
              avatar: Icon(b.$1,
                  size: 18,
                  color: b.$3 ? const Color(0xFFF29900) : Colors.grey),
              label: Text(s.t(b.$2)),
              backgroundColor: b.$3
                  ? const Color(0xFFF29900).withValues(alpha: .12)
                  : null,
            ),
        ]),
      ],
    );
  }
}
