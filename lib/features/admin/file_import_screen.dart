import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/bg_guard.dart';
import '../../core/l10n.dart';
import 'data/admin_repo.dart';
import 'data/admin_tools_repo.dart';
import 'playlist_import.dart';
import 'youtube_import_screen.dart';

const kImportTemplate =
    'category,playlist_url,title,language,level\n'
    'Programming,https://www.youtube.com/playlist?list=PLxxxxxxxxxxxx,,ar,beginner\n'
    'Programming,https://www.youtube.com/playlist?list=PLyyyyyyyyyyyy,My custom title,en,advanced\n'
    'Design,https://www.youtube.com/playlist?list=PLzzzzzzzzzzzz,,,\n';

class _Row {
  _Row(this.line, this.category, this.url, this.title, this.language,
      this.level);
  final int line;
  final String category;
  final String url;
  final String title;
  final String language;
  final String level;
  String status = 'wait'; // wait, run, ok, skip, err
  String note = '';
}

/// Reads a CSV or XLSX file into rows of cells.
List<List<String>> parseTable(String name, List<int> bytes) {
  if (name.toLowerCase().endsWith('.xlsx')) return _parseXlsx(bytes);
  var text = utf8.decode(bytes, allowMalformed: true);
  if (text.startsWith('\uFEFF')) text = text.substring(1);
  return _parseCsv(text);
}

List<List<String>> _parseCsv(String text) {
  final first = text.split('\n').firstWhere((l) => l.trim().isNotEmpty,
      orElse: () => '');
  var d = ',';
  if (first.contains('\t')) {
    d = '\t';
  } else if (';'.allMatches(first).length > ','.allMatches(first).length) {
    d = ';';
  }
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var q = false;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (q) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          q = false;
        }
      } else {
        cell.write(c);
      }
    } else if (c == '"') {
      q = true;
    } else if (c == d) {
      row.add(cell.toString().trim());
      cell.clear();
    } else if (c == '\n' || c == '\r') {
      if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(cell.toString().trim());
      cell.clear();
      if (row.any((x) => x.isNotEmpty)) rows.add(row);
      row = <String>[];
    } else {
      cell.write(c);
    }
  }
  row.add(cell.toString().trim());
  if (row.any((x) => x.isNotEmpty)) rows.add(row);
  return rows;
}

String _unxml(String s) => s
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'");

int _colIndex(String ref) {
  var n = 0;
  for (final u in ref.codeUnits) {
    if (u >= 65 && u <= 90) {
      n = n * 26 + (u - 64);
    } else {
      break;
    }
  }
  return n - 1;
}

List<List<String>> _parseXlsx(List<int> bytes) {
  final zip = ZipDecoder().decodeBytes(bytes);
  String read(String path) {
    for (final f in zip) {
      if (f.name == path) {
        return utf8.decode(f.content as List<int>, allowMalformed: true);
      }
    }
    return '';
  }

  final shared = <String>[];
  final sst = read('xl/sharedStrings.xml');
  for (final m in RegExp(r'<si>([\s\S]*?)</si>').allMatches(sst)) {
    final t = RegExp(r'<t[^>]*>([\s\S]*?)</t>')
        .allMatches(m.group(1)!)
        .map((x) => _unxml(x.group(1)!))
        .join();
    shared.add(t);
  }
  var sheet = read('xl/worksheets/sheet1.xml');
  if (sheet.isEmpty) {
    for (final f in zip) {
      if (f.name.startsWith('xl/worksheets/sheet') &&
          f.name.endsWith('.xml')) {
        sheet = utf8.decode(f.content as List<int>, allowMalformed: true);
        break;
      }
    }
  }
  final rows = <List<String>>[];
  for (final r in RegExp(r'<row[^>]*>([\s\S]*?)</row>').allMatches(sheet)) {
    final cells = <String>[];
    for (final c in RegExp(r'<c ([^>]*?)(?:/>|>([\s\S]*?)</c>)')
        .allMatches(r.group(1)!)) {
      final attrs = c.group(1)!;
      final body = c.group(2) ?? '';
      final ref = RegExp(r'r="([A-Z]+)\d+"').firstMatch(attrs)?.group(1);
      final idx = ref == null ? cells.length : _colIndex(ref);
      while (cells.length <= idx) {
        cells.add('');
      }
      final type = RegExp(r't="(\w+)"').firstMatch(attrs)?.group(1);
      var v = '';
      if (type == 's') {
        final i = int.tryParse(
            RegExp(r'<v>([\s\S]*?)</v>').firstMatch(body)?.group(1) ?? '');
        if (i != null && i < shared.length) v = shared[i];
      } else if (type == 'inlineStr') {
        v = _unxml(RegExp(r'<t[^>]*>([\s\S]*?)</t>')
                .firstMatch(body)
                ?.group(1) ??
            '');
      } else {
        v = _unxml(
            RegExp(r'<v>([\s\S]*?)</v>').firstMatch(body)?.group(1) ?? '');
      }
      cells[idx] = v.trim();
    }
    if (cells.any((x) => x.isNotEmpty)) rows.add(cells);
  }
  return rows;
}

