import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/tenant.dart';
import '../library/books_shelf.dart';
import '../library/data/library_repo.dart';


/// Strict rights rule (same as the server): explicit CC0 / CC BY / CC BY-SA /
/// public domain only. NC, ND, unknown, "verify", per-page labels fail.
bool rightsOk(String lic, String? url, String source) {
  if (source.toLowerCase().contains('wikisource')) return false;
  final t = lic.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  final u = (url ?? '').toLowerCase();
  if (RegExp(r'creativecommons\.org/publicdomain/(zero|mark)/').hasMatch(u)) return true;
  if (RegExp(r'creativecommons\.org/licenses/by(-sa)?/').hasMatch(u)) return true;
  if (u.contains('creativecommons.org/')) return false;
  if (RegExp(r'creativecommons\.org/publicdomain/(zero|mark)/').hasMatch(t) ||
      RegExp(r'creativecommons\.org/licenses/by(-sa)?/').hasMatch(t)) return true;
  if (t.isEmpty ||
      RegExp(r'non ?-?commercial|no ?-?deriv|\bnc\b|\bnd\b|by-nc|by-nd|all rights|unknown|review|licen[cs]e per|verify|/|\bor\b').hasMatch(t)) {
    return false;
  }
  return RegExp(r'^(cc0( 1\.0)?|public domain( \(cc0\))?|public domain mark( 1\.0)?)$').hasMatch(t) ||
      RegExp(r'^cc[ -]by([ -]sa)?( [0-9.]+)?$').hasMatch(t) ||
      RegExp(r'^creative commons attribution([ -]share ?alike)?( licen[cs]e)?( [0-9.]+)?$').hasMatch(t);
}

/// Admin: books waiting in status 'review'. Filter by source / licence, then
/// approve or delete one book or everything in the current filter.
class AdminBooksReviewScreen extends StatefulWidget {
  const AdminBooksReviewScreen({super.key});

  @override
  State<AdminBooksReviewScreen> createState() => _AdminBooksReviewScreenState();
}

