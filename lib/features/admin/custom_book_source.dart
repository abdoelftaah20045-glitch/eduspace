import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/tenant.dart';

bool _ar(BuildContext c) => Localizations.localeOf(c).languageCode == 'ar';

/// A book library the admin plugs in without a new app build.
/// Only JSON search APIs are supported. Paths are dotted, like `docs.0.title`.
class CustomBookSource {
  CustomBookSource({
    required this.name,
    required this.url,
    this.results = '',
    this.title = 'title',
    this.author = '',
    this.cover = '',
    this.link = 'url',
    this.pdf = '',
    this.license = '',
    this.licenseFixed = '',
    this.language = '',
    this.languageFixed = '',
  });

  String name;
  String url; // contains {q}
  String results;
  String title;
  String author;
  String cover;
  String link;
  String pdf;
  String license;
  String licenseFixed;
  String language;
  String languageFixed;

  Map<String, dynamic> toJson() => {
        'name': name,
        'url': url,
        'results': results,
        'title': title,
        'author': author,
        'cover': cover,
        'link': link,
        'pdf': pdf,
        'license': license,
        'licenseFixed': licenseFixed,
        'language': language,
        'languageFixed': languageFixed,
      };

  factory CustomBookSource.fromJson(Map m) {
    String g(String k, [String d = '']) => (m[k] ?? d).toString();
    return CustomBookSource(
      name: g('name'),
      url: g('url'),
      results: g('results'),
      title: g('title', 'title'),
      author: g('author'),
      cover: g('cover'),
      link: g('link', 'url'),
      pdf: g('pdf'),
      license: g('license'),
      licenseFixed: g('licenseFixed'),
      language: g('language'),
      languageFixed: g('languageFixed'),
    );
  }

  static SupabaseClient get _c => Supabase.instance.client;

  static Future<List<CustomBookSource>> load() async {
    try {
      final st = await _c
          .from('tenant_settings')
          .select('setting_value')
          .eq('tenant_id', TenantContext.id)
          .eq('setting_key', 'book_sources')
          .maybeSingle();
      final v = st?['setting_value'];
      if (v is Map && v['sources'] is List) {
        return [
          for (final e in v['sources'] as List)
            if (e is Map) CustomBookSource.fromJson(e)
        ];
      }
    } catch (_) {}
    return [];
  }

  static Future<void> save(List<CustomBookSource> list) async {
    await _c.from('tenant_settings').upsert({
      'tenant_id': TenantContext.id,
      'setting_key': 'book_sources',
      'setting_value': {'sources': list.map((e) => e.toJson()).toList()},
    }, onConflict: 'tenant_id,setting_key');
  }

  static dynamic dig(dynamic node, String path) {
    final p = path.trim();
    if (p.isEmpty) return node;
    var cur = node;
    for (final part in p.split('.')) {
      if (cur is Map) {
        cur = cur[part];
      } else if (cur is List) {
        final i = int.tryParse(part);
        cur = (i != null && i >= 0 && i < cur.length) ? cur[i] : null;
      } else {
        return null;
      }
      if (cur == null) return null;
    }
    return cur;
  }

  static String _str(dynamic v) {
    if (v == null) return '';
    if (v is List) return v.map((e) => e.toString()).join(', ');
    return v.toString();
  }

  /// Runs a search and returns mapped rows: title, author, cover, link,
  /// pdf, license, language. Throws on network or format errors.
  Future<List<Map<String, String>>> search(String q) async {
    final u = url.replaceAll('{q}', Uri.encodeQueryComponent(q));
    final uri = Uri.parse(u);
    if (uri.scheme != 'https') throw Exception('https only');
    final r = await http.get(uri, headers: {
      'Accept': 'application/json',
    }).timeout(const Duration(seconds: 25));
    if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
    final root = jsonDecode(utf8.decode(r.bodyBytes));
    final list = dig(root, results);
    if (list is! List) throw Exception('results path is not a list');
    final out = <Map<String, String>>[];
    for (final e in list.take(80)) {
      final t = _str(dig(e, title));
      final l = _str(dig(e, link));
      final p = pdf.isEmpty ? '' : _str(dig(e, pdf));
      if (t.isEmpty || (l.isEmpty && p.isEmpty)) continue;
      out.add({
        'title': t,
        'author': author.isEmpty ? '' : _str(dig(e, author)),
        'cover': cover.isEmpty ? '' : _str(dig(e, cover)),
        'link': p.isNotEmpty ? p : l,
        'license': licenseFixed.isNotEmpty
            ? licenseFixed
            : (license.isEmpty ? '' : _str(dig(e, license))),
        'language': languageFixed.isNotEmpty
            ? languageFixed
            : (language.isEmpty ? '' : _str(dig(e, language))),
      });
    }
    return out;
  }
}