String _normLevel(String v) {
  final t = v.trim().toLowerCase();
  if (t.isEmpty) return '';
  if (t.contains('begin') || t.contains('مبتد')) return 'beginner';
  if (t.contains('inter') || t.contains('متوسط')) return 'intermediate';
  if (t.contains('adv') || t.contains('متقدم')) return 'advanced';
  if (t.contains('all') || t.contains('كل')) return 'all_levels';
  return '';
}

String _normLang(String v) {
  final t = v.trim().toLowerCase();
  if (t.isEmpty) return '';
  if (t == 'ar' || t.contains('arab') || t.contains('عرب')) return 'ar';
  if (t == 'en' || t.contains('engl') || t.contains('انجل') || t.contains('إنجل')) {
    return 'en';
  }
  if (t == 'fr' || t.contains('fren') || t.contains('فرن')) return 'fr';
  if (t == 'es' || t.contains('span') || t.contains('اسب') || t.contains('إسب')) {
    return 'es';
  }
  if (t == 'de' || t.contains('germ') || t.contains('الما') || t.contains('ألما')) {
    return 'de';
  }
  return '';
}

class FileImportScreen extends StatefulWidget {
  const FileImportScreen({super.key});

  @override
  State<FileImportScreen> createState() => _FileImportScreenState();
}

class _FileImportScreenState extends State<FileImportScreen> {
  final List<_Row> _rows = [];
  String _fileName = '';
  String _error = '';
  bool _running = false;
  bool _withDesc = true;
  int _done = 0;
  String _progress = '';

  Future<void> _pick() async {
    final s = S.of(context);
    final picked = await FilePicker.pickFiles();
    if (picked.isEmpty || !mounted) return;
    final f = picked.first;
    try {
      final table = parseTable(f.name, await f.readAsBytes());
      if (table.isEmpty) throw 'empty';
      var cCat = 0, cUrl = 1, cTitle = -1, cLang = -1, cLevel = -1;
      var start = 0;
      final head = table.first.map((x) => x.toLowerCase().trim()).toList();
      int find(List<String> keys) =>
          head.indexWhere((h) => keys.any((k) => h == k || h.contains(k)));
      final hasHead = !head.any((h) => h.contains('http'));
      if (hasHead) {
        start = 1;
        final a = find(['category', 'section', 'تصنيف', 'قسم', 'فئة']);
        final b = find(['playlist', 'url', 'link', 'رابط']);
        if (a >= 0) cCat = a;
        if (b >= 0) cUrl = b;
        cTitle = find(['title', 'name', 'عنوان', 'اسم']);
        cLang = find(['lang', 'لغة']);
        cLevel = find(['level', 'مستوى']);
      }
      String at(List<String> r, int i) =>
          i >= 0 && i < r.length ? r[i].trim() : '';
      final rows = <_Row>[];
      var lastCat = '';
      for (var i = start; i < table.length; i++) {
        final r = table[i];
        var cat = at(r, cCat);
        if (cat.isNotEmpty && !cat.toLowerCase().contains('http')) {
          lastCat = cat;
        } else if (cat.toLowerCase().contains('http')) {
          cat = '';
        }
        var url = at(r, cUrl);
        if (!url.toLowerCase().contains('list=') &&
            !url.toLowerCase().contains('http')) {
          // a category-only row: remember it for the rows below
          if (url.isEmpty && cat.isNotEmpty) lastCat = cat;
          if (url.isEmpty) continue;
        }
        rows.add(_Row(
            i + 1,
            cat.isNotEmpty ? cat : lastCat,
            url,
            at(r, cTitle),
            _normLang(at(r, cLang)),
            _normLevel(at(r, cLevel))));
      }
      setState(() {
        _rows
          ..clear()
          ..addAll(rows);
        _fileName = f.name;
        _error = rows.isEmpty ? s.t('fi_empty') : '';
        _done = 0;
      });
    } catch (e) {
      setState(() => _error = '${s.t('fi_bad_file')}: $e');
    }
  }

