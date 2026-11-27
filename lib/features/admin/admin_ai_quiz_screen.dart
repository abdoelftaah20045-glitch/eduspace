import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/tenant.dart';

/// Admin: generate a practice quiz for every lesson that has none, in one
/// run (free Gemini tier through the quiz-gen function). Drafts by default.
/// Questions come from the lesson title/description and the course topic, so
/// they are topic practice, not a check of what a given video said.
class AdminAiQuizScreen extends StatefulWidget {
  const AdminAiQuizScreen({super.key});

  @override
  State<AdminAiQuizScreen> createState() => _AdminAiQuizScreenState();
}

class _AdminAiQuizScreenState extends State<AdminAiQuizScreen> {
  SupabaseClient get _c => Supabase.instance.client;
  List<Map<String, dynamic>>? _courses;
  final Set<String> _picked = {};
  bool _publish = false;
  bool _running = false;
  bool _stop = false;
  int _total = 0;
  int _done = 0;
  int _made = 0;
  int _skipped = 0;
  int _failed = 0;
  String _current = '';
  String? _error;
  final List<String> _log = [];

  Map<String, dynamic>? _cfg;
  Map<String, dynamic>? _prog;
  String? _autoErr;

  @override
  void initState() {
    super.initState();
    _load();
    _loadAuto();
  }

  Future<void> _loadAuto() async {
    try {
      final row = await _c
          .from('quiz_auto_config')
          .select()
          .eq('tenant_id', TenantContext.id)
          .maybeSingle();
      final pr = await _c.rpc('quiz_auto_progress', params: {'t': TenantContext.id});
      if (!mounted) return;
      setState(() {
        _cfg = row == null ? <String, dynamic>{} : Map<String, dynamic>.from(row);
        _prog = pr is Map ? Map<String, dynamic>.from(pr) : null;
        _autoErr = null;
      });
    } catch (_) {
      if (mounted) setState(() => _autoErr = 'شغّل ملف SQL part37 الأول عشان التشغيل التلقائي.');
    }
  }

  Future<void> _saveAuto(Map<String, dynamic> patch) async {
    try {
      final next = {...?_cfg, ...patch};
      await _c.from('quiz_auto_config').upsert({
        'tenant_id': TenantContext.id,
        'enabled': next['enabled'] == true,
        'publish': next['publish'] == true,
        'text_fallback': next['text_fallback'] == true,
        'course_ids': next['course_ids'],
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        if (patch['enabled'] == true) 'paused_until': null,
        if (patch['enabled'] == true) 'last_error': null,
      });
      await _loadAuto();
    } catch (e) {
      if (mounted) setState(() => _autoErr = '$e');
    }
  }

