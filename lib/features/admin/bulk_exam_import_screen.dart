import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/tenant.dart';
import 'bulk_exam_import.dart';
import 'data/admin_exams_repo.dart';
import 'file_import_screen.dart' show parseTable;

/// Admin: bring in the quizzes of many lessons at once from a CSV / XLSX /
/// JSON file, pasted text or his own Google Sheet link. Rows are matched to
/// lessons by YouTube link/id or title; each lesson gets one auto-graded exam.
class BulkExamImportScreen extends StatefulWidget {
  const BulkExamImportScreen({super.key});

  @override
  State<BulkExamImportScreen> createState() => _BulkExamImportScreenState();
}

class _Group {
  _Group(this.key, this.course, this.ref);
  final String key;
  final String course;
  final String ref;
  final List<BulkQuestion> qs = [];
  Map<String, dynamic>? lesson;
  bool hasExam = false;
  int get valid => qs.where((q) => q.q.problem == null).length;
}

class _BulkExamImportScreenState extends State<BulkExamImportScreen> {
  final _paste = TextEditingController();
  final _sheet = TextEditingController();
  final _pass = TextEditingController(text: '50');
  final _attempts = TextEditingController(text: '3');
  final _minutes = TextEditingController();
  List<_Group>? _groups;
  int _rowCount = 0;
  bool _busy = false;
  String _status = '';
  String? _error;

  SupabaseClient get _c => Supabase.instance.client;

