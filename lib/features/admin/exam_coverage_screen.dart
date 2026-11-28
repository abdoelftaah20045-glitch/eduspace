import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/tenant.dart';

/// Admin: which lessons already have an exam and which do not. Counts at the
/// top open the lists behind them. Missing ones get a one-tap "generate".
class ExamCoverageScreen extends StatefulWidget {
  const ExamCoverageScreen({super.key});

  @override
  State<ExamCoverageScreen> createState() => _ExamCoverageScreenState();
}

class _ExamCoverageScreenState extends State<ExamCoverageScreen> {
  SupabaseClient get _c => Supabase.instance.client;
  List<Map<String, dynamic>>? _lessons;
  Map<String, String> _courseTitle = {};
  Map<String, int> _examCount = {};
  String _filter = 'all'; // all, has, none
  String? _error;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final cs = await _c
          .from('courses')
          .select('id,title')
          .eq('tenant_id', TenantContext.id)
          .limit(2000);
      final titles = {for (final c in cs) '${c['id']}': '${c['title']}'};
      final ids = titles.keys.toList();
      final lessons = <Map<String, dynamic>>[];
      for (var i = 0; i < ids.length; i += 20) {
        final part = ids.sublist(i, i + 20 > ids.length ? ids.length : i + 20);
        final r = await _c
            .from('lessons')
            .select('id,title,course_id,sort_order,type')
            .inFilter('course_id', part)
            .order('sort_order')
            .limit(5000);
        lessons.addAll(List<Map<String, dynamic>>.from(r));
      }
      final counts = <String, int>{};
      final lids = [for (final l in lessons) '${l['id']}'];
      for (var i = 0; i < lids.length; i += 100) {
        final part = lids.sublist(i, i + 100 > lids.length ? lids.length : i + 100);
        final ex = await _c.from('exams').select('lesson_id').inFilter('lesson_id', part);
        for (final e in ex) {
          final k = '${e['lesson_id']}';
          counts[k] = (counts[k] ?? 0) + 1;
        }
      }
      lessons.sort((a, b) {
        final c = (titles['${a['course_id']}'] ?? '').compareTo(titles['${b['course_id']}'] ?? '');
        if (c != 0) return c;
        return ((a['sort_order'] as num?) ?? 0).compareTo((b['sort_order'] as num?) ?? 0);
      });
      if (!mounted) return;
      setState(() {
        _courseTitle = titles;
        _examCount = counts;
        _lessons = lessons;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'تعذر تحميل القائمة. جرّب تاني.');
    }
  }

  Future<void> _generate(Map<String, dynamic> l) async {
    final id = '${l['id']}';
    setState(() => _busy.add(id));
    String msg;
    try {
      final res = await _c.functions
          .invoke('quiz-gen', body: {'lesson_id': id, 'publish': false, 'count': 10})
          .timeout(const Duration(seconds: 200));
      final d = res.data;
      if (d is Map && d['ok'] == true) {
        msg = 'اتعمل اختبار مسودة للدرس';
      } else if (d is Map && d['skipped'] != null) {
        msg = 'اتخطى: ${d['skipped']}';
      } else if (d is Map && d['error'] == 'no_key') {
        msg = 'مفتاح GEMINI_API_KEY مش متسجل في Supabase Secrets.';
      } else {
        msg = 'فشل التوليد: ${d is Map ? (d['detail'] ?? d['error'] ?? '') : ''}';
      }
    } on FunctionException catch (e) {
      msg = e.status == 404 ? 'دالة quiz-gen مش منشورة في Supabase.' : 'فشل التوليد (${e.status})';
    } catch (_) {
      msg = 'فشل التوليد';
    }
    if (!mounted) return;
    setState(() => _busy.remove(id));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final all = _lessons ?? const <Map<String, dynamic>>[];
    final has = all.where((l) => (_examCount['${l['id']}'] ?? 0) > 0).toList();
    final none = all.where((l) => (_examCount['${l['id']}'] ?? 0) == 0).toList();
    final shown = _filter == 'has' ? has : (_filter == 'none' ? none : all);
    Widget stat(String key, String label, int n) {
      final on = _filter == key;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() => _filter = key),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: on ? scheme.primary : scheme.primaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(children: [
              Text('$n',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: on ? scheme.onPrimary : scheme.onPrimaryContainer)),
              Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: on ? scheme.onPrimary : scheme.onPrimaryContainer)),
            ]),
          ),
        ),
      );
    }

    String? lastCourse;
    final children = <Widget>[];
    for (final l in shown) {
      final cid = '${l['course_id']}';
      if (cid != lastCourse) {
        lastCourse = cid;
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(4, 14, 4, 4),
          child: Text(_courseTitle[cid] ?? '',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
        ));
      }
      final n = _examCount['${l['id']}'] ?? 0;
      final busy = _busy.contains('${l['id']}');
      children.add(Card(
        child: ListTile(
          title: Text('${l['title']}', maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text(n > 0 ? 'عدد الاختبارات: $n' : 'من غير اختبار'),
          leading: Icon(n > 0 ? Icons.check_circle : Icons.error_outline,
              color: n > 0 ? Colors.green : Colors.orange),
          trailing: n > 0
              ? null
              : (busy
                  ? const SizedBox(
                      width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                  : FilledButton(
                      onPressed: () => _generate(l), child: const Text('ولّد اختبار'))),
        ),
      ));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('تغطية الاختبارات')),
      body: _lessons == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Text(_error!))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 16), children: [
                Row(children: [
                  stat('all', 'كل الدروس', all.length),
                  const SizedBox(width: 8),
                  stat('has', 'عندها اختبار', has.length),
                  const SizedBox(width: 8),
                  stat('none', 'من غير اختبار', none.length),
                ]),
                if (children.isEmpty)
                  const Padding(
                      padding: EdgeInsets.all(24), child: Center(child: Text('مفيش حاجة هنا'))),
                ...children,
              ]),
            ),
    );
  }
}
