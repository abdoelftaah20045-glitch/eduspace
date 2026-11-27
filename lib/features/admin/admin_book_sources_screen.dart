import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../library/data/library_repo.dart';

bool _ar(BuildContext c) => Localizations.localeOf(c).languageCode == 'ar';

class _Found {
  _Found({
    required this.title,
    required this.author,
    required this.link,
    required this.cover,
    required this.license,
    required this.source,
    required this.lang,
  });
  final String title;
  final String author;
  final String link;
  final String? cover;
  final String license;
  final String source;
  final String lang;
  bool picked = false;
}

/// Admin: search open sources and import books as link-only entries.
/// Only open-licensed or public-domain items are listed. Nothing is stored.
class AdminBookSourcesScreen extends StatefulWidget {
  const AdminBookSourcesScreen({super.key});

  @override
  State<AdminBookSourcesScreen> createState() => _AdminBookSourcesScreenState();
}

class _AdminBookSourcesScreenState extends State<AdminBookSourcesScreen> {
  final _q = TextEditingController();
  final _cat = TextEditingController();
  String _source = 'archive';
  String _lang = 'any';
  bool _busy = false;
  String? _err;
  List<_Found> _res = const [];

  @override
  void dispose() {
    _q.dispose();
    _cat.dispose();
    super.dispose();
  }

  String _licName(String url) {
    final u = url.toLowerCase();
    if (u.contains('publicdomain') || u.contains('/zero/')) return 'Public domain';
    final m = RegExp(r'licenses/([a-z\-]+)/([0-9.]+)').firstMatch(u);
    if (m != null) return 'CC ${m.group(1)!.toUpperCase()} ${m.group(2)}';
    return 'Creative Commons';
  }