  Future<void> _fromRows(List<BulkQuestion> rows) async {
    if (rows.isEmpty) {
      setState(() {
        _groups = null;
        _error =
            'مفيش أسئلة اتقرت. لازم أعمدة: lesson (أو video/youtube) و question وبعدها الاختيارات A,B,C,D و answer.';
      });
      return;
    }
    setState(() {
      _busy = true;
      _status = 'بطابق الأسئلة مع الدروس...';
      _error = null;
    });
    try {
      final courses = await _c
          .from('courses')
          .select('id,title')
          .eq('tenant_id', TenantContext.id)
          .limit(2000);
      final titles = {for (final r in courses) '${r['id']}': '${r['title']}'};
      final lessons = await _c
          .from('lessons')
          .select('id,course_id,title,media_url')
          .inFilter('course_id', titles.keys.toList())
          .limit(10000);
      final groups = <String, _Group>{};
      for (final r in rows) {
        final k = '${r.course.toLowerCase()}|${r.lesson.toLowerCase()}';
        groups.putIfAbsent(k, () => _Group(k, r.course, r.lesson)).qs.add(r);
      }
      for (final g in groups.values) {
        g.lesson = matchLesson(g.ref, g.course, List<Map<String, dynamic>>.from(lessons), titles);
      }
      final ids = [for (final g in groups.values) if (g.lesson != null) '${g.lesson!['id']}'];
      if (ids.isNotEmpty) {
        try {
          final ex = await _c.from('exams').select('lesson_id').inFilter('lesson_id', ids);
          final have = {for (final e in ex) '${e['lesson_id']}'};
          for (final g in groups.values) {
            g.hasExam = g.lesson != null && have.contains('${g.lesson!['id']}');
          }
        } catch (_) {
          _error = 'لازم تشغّل ملف SQL part36 الأول (بيضيف ربط الاختبار بالدرس).';
        }
      }
      setState(() {
        _groups = groups.values.toList();
        _rowCount = rows.length;
      });
    } catch (e) {
      setState(() => _error = 'تعذر القراءة: $e');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _file() async {
    try {
      final picked = await FilePicker.pickFiles();
      if (picked.isEmpty) return;
      final f = picked.first;
      final bytes = await f.readAsBytes();
      final name = f.name.toLowerCase();
      if (name.endsWith('.json')) {
        await _fromRows(parseBulkJson(utf8.decode(bytes, allowMalformed: true)));
      } else {
        await _fromRows(parseBulkRows(parseTable(f.name, bytes)));
      }
    } catch (e) {
      setState(() => _error = 'تعذر قراءة الملف: $e');
    }
  }

  Future<void> _pasted() async {
    final t = _paste.text.trim();
    if (t.isEmpty) return;
    try {
      if (t.startsWith('[') || t.startsWith('{')) {
        await _fromRows(parseBulkJson(t));
      } else {
        await _fromRows(parseBulkRows(parseTable('paste.csv', utf8.encode(t))));
      }
    } catch (e) {
      setState(() => _error = 'تعذر قراءة النص: $e');
    }
  }

  Future<void> _sheetLink() async {
    final u = _sheet.text.trim();
    final m = RegExp(r'/spreadsheets/d/([A-Za-z0-9_-]+)').firstMatch(u);
    if (m == null) {
      setState(() => _error = 'ده مش رابط Google Sheet.');
      return;
    }
    final gid = RegExp(r'[#&?]gid=(\d+)').firstMatch(u)?.group(1) ?? '0';
    setState(() {
      _busy = true;
      _status = 'بقرا الشيت...';
      _error = null;
    });
    try {
      final r = await http.get(Uri.parse(
          'https://docs.google.com/spreadsheets/d/${m.group(1)}/export?format=csv&gid=$gid'));
      if (r.statusCode != 200) {
        setState(() {
          _busy = false;
          _error =
              'الشيت مش متاح. خليه "أي شخص معاه الرابط يشوف" وجرب تاني (كود ${r.statusCode}).';
        });
        return;
      }
      await _fromRows(parseBulkRows(parseTable('sheet.csv', r.bodyBytes)));
    } catch (e) {
      setState(() => _error = 'تعذر قراءة الشيت: $e');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _save() async {
    final groups = _groups;
    if (groups == null) return;
    final passPct = (double.tryParse(_pass.text.trim()) ?? 50).clamp(0, 100);
    final attempts = int.tryParse(_attempts.text.trim()) ?? 3;
    final minutes = int.tryParse(_minutes.text.trim());
    final todo = groups.where((g) => g.lesson != null && !g.hasExam && g.valid > 0).toList();
    setState(() {
      _busy = true;
      _error = null;
    });
    var exams = 0;
    var questions = 0;
    var failed = 0;
    for (var gi = 0; gi < todo.length; gi++) {
      final g = todo[gi];
      setState(() => _status = 'بحفظ ${gi + 1} من ${todo.length}: ${g.lesson!['title']}');
      try {
        final good = g.qs.where((q) => q.q.problem == null).toList();
        final total = good.fold<double>(0, (a, q) => a + q.q.points);
        final examId = await AdminExamsRepository.createExam({
          'course_id': g.lesson!['course_id'],
          'lesson_id': g.lesson!['id'],
          'title': 'اختبار: ${g.lesson!['title']}',
          'description': '',
          'status': 'published',
          'pass_grade': (total * passPct / 100),
          'max_attempts': attempts,
          if (minutes != null) 'duration_minutes': minutes,
        });
        for (final b in good) {
          final q = b.q;
          final qid = await AdminExamsRepository.createQuestion(
            type: q.type,
            body: q.body.trim(),
            points: q.points,
            explanation: q.explanation,
            options: q.type == 'essay' ? const [] : q.toOptionMaps(),
          );
          await AdminExamsRepository.attachQuestion(examId, qid);
          questions++;
        }
        exams++;
      } catch (_) {
        failed++;
      }
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = '';
      _groups = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('اتعمل $exams اختبار و $questions سؤال${failed > 0 ? ' (فشل $failed)' : ''}')));
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groups;
    final matched = groups?.where((g) => g.lesson != null).length ?? 0;
    final todo = groups?.where((g) => g.lesson != null && !g.hasExam && g.valid > 0).length ?? 0;
    return Scaffold(
      appBar: AppBar(title: const Text('استيراد اختبارات بالجملة'), actions: [
        FilledButton(
            onPressed: (_busy || todo == 0) ? null : _save,
            child: Text('حفظ $todo')),
        const SizedBox(width: 12),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Card(
          child: Padding(
            padding: EdgeInsets.all(14),
            child: Text(
                'ارفع ملف واحد (CSV أو Excel أو JSON) أو الصق الجدول أو حط رابط Google Sheet بتاعك. كل سطر سؤال، وعمود lesson فيه رابط يوتيوب الفيديو أو عنوان الدرس. كل درس هياخد اختبار واحد بيظهر بعده ويتصحح لوحده.'),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          FilledButton.icon(
              onPressed: _busy ? null : _file,
              icon: const Icon(Icons.upload_file),
              label: const Text('اختر ملف')),
          OutlinedButton(
              onPressed: () async {
                await Clipboard.setData(const ClipboardData(text: bulkTemplateCsv));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('اتنسخ نموذج الجدول، الصقه في Excel أو Sheets')));
                }
              },
              child: const Text('انسخ نموذج الجدول')),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: _paste,
          maxLines: 4,
          decoration: const InputDecoration(
              labelText: 'أو الصق الجدول / JSON هنا', border: OutlineInputBorder()),
        ),
        Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(onPressed: _busy ? null : _pasted, child: const Text('اقرأ النص'))),
        TextField(
          controller: _sheet,
          decoration: const InputDecoration(
              labelText: 'أو رابط Google Sheet (أي شخص معاه الرابط يشوف)',
              border: OutlineInputBorder()),
        ),
        Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(onPressed: _busy ? null : _sheetLink, child: const Text('اقرأ الشيت'))),
        if (_busy) ...[
          const LinearProgressIndicator(),
          Padding(padding: const EdgeInsets.all(8), child: Text(_status)),
        ],
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        if (groups != null) ...[
          const Divider(),
          Text('$_rowCount سؤال في ${groups.length} درس. اتطابق: $matched. هيتعمل: $todo اختبار.',
              style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
                child: TextField(
                    controller: _pass,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'درجة النجاح %', border: OutlineInputBorder()))),
            const SizedBox(width: 8),
            Expanded(
                child: TextField(
                    controller: _attempts,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'عدد المحاولات', border: OutlineInputBorder()))),
            const SizedBox(width: 8),
            Expanded(
                child: TextField(
                    controller: _minutes,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'المدة (دقيقة)', border: OutlineInputBorder()))),
          ]),
          const SizedBox(height: 8),
          for (final g in groups)
            Card(
              child: ListTile(
                dense: true,
                leading: Icon(
                    g.lesson == null
                        ? Icons.error_outline
                        : (g.hasExam ? Icons.info_outline : Icons.check_circle),
                    color: g.lesson == null
                        ? Theme.of(context).colorScheme.error
                        : (g.hasExam ? Colors.orange : Colors.green)),
                title: Text(g.lesson == null ? g.ref : '${g.lesson!['title']}',
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text(g.lesson == null
                    ? 'مش لاقي الدرس ده (${g.qs.length} سؤال). صحّح العنوان أو الرابط.'
                    : '${g.valid} سؤال سليم من ${g.qs.length}${g.hasExam ? '  •  عنده اختبار بالفعل (هيتخطى)' : ''}'),
              ),
            ),
          const SizedBox(height: 8),
          FilledButton(
              onPressed: (_busy || todo == 0) ? null : _save,
              child: Text('حفظ $todo اختبار')),
        ],
      ]),
    );
  }
}