  Future<void> _copyTemplate() async {
    await Clipboard.setData(const ClipboardData(text: kImportTemplate));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(S.of(context).t('fi_copied'))));
  }

  Future<bool> _exists(String listId) async {
    final r = await Supabase.instance.client
        .from('lessons')
        .select('id')
        .ilike('media_url', '%list=$listId%')
        .limit(1);
    return (r as List).isNotEmpty;
  }

  Future<void> _run() async {
    final s = S.of(context);
    setState(() {
      _running = true;
      _done = 0;
    });
    final title = s.t('bg_import_running');
    await BgGuard.begin(title, '0/${_rows.length}');
    final known = <String>{};
    try {
      for (final c in await AdminToolsRepository.fetchCategories()) {
        if (c['kind'] == 'category') {
          known.add((c['name'] as String).trim().toLowerCase());
        }
      }
    } catch (_) {}
    var okCount = 0;
    var errCount = 0;
    for (final row in _rows) {
      if (row.status == 'ok' || row.status == 'skip') {
        _done++;
        continue;
      }
      if (!mounted) break;
      setState(() {
        row.status = 'run';
        row.note = '';
      });
      try {
        final id = YtImporter.listId(row.url);
        if (id == null) throw s.t('fi_bad_link');
        final p = await YtImporter.fetchPlaylist(id);
        if (row.title.isNotEmpty) p.title = row.title;
        if (row.category.isNotEmpty &&
            !known.contains(row.category.toLowerCase())) {
          await AdminToolsRepository.addCategory('category', row.category);
          known.add(row.category.toLowerCase());
        }
        final added = await PlaylistImport.run(
          p,
          s: s,
          withDesc: _withDesc,
          field: row.category,
          level: row.level,
          language: row.language,
          onProgress: (t) {
            if (mounted) setState(() => _progress = t);
            BgGuard.update(title,
                '$_done/${_rows.length} - ${s.t('bg_err_word')}: $errCount\n$t');
          },
        );
        if (added < 0) {
          row.status = 'skip';
          row.note = s.t('fi_already');
        } else {
          row.status = 'ok';
          row.note = '${p.title} ($added)';
          okCount++;
        }
      } catch (e) {
        final t = '$e';
        row.status = 'err';
        row.note = t.length > 160 ? t.substring(0, 160) : t;
        errCount++;
      }
      _done++;
      if (mounted) setState(() {});
    }
    await BgGuard.end();
    await BgGuard.notify(4712, s.t('bg_import_done'),
        '${s.t('bg_done_word')}: $okCount - ${s.t('bg_err_word')}: $errCount');
    if (mounted) {
      setState(() {
        _running = false;
        _progress = '';
      });
    }
  }

  String _report() {
    final b = StringBuffer();
    for (final r in _rows) {
      b.writeln('${r.line},${r.status},${r.category},${r.url},${r.note}');
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final ok = _rows.where((r) => r.status == 'ok').length;
    final skip = _rows.where((r) => r.status == 'skip').length;
    final err = _rows.where((r) => r.status == 'err').length;
    final pending = _rows.where((r) => r.status == 'wait' || r.status == 'err');
    return Scaffold(
      appBar: AppBar(title: Text(s.t('fi_title'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(s.t('fi_hint')),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.icon(
                onPressed: _running ? null : _pick,
                icon: const Icon(Icons.upload_file),
                label: Text(s.t('fi_pick'))),
            OutlinedButton.icon(
                onPressed: _copyTemplate,
                icon: const Icon(Icons.copy),
                label: Text(s.t('fi_template'))),
          ]),
          SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _withDesc,
              onChanged: _running ? null : (v) => setState(() => _withDesc = v),
              title: Text(s.t('yt_with_desc')),
              subtitle: Text(s.t('yt_with_desc_sub'))),
          if (_error.isNotEmpty)
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(_error,
                    style: TextStyle(color: Theme.of(context).colorScheme.error))),
          if (_rows.isNotEmpty) ...[
            Text('$_fileName: ${_rows.length} ${s.t('fi_rows')}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            LinearProgressIndicator(
                value: _rows.isEmpty ? 0 : _done / _rows.length),
            const SizedBox(height: 4),
            Text(
                '$_done/${_rows.length}  ${s.t('fi_ok')}: $ok  ${s.t('fi_skipped')}: $skip  ${s.t('fi_errors')}: $err'),
            if (_progress.isNotEmpty)
              Text(_progress, style: const TextStyle(color: Colors.black54)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                  child: FilledButton(
                      onPressed:
                          _running || pending.isEmpty ? null : _run,
                      child: Text(err > 0 && ok + skip + err == _rows.length
                          ? s.t('fi_retry')
                          : s.t('yt_import_btn')))),
              const SizedBox(width: 8),
              OutlinedButton(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: _report()));
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(s.t('fi_copied'))));
                  },
                  child: Text(s.t('fi_report'))),
            ]),
            const Divider(height: 24),
            for (final r in _rows)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: switch (r.status) {
                  'ok' => const Icon(Icons.check_circle, color: Colors.green),
                  'skip' => const Icon(Icons.skip_next, color: Colors.orange),
                  'err' => const Icon(Icons.error, color: Colors.red),
                  'run' => const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  _ => const Icon(Icons.schedule, color: Colors.grey),
                },
                title: Text(r.category.isEmpty ? '-' : r.category),
                subtitle: Text(
                    r.note.isEmpty ? r.url : '${r.note}\n${r.url}',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis),
              ),
          ],
        ],
      ),
    );
  }
}