  Widget _autoCard() {
    final cfg = _cfg;
    if (_autoErr != null) {
      return Card(child: Padding(padding: const EdgeInsets.all(14), child: Text(_autoErr!)));
    }
    if (cfg == null) return const SizedBox.shrink();
    final p = _prog;
    final paused = DateTime.tryParse('${cfg['paused_until'] ?? ''}');
    final waiting = paused != null && paused.isAfter(DateTime.now().toUtc());
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SwitchListTile(
            value: cfg['enabled'] == true,
            title: const Text('تشغيل تلقائي (على السيرفر)'),
            subtitle: const Text(
                'بيشتغل لوحده كل كام دقيقة من غير ما تفتح التطبيق. لما الحد اليومي يخلص بيقف ويكمل تاني يوم لحد ما كل درس يبقى له اختبار. الدروس اللي مفيهاش فيديو يوتيوب عام بتتخطى.'),
            onChanged: (v) => _saveAuto({
              'enabled': v,
              'course_ids': _picked.isEmpty ? null : _picked.toList(),
            }),
          ),
          SwitchListTile(
            value: cfg['publish'] == true,
            title: const Text('نشر مباشر للاختبارات (من غير مراجعة)'),
            onChanged: (v) => _saveAuto({'publish': v}),
          ),
          SwitchListTile(
            value: cfg['text_fallback'] == true,
            title: const Text('لو الفيديو مش متاح، اعمل من العنوان والوصف'),
            subtitle: const Text('مقفول: مفيش اختبار بيتعمل إلا من الفيديو نفسه.'),
            onChanged: (v) => _saveAuto({'text_fallback': v}),
          ),
          if (p != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Text(
                  'اتعمل: ${p['done']}  •  فاضل: ${p['remaining']}  •  اتخطى: ${p['skipped']}',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          if (waiting)
            const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text('واقف مؤقتاً (الحد اليومي)، وهيكمل لوحده.')),
          if ('${cfg['last_error'] ?? ''}'.isNotEmpty)
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text('${cfg['last_error']}', style: const TextStyle(fontSize: 12))),
          TextButton(onPressed: _loadAuto, child: const Text('تحديث')),
        ]),
      ),
    );
  }

  Future<void> _load() async {
    try {
      final rows = await _c
          .from('courses')
          .select('id,title,status')
          .eq('tenant_id', TenantContext.id)
          .order('created_at', ascending: false)
          .limit(1000);
      if (mounted) setState(() => _courses = List<Map<String, dynamic>>.from(rows));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _stop = false;
      _done = _made = _skipped = _failed = 0;
      _log.clear();
      _error = null;
      _current = 'بجهز قائمة الدروس...';
    });
    try {
      final ids = _picked.toList();
      final lessons = <Map<String, dynamic>>[];
      for (var i = 0; i < ids.length; i += 20) {
        final part = ids.sublist(i, i + 20 > ids.length ? ids.length : i + 20);
        final r = await _c
            .from('lessons')
            .select('id,title,course_id,sort_order')
            .inFilter('course_id', part)
            .order('sort_order')
            .limit(5000);
        lessons.addAll(List<Map<String, dynamic>>.from(r));
      }
      Set<String> have = {};
      try {
        final lids = [for (final l in lessons) '${l['id']}'];
        for (var i = 0; i < lids.length; i += 100) {
          final part = lids.sublist(i, i + 100 > lids.length ? lids.length : i + 100);
          final ex = await _c.from('exams').select('lesson_id').inFilter('lesson_id', part);
          have.addAll([for (final e in ex) '${e['lesson_id']}']);
        }
      } catch (_) {
        setState(() {
          _running = false;
          _error = 'لازم تشغّل ملف SQL part36 الأول، وتنشر دالة quiz-gen.';
        });
        return;
      }
      final todo = lessons.where((l) => !have.contains('${l['id']}')).toList();
      setState(() => _total = todo.length);
      for (final l in todo) {
        if (_stop || !mounted) break;
        setState(() => _current = '${l['title']}');
        try {
          final res = await _c.functions
              .invoke('quiz-gen', body: {'lesson_id': l['id'], 'publish': _publish, 'count': 6})
              .timeout(const Duration(seconds: 200));
          final d = res.data;
          if (d is Map && d['ok'] == true) {
            _made++;
          } else if (d is Map && d['skipped'] != null) {
            _skipped++;
            _log.add('تخطي: ${l['title']} (${d['skipped']})');
          } else if (d is Map && d['error'] == 'no_key') {
            setState(() => _error = 'مفتاح GEMINI_API_KEY مش متسجل في Supabase Secrets.');
            break;
          } else {
            _failed++;
            _log.add('فشل: ${l['title']} ${d is Map ? (d['detail'] ?? d['error']) : ''}');
          }
        } on FunctionException catch (e) {
          if (e.status == 404) {
            setState(() => _error = 'دالة quiz-gen مش منشورة في Supabase. انشرها (Deploy) وارجع جرب.');
            break;
          }
          _failed++;
          _log.add('فشل: ${l['title']} (${e.status})');
        } catch (e) {
          _failed++;
          _log.add('فشل: ${l['title']}');
        }
        _done++;
        if (mounted) setState(() {});
        // Free tier allows only a few requests per minute.
        await Future<void>.delayed(const Duration(seconds: 8));
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
    if (mounted) setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    final courses = _courses;
    return Scaffold(
      appBar: AppBar(title: const Text('اختبارات تدريبية بالذكاء الاصطناعي')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        _autoCard(),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(14),
            child: Text(
                'بيعمل اختبار تدريبي (6 أسئلة اختيار من متعدد) لكل درس معندوش اختبار. لو الفيديو يوتيوب عام، الذكاء الاصطناعي بيشوف الفيديو نفسه وبيسأل في اللي اتشرح فعلاً (عدد الأسئلة حسب طول الفيديو)، ولو مش متاح بيرجع لعنوان الدرس ووصفه. الحد المجاني حوالي 8 ساعات فيديو في اليوم، وبتتولد بالذكاء الاصطناعي المجاني فممكن يبقى فيها أخطاء، فالأفضل مراجعتها. بيتحفظوا مسودة لحد ما تنشرهم، أو فعّل النشر المباشر. سيب الشاشة مفتوحة أثناء التشغيل.'),
          ),
        ),
        SwitchListTile(
          value: _publish,
          title: const Text('نشر مباشر (من غير مراجعة)'),
          onChanged: _running ? null : (v) => setState(() => _publish = v),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        if (courses == null)
          const Center(child: CircularProgressIndicator())
        else ...[
          Row(children: [
            TextButton(
                onPressed: _running ? null : () => setState(() => _picked.addAll([for (final c in courses) '${c['id']}'])),
                child: const Text('اختر الكل')),
            TextButton(
                onPressed: _running ? null : () => setState(_picked.clear),
                child: const Text('إلغاء الاختيار')),
          ]),
          for (final c in courses)
            CheckboxListTile(
              dense: true,
              value: _picked.contains('${c['id']}'),
              title: Text('${c['title']}', maxLines: 2, overflow: TextOverflow.ellipsis),
              onChanged: _running
                  ? null
                  : (v) => setState(() {
                        if (v == true) {
                          _picked.add('${c['id']}');
                        } else {
                          _picked.remove('${c['id']}');
                        }
                      }),
            ),
        ],
        const SizedBox(height: 12),
        if (_running) ...[
          LinearProgressIndicator(value: _total == 0 ? null : _done / _total),
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('$_done / $_total  •  اتعمل $_made  •  اتخطى $_skipped  •  فشل $_failed\n$_current')),
          OutlinedButton(onPressed: () => setState(() => _stop = true), child: const Text('إيقاف')),
        ] else
          FilledButton(
              onPressed: _picked.isEmpty ? null : _run,
              child: Text('ابدأ التوليد (${_picked.length} كورس)')),
        if (!_running && (_made + _skipped + _failed) > 0)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text('خلص: اتعمل $_made اختبار، اتخطى $_skipped، فشل $_failed',
                style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        for (final l in _log.take(60)) Text(l, style: const TextStyle(fontSize: 12)),
      ]),
    );
  }
}
