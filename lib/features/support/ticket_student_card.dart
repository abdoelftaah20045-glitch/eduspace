import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/l10n.dart';
import '../../core/tenant.dart';
import '../admin/admin_student_detail_screen.dart';

const _labels = <String, (String, String)>{
  'full_name': ('الاسم', 'Name'),
  'email': ('الإيميل', 'Email'),
  'phone': ('الموبايل', 'Phone'),
  'birth_date': ('تاريخ الميلاد', 'Birth date'),
  'country': ('الدولة', 'Country'),
  'governorate': ('المحافظة', 'Governorate'),
  'institution': ('المؤسسة', 'Institution'),
  'faculty': ('الكلية', 'Faculty'),
  'specialization': ('التخصص', 'Specialization'),
  'stage': ('المرحلة', 'Stage'),
  'level': ('المستوى', 'Level'),
  'group_name': ('المجموعة', 'Group'),
  'bio': ('نبذة', 'Bio'),
  'status': ('الحالة', 'Status'),
  'status_reason': ('سبب الحالة', 'Status reason'),
  'locale': ('اللغة', 'Language'),
  'created_at': ('تاريخ التسجيل', 'Joined'),
};

/// Admin-only: full profile of the person who opened a support ticket, with
/// their roles and enrolled courses, so the admin can help them.
class TicketStudentCard extends StatefulWidget {
  const TicketStudentCard({super.key, required this.userId});

  final String userId;

  @override
  State<TicketStudentCard> createState() => _TicketStudentCardState();
}

class _TicketStudentCardState extends State<TicketStudentCard> {
  Map<String, dynamic>? _profile;
  List<String> _courses = const [];
  String _role = '';
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = Supabase.instance.client;
    try {
      _profile = Map<String, dynamic>.from(
          await c.from('profiles').select().eq('id', widget.userId).single());
    } catch (_) {}
    try {
      final rows = await c
          .from('enrollments')
          .select('status, courses(title)')
          .eq('user_id', widget.userId)
          .eq('tenant_id', TenantContext.id);
      _courses = [
        for (final r in rows)
          if (r['courses'] is Map) '${(r['courses'] as Map)['title']}'
      ];
    } catch (_) {}
    try {
      final m = await c
          .from('tenant_memberships')
          .select('role, status')
          .eq('user_id', widget.userId)
          .eq('tenant_id', TenantContext.id)
          .maybeSingle();
      if (m != null) _role = '${m['role'] ?? ''}';
    } catch (_) {}
    if (mounted) setState(() => _loaded = true);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final ar = s.locale.languageCode == 'ar';
    final p = _profile;
    if (!_loaded) return const LinearProgressIndicator(minHeight: 2);
    if (p == null) return const SizedBox.shrink();
    final rows = <(String, String)>[];
    for (final e in _labels.entries) {
      final v = p[e.key];
      if (v == null || '$v'.trim().isEmpty) continue;
      var text = '$v';
      if (e.key == 'created_at' && text.length >= 10) text = text.substring(0, 10);
      rows.add((ar ? e.value.$1 : e.value.$2, text));
    }
    if (_role.isNotEmpty) rows.add((ar ? 'الدور' : 'Role', _role));
    final name = '${p['full_name'] ?? p['email'] ?? ''}';
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: ExpansionTile(
        leading: CircleAvatar(child: Text(name.isEmpty ? '?' : name[0])),
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text('${p['email'] ?? ''}${(p['phone'] ?? '').toString().isEmpty ? '' : '  ·  ${p['phone']}'}',
            maxLines: 1, overflow: TextOverflow.ellipsis),
        childrenPadding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                    width: 110,
                    child: Text(r.$1, style: const TextStyle(color: Colors.grey))),
                Expanded(child: SelectableText(r.$2)),
              ]),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                  width: 110,
                  child: Text(ar ? 'الكورسات' : 'Courses',
                      style: const TextStyle(color: Colors.grey))),
              Expanded(
                  child: Text(_courses.isEmpty
                      ? (ar ? 'لا يوجد' : 'None')
                      : _courses.join('، '))),
            ]),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              icon: const Icon(Icons.person_search_outlined),
              label: Text(ar ? 'ملف الطالب الكامل' : 'Full student file'),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => AdminStudentDetailScreen(user: p))),
            ),
          ),
        ],
      ),
    );
  }
}
