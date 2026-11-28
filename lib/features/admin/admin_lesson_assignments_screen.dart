import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/tenant.dart';

/// Admin: deadline length for lesson assignments, and review of the
/// assignment cards (drafts from the video pass or made by hand).
class AdminLessonAssignmentsScreen extends StatefulWidget {
  const AdminLessonAssignmentsScreen({super.key});

  @override
  State<AdminLessonAssignmentsScreen> createState() => _AdminLessonAssignmentsScreenState();
}

class _AdminLessonAssignmentsScreenState extends State<AdminLessonAssignmentsScreen> {
  SupabaseClient get _c => Supabase.instance.client;
  final _hours = TextEditingController(text: '24');
  List<Map<String, dynamic>>? _rows;
  String? _err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _hours.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final st = await _c
          .from('tenant_settings')
          .select('setting_value')
          .eq('tenant_id', TenantContext.id)
          .eq('setting_key', 'assignment_defaults')
          .maybeSingle();
      final v = st?['setting_value'];
      if (v is Map && v['hours'] != null) _hours.text = '${v['hours']}';
      final rows = await _c
          .from('assignments')
          .select('id,title,status,questions,allow_late,lesson_id,course_id,ai_generated,created_at')
          .not('lesson_id', 'is', null)
          .eq('tenant_id', TenantContext.id)
          .order('created_at', ascending: false)
          .limit(500);
      if (mounted) {
        setState(() {
          _rows = List<Map<String, dynamic>>.from(rows);
          _err = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _err = 'شغّل ملف SQL part39 الأول.');
    }
  }

  Future<void> _saveHours() async {
    final h = int.tryParse(_hours.text.trim());
    if (h == null || h < 1 || h > 720) {
      _snack('اكتب عدد ساعات من 1 لـ 720.');
      return;
    }
    try {
      await _c.from('tenant_settings').upsert({
        'tenant_id': TenantContext.id,
        'setting_key': 'assignment_defaults',
        'setting_value': {'hours': h},
      }, onConflict: 'tenant_id,setting_key');
      _snack('اتحفظ. (ممكن تغيّره لكورس أو درس معيّن من شاشة تعديله).');
    } catch (_) {
      _snack('حصل خطأ.');
    }
  }

  void _snack(String t) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  Future<void> _set(Map<String, dynamic> r, Map<String, dynamic> patch) async {
    try {
      await _c.from('assignments').update(patch).eq('id', r['id']);
      await _load();
    } catch (_) {
      _snack('حصل خطأ.');
    }
  }

  Future<void> _publishAll() async {
    try {
      await _c
          .from('assignments')
          .update({'status': 'published'})
          .not('lesson_id', 'is', null)
          .eq('status', 'draft')
          .eq('tenant_id', TenantContext.id);
      await _load();
    } catch (_) {
      _snack('حصل خطأ.');
    }
  }

  Future<void> _edit(Map<String, dynamic> r) async {
    final c = TextEditingController(text: [for (final q in (r['questions'] as List? ?? const [])) '$q'].join('\n'));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('الأسئلة (سؤال في كل سطر)'),
        content: TextField(controller: c, minLines: 4, maxLines: 10),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
        ],
      ),
    );
    if (ok == true) {
      final qs = c.text.split('\n').map((x) => x.trim()).where((x) => x.isNotEmpty).toList();
      if (qs.isNotEmpty) await _set(r, {'questions': qs, 'max_points': qs.length * 2});
    }
    c.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final drafts = rows?.where((r) => r['status'] == 'draft').length ?? 0;
    return Scaffold(
      appBar: AppBar(title: const Text('تكليفات الدروس')),
      body: ListView(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 16), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('مدة التسليم الافتراضية (بالساعات)، بتبدأ من لحظة ما الطالب يدوس "ابدأ التكليف"',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Row(children: [
                SizedBox(
                    width: 100,
                    child: TextField(
                        controller: _hours,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true))),
                const SizedBox(width: 12),
                FilledButton(onPressed: _saveHours, child: const Text('حفظ')),
              ]),
              const SizedBox(height: 6),
              const Text('لكورس معيّن أو درس معيّن: غيّر "ساعات التكليف" في شاشة تعديله، وهي بتغلب الافتراضي.',
                  style: TextStyle(fontSize: 12)),
            ]),
          ),
        ),
        if (_err != null) Padding(padding: const EdgeInsets.all(8), child: Text(_err!)),
        if (rows == null && _err == null) const Center(child: CircularProgressIndicator()),
        if (rows != null) ...[
          if (drafts > 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: OutlinedButton(onPressed: _publishAll, child: Text('نشر كل المسودات ($drafts)')),
            ),
          if (rows.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('مفيش تكليفات دروس لسه.')),
          for (final r in rows)
            Card(
              child: ExpansionTile(
                title: Text('${r['title']}', maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                    '${r['status'] == 'draft' ? 'مسودة' : 'منشور'}${r['ai_generated'] == true ? ' • مولّد بالذكاء الاصطناعي' : ''}${r['allow_late'] == true ? ' • التأخير مسموح' : ''}'),
                children: [
                  for (final q in (r['questions'] as List? ?? const [])) ListTile(dense: true, title: Text('$q')),
                  Wrap(spacing: 8, children: [
                    TextButton(
                        onPressed: () => _set(r, {'status': r['status'] == 'draft' ? 'published' : 'draft'}),
                        child: Text(r['status'] == 'draft' ? 'نشر' : 'رجوع لمسودة')),
                    TextButton(onPressed: () => _edit(r), child: const Text('تعديل الأسئلة')),
                    TextButton(
                        onPressed: () => _set(r, {'allow_late': r['allow_late'] != true}),
                        child: Text(r['allow_late'] == true ? 'امنع التأخير' : 'اسمح بالتأخير')),
                    TextButton(
                        onPressed: () async {
                          await _c.from('assignments').delete().eq('id', r['id']);
                          await _load();
                        },
                        child: const Text('حذف')),
                  ]),
                ],
              ),
            ),
        ],
      ]),
    );
  }
}
