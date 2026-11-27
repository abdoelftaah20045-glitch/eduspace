import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/tenant.dart';

/// Short written assignment under a lesson. The clock starts when the student
/// taps "start"; the deadline length comes from the admin (lesson, course or
/// organization default, 24 h). Shows nothing when the lesson has none, or
/// when the SQL for it has not been run yet.
class LessonAssignmentCard extends StatefulWidget {
  const LessonAssignmentCard({super.key, required this.lessonId});
  final String lessonId;

  @override
  State<LessonAssignmentCard> createState() => _LessonAssignmentCardState();
}

class _LessonAssignmentCardState extends State<LessonAssignmentCard> {
  SupabaseClient get _c => Supabase.instance.client;
  Map<String, dynamic>? _a;
  Map<String, dynamic>? _sub;
  DateTime? _due;
  DateTime? _started;
  int _hours = 24;
  bool _allowLate = false;
  bool _busy = false;
  List<TextEditingController> _ctrls = [];
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tick?.cancel();
    for (final c in _ctrls) {
      c.dispose();
    }
    super.dispose();
  }

  List<String> get _questions =>
      [for (final q in (_a?['questions'] as List? ?? const [])) '$q'];

  Future<void> _load() async {
    try {
      final rows = await _c
          .from('assignments')
          .select()
          .eq('lesson_id', widget.lessonId)
          .eq('status', 'published')
          .limit(1);
      if (rows.isEmpty) return;
      final a = Map<String, dynamic>.from(rows.first);
      final uid = _c.auth.currentUser?.id;
      Map<String, dynamic>? sub;
      DateTime? started;
      if (uid != null) {
        final s = await _c
            .from('assignment_submissions')
            .select()
            .eq('assignment_id', a['id'])
            .eq('user_id', uid)
            .maybeSingle();
        if (s != null) sub = Map<String, dynamic>.from(s);
        final st = await _c
            .from('assignment_starts')
            .select('started_at')
            .eq('assignment_id', a['id'])
            .eq('user_id', uid)
            .maybeSingle();
        if (st != null) started = DateTime.tryParse('${st['started_at']}')?.toLocal();
      }
      if (!mounted) return;
      setState(() {
        _a = a;
        _sub = sub;
        _started = started;
        _allowLate = a['allow_late'] == true;
        _ctrls = [for (final _ in _questions) TextEditingController()];
      });
      if (started != null) await _window();
    } catch (_) {}
  }

  /// Starts the clock (first call) or reads it back.
  Future<void> _window() async {
    final r = await _c.rpc('assignment_window', params: {'p_assignment': _a!['id']});
    if (r is! Map || !mounted) return;
    setState(() {
      _started = DateTime.tryParse('${r['started_at']}')?.toLocal();
      _due = DateTime.tryParse('${r['due_at']}')?.toLocal();
      _hours = (r['hours'] as num?)?.toInt() ?? 24;
      _allowLate = r['allow_late'] == true;
    });
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _start() async {
    setState(() => _busy = true);
    try {
      await _window();
    } catch (_) {
      _snack('حصل خطأ، حاول تاني.');
    }
    if (mounted) setState(() => _busy = false);
  }

  void _snack(String t) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  Future<void> _submit() async {
    final qs = _questions;
    if (_ctrls.any((c) => c.text.trim().isEmpty)) {
      _snack('جاوب على كل الأسئلة الأول.');
      return;
    }
    setState(() => _busy = true);
    try {
      final text = [
        for (var i = 0; i < qs.length; i++) '${i + 1}) ${qs[i]}\n${_ctrls[i].text.trim()}'
      ].join('\n\n');
      await _c.from('assignment_submissions').upsert({
        'assignment_id': _a!['id'],
        'user_id': _c.auth.currentUser!.id,
        'tenant_id': TenantContext.id,
        'text_answer': text,
        'status': 'submitted',
        'submitted_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'assignment_id,user_id');
      _snack('اتسلّم التكليف.');
      await _load();
    } catch (e) {
      _snack('$e'.contains('assignment_closed') ? 'الميعاد خلص ومينفعش التسليم.' : 'حصل خطأ، حاول تاني.');
    }
    if (mounted) setState(() => _busy = false);
  }

  String _left(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    String two(int x) => x.toString().padLeft(2, '0');
    return '${two(h)}:${two(m)}:${two(s)}';
  }

  @override
  Widget build(BuildContext context) {
    final a = _a;
    if (a == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final graded = _sub?['status'] == 'graded';
    final submitted = _sub != null;
    final due = _due;
    final now = DateTime.now();
    final overdue = due != null && now.isAfter(due);
    final started = _started != null && due != null;
    final closed = overdue && !_allowLate && !submitted;

    Widget head(String badge, Color color) => Row(children: [
          Icon(Icons.edit_note, color: scheme.primary),
          const SizedBox(width: 8),
          const Expanded(
              child: Text('تكليف الدرس', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: color.withValues(alpha: .15), borderRadius: BorderRadius.circular(20)),
            child: Text(badge, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
          ),
        ]);

    final children = <Widget>[];
    if (graded) {
      children.add(head('اتصحح', const Color(0xFF2E9E5B)));
      children.add(const SizedBox(height: 8));
      children.add(Text('الدرجة: ${_sub?['score']} / ${a['max_points']}',
          style: const TextStyle(fontWeight: FontWeight.w800)));
      if ('${_sub?['feedback'] ?? ''}'.isNotEmpty) children.add(Text('ملاحظات المدرس: ${_sub?['feedback']}'));
    } else if (!started && !submitted) {
      children.add(head('لسه مبدأتش', Colors.grey));
      children.add(const SizedBox(height: 8));
      children.add(Text('${_questions.length} أسئلة قصيرة. أول ما تدوس "ابدأ" بيبدأ العد التنازلي وعندك ميعاد محدد للتسليم (الافتراضي 24 ساعة).'));
      children.add(const SizedBox(height: 8));
      children.add(FilledButton(onPressed: _busy ? null : _start, child: const Text('ابدأ التكليف')));
    } else if (closed) {
      children.add(head('فاتك الميعاد', const Color(0xFFE53935)));
      children.add(const SizedBox(height: 8));
      children.add(const Text('الميعاد خلص ومتسلمش تكليف. كلّم المدرس لو محتاج فرصة تانية.'));
    } else {
      final badge = submitted
          ? (_sub?['status'] == 'late' ? 'اتسلّم متأخر' : 'اتسلّم')
          : (overdue ? 'متأخر' : 'مفتوح');
      children.add(head(badge, submitted ? const Color(0xFF2E9E5B) : (overdue ? const Color(0xFFF29900) : scheme.primary)));
      if (due != null) {
        children.add(const SizedBox(height: 8));
        children.add(Text(
            overdue ? 'الميعاد عدّى (التسليم المتأخر مسموح).' : 'الوقت المتبقي: ${_left(due.difference(now))}',
            style: TextStyle(fontWeight: FontWeight.w800, color: overdue ? const Color(0xFFF29900) : scheme.primary)));
      }
      final qs = _questions;
      for (var i = 0; i < qs.length; i++) {
        children.add(const SizedBox(height: 10));
        children.add(Text('${i + 1}) ${qs[i]}', style: const TextStyle(fontWeight: FontWeight.w700)));
        children.add(const SizedBox(height: 4));
        children.add(TextField(
          controller: _ctrls[i],
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'اكتب إجابتك'),
        ));
      }
      if (submitted && '${_sub?['text_answer'] ?? ''}'.isNotEmpty) {
        children.add(const SizedBox(height: 8));
        children.add(const Text('آخر تسليم ليك:', style: TextStyle(fontWeight: FontWeight.w700)));
        children.add(Text('${_sub?['text_answer']}', style: const TextStyle(fontSize: 12)));
      }
      children.add(const SizedBox(height: 10));
      children.add(FilledButton(
          onPressed: _busy ? null : _submit, child: Text(submitted ? 'عدّل التسليم' : 'سلّم التكليف')));
    }
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children)),
    );
  }
}
