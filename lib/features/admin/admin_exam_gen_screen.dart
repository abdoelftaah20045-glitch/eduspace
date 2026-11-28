import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/tenant.dart';

/// Admin: big exams from files. Two modes:
/// import (a PDF/text file that already holds questions with answers) and
/// generate (the AI writes questions from the material). The server keeps
/// working after the app is closed; progress shows here.
class AdminExamGenScreen extends StatefulWidget {
  const AdminExamGenScreen({super.key});

  @override
  State<AdminExamGenScreen> createState() => _AdminExamGenScreenState();
}

class _AdminExamGenScreenState extends State<AdminExamGenScreen> {
  SupabaseClient get _c => Supabase.instance.client;
  final _title = TextEditingController();
  final _total = TextEditingController(text: '100');
  String _mode = 'generate';
  String _lang = 'auto';
  final List<({String name, String mime, String b64, int size})> _files = [];
  List<Map<String, dynamic>> _jobs = [];
  bool _busy = false;
  String? _msg;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _loadJobs();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) => _loadJobs());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _title.dispose();
    _total.dispose();
    super.dispose();
  }

  Future<void> _loadJobs() async {
    try {
      final rows = await _c
          .from('exam_gen_jobs')
          .select('id,title,mode,status,total,made,stop,last_error,paused_until,created_at')
          .eq('tenant_id', TenantContext.id)
          .order('created_at', ascending: false)
          .limit(20);
      if (mounted) setState(() => _jobs = [for (final r in rows) Map<String, dynamic>.from(r)]);
    } catch (_) {
      if (mounted) setState(() => _msg ??= 'شغّل ملف part48 الأول (جدول المهام مش موجود).');
    }
  }

  int get _bytesTotal => _files.fold(0, (a, f) => a + f.size);

  Future<void> _addFile() async {
    try {
      final picked = await FilePicker.pickFiles();
      if (picked.isEmpty || !mounted) return;
      final f = picked.first;
      final bytes = await f.readAsBytes();
      final lower = f.name.toLowerCase();
      if (!(lower.endsWith('.pdf') || lower.endsWith('.txt'))) {
        setState(() => _msg = 'الملف لازم يكون PDF أو TXT. (Word: احفظه PDF، أو استورد Word من "استيراد أسئلة").');
        return;
      }
      if (bytes.length > 12 * 1024 * 1024 || _bytesTotal + bytes.length > 20 * 1024 * 1024) {
        setState(() => _msg = 'الملف كبير (الحد 12 ميجا للملف و20 للكل). قسّمه.');
        return;
      }
      setState(() {
        _msg = null;
        _files.add((name: f.name, mime: lower.endsWith('.pdf') ? 'application/pdf' : 'text/plain', b64: base64Encode(bytes), size: bytes.length));
        if (_title.text.trim().isEmpty) _title.text = f.name.replaceAll(RegExp(r'\.(pdf|txt)$', caseSensitive: false), '');
      });
    } catch (_) {
      if (mounted) setState(() => _msg = 'تعذر قراءة الملف');
    }
  }

  Future<void> _start() async {
    if (_files.isEmpty || _title.text.trim().isEmpty) {
      setState(() => _msg = 'اكتب اسم الامتحان وأضف ملف.');
      return;
    }
    setState(() {
      _busy = true;
      _msg = 'برفع الملفات لجوجل... استنى.';
    });
    try {
      final res = await _c.functions.invoke('exam-gen', body: {
        'action': 'create',
        'tenant_id': TenantContext.id,
        'title': _title.text.trim(),
        'total': int.tryParse(_total.text.trim()) ?? 100,
        'language': _lang,
        'mode': _mode,
        'files': [for (final f in _files) {'name': f.name, 'mime': f.mime, 'b64': f.b64}],
      }).timeout(const Duration(seconds: 115));
      final d = res.data;
      if (d is Map && d['ok'] == true) {
        _files.clear();
        _title.clear();
        _msg = 'اتبدأ. السيرفر بيشتغل لوحده حتى لو قفلت التطبيق. الامتحان هيظهر مسودة في الامتحانات.';
      } else if (d is Map && d['error'] == 'no_key') {
        _msg = 'مفتاح GEMINI_API_KEY مش متسجل في Supabase Secrets.';
      } else if (d is Map && d['error'] == 'not_allowed') {
        _msg = 'مش مسموح (محتاج أدمن) أو شغّل part47.';
      } else {
        _msg = 'فشل: ${d is Map ? (d['detail'] ?? d['error']) : d}';
      }
    } catch (e) {
      _msg = 'فشل الاتصال: $e';
    }
    if (mounted) setState(() => _busy = false);
    await _loadJobs();
  }

  Future<void> _stop(String id) async {
    await _c.from('exam_gen_jobs').update({'stop': true, 'status': 'stopped'}).eq('id', id);
    await _loadJobs();
  }

  Future<void> _resume(String id) async {
    await _c.from('exam_gen_jobs').update({'stop': false, 'status': 'queued', 'paused_until': null, 'busy_until': null}).eq('id', id);
    await _loadJobs();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('امتحان كبير من ملفات')),
      body: ListView(padding: const EdgeInsets.fromLTRB(4, 8, 4, 40), children: [
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: _busy ? null : _start,
              icon: const Icon(Icons.play_arrow),
              label: const Text('ابدأ'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _addFile,
              icon: const Icon(Icons.upload_file),
              label: const Text('إضافة ملف PDF / TXT'),
            ),
          ),
        ]),
        if (_busy) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
        if (_msg != null) Padding(padding: const EdgeInsets.all(8), child: Text(_msg!)),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'generate', label: Text('الذكاء يولّد أسئلة')),
            ButtonSegment(value: 'import', label: Text('استيراد أسئلة جاهزة')),
          ],
          selected: {_mode},
          onSelectionChanged: (v) => setState(() => _mode = v.first),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
          child: Text(
            _mode == 'generate'
                ? 'الذكاء بيكتب أسئلة اختيار من متعدد من محتوى الملفات بس، موزعة على الملف كله.'
                : 'الملف فيه أسئلة جاهزة (ومعاها الإجابات أو مفتاح الإجابة). الذكاء بيستخرجها زي ما هي، بدون تأليف. الأسئلة بـ4 اختيارات بس.',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
        TextField(controller: _title, decoration: const InputDecoration(labelText: 'اسم الامتحان')),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _total,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: _mode == 'generate' ? 'عدد الأسئلة (حتى 600)' : 'أقصى عدد أسئلة (حتى 600)'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: _lang,
              decoration: const InputDecoration(labelText: 'اللغة'),
              items: const [
                DropdownMenuItem(value: 'auto', child: Text('زي الملف')),
                DropdownMenuItem(value: 'ar', child: Text('عربي')),
                DropdownMenuItem(value: 'en', child: Text('English')),
              ],
              onChanged: (v) => setState(() => _lang = v ?? 'auto'),
            ),
          ),
        ]),
        for (var i = 0; i < _files.length; i++)
          ListTile(
            dense: true,
            leading: const Icon(Icons.description_outlined),
            title: Text(_files[i].name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${(_files[i].size / 1024 / 1024).toStringAsFixed(1)} MB'),
            trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _files.removeAt(i))),
          ),
        const Divider(height: 24),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text('المهام (السيرفر شغال حتى لو التطبيق مقفول)', style: TextStyle(fontWeight: FontWeight.w800)),
        ),
        for (final j in _jobs) _jobTile(j),
        if (_jobs.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('مفيش مهام لسه')),
      ]),
    );
  }

  Widget _jobTile(Map<String, dynamic> j) {
    final total = (j['total'] as num?)?.toInt() ?? 1;
    final made = (j['made'] as num?)?.toInt() ?? 0;
    final st = '${j['status']}';
    final stLabel = {
      'queued': 'في الانتظار',
      'running': 'شغال',
      'done': 'تم',
      'error': 'خطأ',
      'stopped': 'متوقف',
    }[st] ?? st;
    final paused = j['paused_until'] != null && DateTime.tryParse('${j['paused_until']}')?.isAfter(DateTime.now()) == true;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${j['title']}  ·  ${j['mode'] == 'import' ? 'استيراد' : 'توليد'}', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          LinearProgressIndicator(value: total > 0 ? (made / total).clamp(0, 1).toDouble() : null),
          const SizedBox(height: 4),
          Text('$made / $total  ·  $stLabel${paused ? ' (وقفة مؤقتة)' : ''}'),
          if ((j['last_error'] ?? '').toString().isNotEmpty)
            Text('${j['last_error']}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
          Row(children: [
            if (st == 'queued' || st == 'running')
              TextButton(onPressed: () => _stop('${j['id']}'), child: const Text('إيقاف')),
            if (st == 'stopped' || st == 'error' || st == 'done')
              TextButton(onPressed: () => _resume('${j['id']}'), child: Text(st == 'done' ? 'كمّل بأسئلة زيادة' : 'استئناف')),
          ]),
        ]),
      ),
    );
  }
}