  Future<void> _search() async {
    final q = _q.text.replaceAll(RegExp(r'[^\w\u0600-\u06FF\s\-]'), ' ').trim();
    if (q.isEmpty) return;
    setState(() {
      _busy = true;
      _err = null;
      _res = const [];
    });
    try {
      final out = <_Found>[];
      if (_source == 'archive') {
        var lq =
            '(title:($q) OR subject:($q)) AND mediatype:texts AND (licenseurl:*creativecommons* OR licenseurl:*publicdomain*)';
        if (_lang == 'en') lq += ' AND language:(eng OR English)';
        if (_lang == 'ar') lq += ' AND language:(ara OR Arabic)';
        final uri = Uri.https('archive.org', '/advancedsearch.php', {
          'q': lq,
          'fl[]': ['identifier', 'title', 'creator', 'language', 'licenseurl'],
          'rows': '60',
          'sort[]': 'downloads desc',
          'output': 'json',
        });
        final r = await http.get(uri).timeout(const Duration(seconds: 25));
        final docs = (jsonDecode(r.body)['response']['docs'] as List);
        for (final d in docs) {
          final id = d['identifier'].toString();
          final cr = d['creator'];
          final lang = d['language'];
          out.add(_Found(
            title: (d['title'] is List ? (d['title'] as List).first : d['title'])
                .toString(),
            author: cr is List ? cr.join(', ') : (cr ?? '').toString(),
            link: 'https://archive.org/details/$id',
            cover: 'https://archive.org/services/img/$id',
            license: _licName(
                (d['licenseurl'] is List
                        ? (d['licenseurl'] as List).first
                        : d['licenseurl'] ?? '')
                    .toString()),
            source: 'archive.org',
            lang: lang is List ? lang.join(',') : (lang ?? '').toString(),
          ));
        }
      } else if (_source == 'wikisource') {
        final host = _lang == 'ar' ? 'ar.wikisource.org' : 'en.wikisource.org';
        final uri = Uri.https(host, '/w/api.php', {
          'action': 'query',
          'list': 'search',
          'srsearch': q,
          'srnamespace': '0',
          'srlimit': '40',
          'format': 'json',
        });
        final r = await http.get(uri).timeout(const Duration(seconds: 25));
        final rows = (jsonDecode(r.body)['query']['search'] as List);
        for (final d in rows) {
          final t = (d['title'] ?? '').toString();
          out.add(_Found(
            title: t,
            author: 'Wikisource',
            link: 'https://$host/wiki/${Uri.encodeComponent(t.replaceAll(' ', '_'))}',
            cover: null,
            license: 'Public domain / CC BY-SA (Wikisource)',
            source: host,
            lang: _lang == 'ar' ? 'ara' : 'eng',
          ));
        }
      } else if (_source == 'ncbi') {
        final uri = Uri.https('www.ebi.ac.uk',
            '/europepmc/webservices/rest/search', {
          'query': '$q AND OPEN_ACCESS:y AND SRC:MED AND HAS_BOOK:y',
          'format': 'json',
          'resultType': 'core',
          'pageSize': '60',
        });
        final r = await http.get(uri).timeout(const Duration(seconds: 25));
        final rows = (jsonDecode(r.body)['resultList']['result'] as List);
        for (final d in rows) {
          final b = (d['bookid'] ?? '').toString();
          if (b.isEmpty) continue;
          out.add(_Found(
            title: (d['title'] ?? '').toString().replaceAll(RegExp(r'<[^>]*>'), ''),
            author: (d['authorString'] ?? '').toString(),
            link: 'https://www.ncbi.nlm.nih.gov/books/$b/',
            cover: null,
            license: 'NCBI Bookshelf open-access subset (check book page)',
            source: 'ncbi.nlm.nih.gov/books',
            lang: 'eng',
          ));
        }
      } else {
        final uri = Uri.https('openstax.org', '/apps/cms/api/v2/pages/', {
          'type': 'books.Book',
          'fields':
              'title,cover_url,book_state,webview_rex_link,license_name,high_resolution_pdf_url',
          'limit': '200',
        });
        final r = await http.get(uri).timeout(const Duration(seconds: 25));
        final items = (jsonDecode(r.body)['items'] as List);
        final ql = q.toLowerCase();
        for (final d in items) {
          final t = (d['title'] ?? '').toString();
          final link = (d['webview_rex_link'] ?? '').toString();
          if (d['book_state'] != 'live' || link.isEmpty) continue;
          if (!t.toLowerCase().contains(ql) && ql != 'all') continue;
          final pdf = (d['high_resolution_pdf_url'] ?? '').toString();
          out.add(_Found(
            title: t,
            author: 'OpenStax',
            link: pdf.isNotEmpty ? pdf : link,
            cover: null,
            license: (d['license_name'] ?? 'Creative Commons').toString(),
            source: 'openstax.org',
            lang: 'en',
          ));
        }
      }
      if (mounted) setState(() => _res = out);
    } catch (e) {
      if (mounted) setState(() => _err = 'Search failed. Check the internet and try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final picks = _res.where((f) => f.picked).toList();
    if (picks.isEmpty) return;
    setState(() => _busy = true);
    var added = 0;
    var skipped = 0;
    try {
      final all = await LibraryRepository.fetchItems(limit: 500);
      final have = {for (final b in all) b.fileUrl};
      final cat = _cat.text.trim().isEmpty ? 'general' : _cat.text.trim();
      for (final f in picks) {
        if (have.contains(f.link)) {
          skipped++;
          continue;
        }
        try {
          await LibraryRepository.create({
            'title': f.title,
            'file_url': f.link,
            'file_type': 'link',
            'category': cat,
            'author': f.author,
            'cover_url': f.cover,
            'kind': 'book',
            'license': f.license,
            'source': f.source,
            'language': f.lang.toLowerCase().startsWith('ar') ? 'ar' : 'en',
          });
          have.add(f.link);
          added++;
        } catch (_) {
          skipped++;
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          for (final f in picks) {
            f.picked = false;
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(_ar(context)
                ? 'تمت إضافة $added كتاب، وتخطي $skipped'
                : 'Added $added books, skipped $skipped')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ar = _ar(context);
    final n = _res.where((f) => f.picked).length;
    return Scaffold(
      appBar: AppBar(title: Text(ar ? 'مصادر الكتب المفتوحة' : 'Open book sources')),
      floatingActionButton: n == 0
          ? null
          : FloatingActionButton.extended(
              onPressed: _busy ? null : _import,
              icon: const Icon(Icons.add),
              label: Text(ar ? 'استيراد $n' : 'Import $n'),
            ),
      body: Column(
        children: [
          if (_busy) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Internet Archive'),
                  selected: _source == 'archive',
                  onSelected: (_) => setState(() {
                    _source = 'archive';
                    _lang = 'any';
                    _res = const [];
                  }),
                ),
                ChoiceChip(
                  label: const Text('Wikisource'),
                  selected: _source == 'wikisource',
                  onSelected: (_) => setState(() {
                    _source = 'wikisource';
                    _lang = 'en';
                    _res = const [];
                  }),
                ),
                ChoiceChip(
                  label: const Text('NCBI Bookshelf'),
                  selected: _source == 'ncbi',
                  onSelected: (_) => setState(() {
                    _source = 'ncbi';
                    _lang = 'any';
                    _res = const [];
                  }),
                ),
                ChoiceChip(
                  label: const Text('OpenStax'),
                  selected: _source == 'openstax',
                  onSelected: (_) => setState(() {
                    _source = 'openstax';
                    _lang = 'any';
                    _res = const [];
                  }),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _q,
                  onSubmitted: (_) => _search(),
                  decoration: InputDecoration(
                    hintText: _source == 'openstax'
                        ? (ar ? 'nursing أو all' : 'nursing, or all')
                        : (ar ? 'موضوع أو عنوان' : 'Subject or title'),
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                  ),
                ),
              ),
              if (_source == 'archive' || _source == 'wikisource') ...[
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _lang,
                  items: [
                    if (_source == 'archive')
                      DropdownMenuItem(value: 'any', child: Text(ar ? 'كل اللغات' : 'Any')),
                    DropdownMenuItem(value: 'en', child: Text(ar ? 'إنجليزي' : 'English')),
                    DropdownMenuItem(value: 'ar', child: Text(ar ? 'عربي' : 'Arabic')),
                  ],
                  onChanged: (v) => setState(() => _lang = v ?? 'any'),
                ),
              ],
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: TextField(
              controller: _cat,
              decoration: InputDecoration(
                labelText: ar ? 'تصنيف الكتب المستوردة' : 'Category for imported books',
                isDense: true,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
            child: Text(
              ar
                  ? 'تظهر فقط الكتب ذات الرخصة المفتوحة أو الملكية العامة. يُحفظ الرابط والترخيص فقط، بدون أي تخزين.'
                  : 'Only open-licensed or public-domain books are listed. Only the link and licence are saved, nothing is stored.',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ),
          if (_err != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_err!, style: const TextStyle(color: Colors.red)),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: _res.length,
              itemBuilder: (c, i) {
                final f = _res[i];
                return CheckboxListTile(
                  value: f.picked,
                  onChanged: (v) => setState(() => f.picked = v ?? false),
                  title: Text(f.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                      [f.author, f.license, f.lang]
                          .where((x) => x.isNotEmpty)
                          .join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