/// Form to add or edit a custom source, with a Test button.
class CustomSourceEditor extends StatefulWidget {
  const CustomSourceEditor({super.key, this.source});
  final CustomBookSource? source;

  @override
  State<CustomSourceEditor> createState() => _CustomSourceEditorState();
}

class _CustomSourceEditorState extends State<CustomSourceEditor> {
  late final Map<String, TextEditingController> _c;
  String _test = '';
  bool _busy = false;

  static const _fields = [
    ('name', 'Name'),
    ('url', 'Search URL (https, with {q})'),
    ('results', 'Results list path (empty if the answer is the list)'),
    ('title', 'Title path'),
    ('author', 'Author path (optional)'),
    ('cover', 'Cover URL path (optional)'),
    ('link', 'Book page link path'),
    ('pdf', 'PDF link path (optional, preferred)'),
    ('license', 'Licence path (optional)'),
    ('licenseFixed', 'Or one fixed licence text for all books'),
    ('language', 'Language path (optional)'),
    ('languageFixed', 'Or fixed language: ar or en'),
  ];

  @override
  void initState() {
    super.initState();
    final j = (widget.source ?? CustomBookSource(name: '', url: '')).toJson();
    _c = {
      for (final f in _fields)
        f.$1: TextEditingController(text: (j[f.$1] ?? '').toString())
    };
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  CustomBookSource _build() => CustomBookSource.fromJson(
      {for (final e in _c.entries) e.key: e.value.text.trim()});

  Future<void> _runTest() async {
    final s = _build();
    setState(() {
      _busy = true;
      _test = '';
    });
    try {
      final rows = await s.search('nursing');
      setState(() => _test = rows.isEmpty
          ? 'Connected, but 0 books mapped. Check the results path and the title/link paths.'
          : '${rows.length} books. First:\n' +
              rows
                  .take(3)
                  .map((r) =>
                      '- ${r['title']} | ${r['author']} | ${r['license']} | ${r['link']}')
                  .join('\n'));
    } catch (e) {
      setState(() => _test = 'Failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final ar = _ar(context);
    final s = _build();
    if (s.name.isEmpty || !s.url.startsWith('https://') || !s.url.contains('{q}')) {
      setState(() => _test = ar
          ? 'الاسم مطلوب والرابط لازم يبدأ بـ https ويحتوي {q}'
          : 'Name is required and the URL must start with https and contain {q}');
      return;
    }
    Navigator.of(context).pop(s);
  }

  @override
  Widget build(BuildContext context) {
    final ar = _ar(context);
    return Scaffold(
      appBar: AppBar(title: Text(ar ? 'مصدر كتب مخصص' : 'Custom book source')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              ar
                  ? 'تنبيه قانوني: أضف فقط مكتبات ذات رخصة مفتوحة أو ملكية عامة أو بإذن الناشر. ممنوع مواقع القرصنة أو المكتبات الظلية أو سحب الصفحات. المفاتيح الخاصة لا تُحفظ هنا (تظهر للطلاب).'
                  : 'Legal notice: add only libraries that are open-licensed, public domain or publisher-permitted. No pirate or shadow libraries, no scraping. Do not put private API keys here (students can read this setting).',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(height: 8),
          for (final f in _fields)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: TextField(
                controller: _c[f.$1],
                decoration: InputDecoration(labelText: f.$2, isDense: true),
              ),
            ),
          const SizedBox(height: 10),
          Row(children: [
            OutlinedButton(
                onPressed: _busy ? null : _runTest,
                child: Text(ar ? 'اختبار' : 'Test')),
            const SizedBox(width: 10),
            FilledButton(
                onPressed: _busy ? null : _save,
                child: Text(ar ? 'حفظ' : 'Save')),
          ]),
          if (_busy) const LinearProgressIndicator(),
          if (_test.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: SelectableText(_test, style: const TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }
}