class _AdminBooksReviewScreenState extends State<AdminBooksReviewScreen> {
  SupabaseClient get _c => Supabase.instance.client;
  List<LibraryItem> _items = [];
  Map<String, int> _sources = {};
  Map<String, int> _licenses = {};
  int _total = 0;
  String? _source;
  String? _license;
  String _q = '';
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load(counts: true);
  }

  dynamic _filter(dynamic q) {
    var r = q.eq('tenant_id', TenantContext.id).eq('kind', 'book').eq('status', 'review');
    if (_source != null) r = r.eq('source', _source!);
    if (_license != null) r = r.eq('license', _license!);
    final safe = _q.replaceAll(',', ' ').replaceAll('(', ' ').replaceAll(')', ' ').trim();
    if (safe.isNotEmpty) r = r.ilike('title', '%$safe%');
    return r;
  }

  Future<void> _load({bool counts = false}) async {
    setState(() => _loading = true);
    try {
      if (counts) {
        final rows = await _c
            .from('library_items')
            .select('source, license')
            .eq('tenant_id', TenantContext.id)
            .eq('kind', 'book')
            .eq('status', 'review')
            .limit(5000);
        final src = <String, int>{};
        final lic = <String, int>{};
        for (final r in rows) {
          final s = ((r['source'] as String?) ?? '').trim();
          final l = ((r['license'] as String?) ?? '').trim();
          src[s] = (src[s] ?? 0) + 1;
          lic[l] = (lic[l] ?? 0) + 1;
        }
        _sources = src;
        _licenses = lic;
        _total = rows.length;
      }
      final rows = await _filter(_c.from('library_items').select('*')).order('created_at', ascending: false).limit(100);
      _items = [for (final r in rows as List) LibraryItem.fromMap(Map<String, dynamic>.from(r as Map))];
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }


  Future<void> _auto() async {
    setState(() => _busy = true);
    try {
      final ok = <String>[];
      final bySrc = <String, int>{};
      var total = 0;
      for (var from = 0; from < 10000; from += 1000) {
        final rows = await _c
            .from('library_items')
            .select('id, source, license, rights_url')
            .eq('tenant_id', TenantContext.id)
            .eq('kind', 'book')
            .eq('status', 'review')
            .order('id')
            .range(from, from + 999);
        for (final r in rows) {
          total++;
          final src = ((r['source'] as String?) ?? '').trim();
          if (rightsOk((r['license'] as String?) ?? '', r['rights_url'] as String?, src)) {
            ok.add(r['id'] as String);
            bySrc[src] = (bySrc[src] ?? 0) + 1;
          }
        }
        if (rows.length < 1000) break;
      }
      if (!mounted) return;
      final go = await _confirm(
        'مراجعة تلقائية',
        'تحت المراجعة: $total\nآمن وهيتنشر: ${ok.length}\nهيفضل تحت المراجعة: ${total - ok.length}\n'
        '${bySrc.entries.map((e) => '${e.key.isEmpty ? '(بدون)' : e.key}: ${e.value}').join('\n')}\n\n'
        'الآمن = ترخيص صريح CC0 أو CC BY أو CC BY-SA أو ملكية عامة فقط. NC/ND والمجهول وويكيسورس بيفضلوا تحت المراجعة. مفيش حذف.',
      );
      if (!go || ok.isEmpty) return;
      for (var i = 0; i < ok.length; i += 150) {
        await _c.from('library_items').update({'status': 'published'}).inFilter('id', ok.sublist(i, i + 150 > ok.length ? ok.length : i + 150));
      }
      _snack('تم نشر ${ok.length} كتاب');
    } catch (_) {
      _snack('حصل خطأ');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _load(counts: true);
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<bool> _confirm(String title, String body) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تأكيد')),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _one(LibraryItem b, bool approve) async {
    try {
      if (approve) {
        await _c.from('library_items').update({'status': 'published'}).eq('id', b.id);
      } else {
        await _c.from('library_items').delete().eq('id', b.id);
      }
      _items.removeWhere((x) => x.id == b.id);
      if (mounted) setState(() {});
    } catch (_) {
      _snack('حصل خطأ');
    }
  }

  Future<void> _all(bool approve) async {
    final count = (_source == null && _license == null && _q.isEmpty)
        ? _total
        : null;
    final what = [
      if (_source != null) 'المصدر: ${_source!.isEmpty ? '(بدون)' : _source}',
      if (_license != null) 'الترخيص: ${_license!.isEmpty ? '(بدون)' : _license}',
      if (_q.isNotEmpty) 'بحث: $_q',
      if (count != null) 'كل الكتب تحت المراجعة ($count)',
    ].join('\n');
    final ok = await _confirm(
      approve ? 'نشر كل الكتب المعروضة؟' : 'حذف كل الكتب المعروضة؟',
      '$what\n\n${approve ? 'هتظهر للطلاب. اتأكد إن ترخيصها يسمح.' : 'هيتم حذف روابطها نهائيًا.'}',
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      final q = approve
          ? _filter(_c.from('library_items').update({'status': 'published'}))
          : _filter(_c.from('library_items').delete());
      await q;
      _snack(approve ? 'تم النشر' : 'تم الحذف');
    } catch (_) {
      _snack('حصل خطأ');
    }
    if (mounted) setState(() => _busy = false);
    await _load(counts: true);
  }

  Widget _chips(String label, Map<String, int> m, String? sel, void Function(String?) on) {
    final keys = m.keys.toList()..sort((a, b) => m[b]!.compareTo(m[a]!));
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: ChoiceChip(label: Text('$label: الكل'), selected: sel == null, onSelected: (_) => on(null)),
          ),
          for (final k in keys.take(14))
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: ChoiceChip(
                label: Text('${k.isEmpty ? '(بدون)' : (k.length > 28 ? k.substring(0, 28) : k)} (${m[k]})'),
                selected: sel == k,
                onSelected: (_) => on(k),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('مراجعة الكتب ($_total)')),
      body: Column(children: [
        if (_busy) const LinearProgressIndicator(),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
          child: TextField(
            decoration: const InputDecoration(
                hintText: 'ابحث بالاسم', isDense: true, border: OutlineInputBorder()),
            onSubmitted: (v) {
              _q = v;
              _load();
            },
          ),
        ),
        _chips('المصدر', _sources, _source, (v) {
          _source = v;
          _load();
        }),
        _chips('الترخيص', _licenses, _license, (v) {
          _license = v;
          _load();
        }),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.tonal(
                onPressed: _busy ? null : _auto, child: const Text('مراجعة تلقائية (نشر الآمن فقط)')),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
          child: Row(children: [
            Expanded(
              child: FilledButton(
                  onPressed: _busy ? null : () => _all(true), child: const Text('نشر كل المعروض')),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                  onPressed: _busy ? null : () => _all(false), child: const Text('حذف كل المعروض')),
            ),
          ]),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _items.isEmpty
                  ? const Center(child: Text('مفيش كتب تحت المراجعة'))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(4, 0, 4, 40),
                      itemCount: _items.length,
                      itemBuilder: (c, i) {
                        final b = _items[i];
                        return ListTile(
                          dense: true,
                          title: Text(b.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                              [b.source, b.license].where((x) => x.isNotEmpty).join(' · '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(
                                icon: const Icon(Icons.check_circle_outline),
                                onPressed: () => _one(b, true)),
                            IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _one(b, false)),
                          ]),
                          onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => BookReaderScreen(item: b))),
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}
