import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/html_text.dart';
import '../../core/tenant.dart';

/// Pulls study resources (slides, PDFs, Drive folders, sheets...) out of the
/// video descriptions that the import already stored, and adds them as link
/// attachments under each lesson. No page is fetched: only the stored text is
/// read. Junk (social, own-channel promo, shops, affiliate) is dropped.
class LessonLinks {
  LessonLinks._();

  static const _junk = [
    'youtube.com', 'youtu.be', 'instagram.com', 'facebook.com', 'fb.com', 'fb.me',
    'twitter.com', 'x.com', 'tiktok.com', 't.me', 'telegram.me', 'wa.me',
    'whatsapp.com', 'chat.whatsapp.com', 'linkedin.com', 'snapchat.com',
    'discord.gg', 'discord.com', 'patreon.com', 'paypal.me', 'paypal.com',
    'amazon.', 'amzn.to', 'amzn.com', 'aliexpress.', 'ebay.', 'noon.com',
    'jumia.', 'udemy.com', 'bit.ly', 'tinyurl.com', 'linktr.ee', 'goo.gl',
    'twitch.tv', 'pinterest.com', 'threads.net', 'buymeacoffee.com', 'ko-fi.com',
    'shareasale.', 'awin1.', 'clickbank.', 'go.skimresources.', 'bit.do',
  ];
  static const _good = [
    'drive.google.com', 'docs.google.com', 'sheets.google.com', 'forms.gle',
    'dropbox.com', 'mega.nz', 'mediafire.com', 'github.com', 'gitlab.com',
    'scribd.com', 'slideshare.net', 'notion.so', 'notion.site', 'canva.com',
    'onedrive.live.com', '1drv.ms', 'archive.org', 'wikipedia.org',
  ];
  static final _docExt =
      RegExp(r'\.(pdf|pptx?|docx?|xlsx?|csv|zip|rar|txt)(\?|#|$)', caseSensitive: false);
  static const _words = [
    'ملف', 'ملفات', 'pdf', 'slides', 'slide', 'شرائح', 'سلايد', 'ملخص', 'مذكر',
    'تحميل', 'download', 'resource', 'مصدر', 'مصادر', 'مرفق', 'تمارين', 'تمرين',
    'sheet', 'template', 'قالب', 'نموذج', 'كتاب', 'book', 'notes', 'code', 'كود',
    'رابط الملف', 'المرفقات', 'attachments', 'materials', 'worksheet',
  ];
  static final _url = RegExp(r'https?://[^\s<>"\u0027)\]]+', caseSensitive: false);

  static String _host(String u) {
    final h = (Uri.tryParse(u)?.host ?? '').toLowerCase();
    return h.startsWith('www.') ? h.substring(4) : h;
  }

  static bool _inList(String host, List<String> l) =>
      l.any((d) => host == d || host.endsWith('.$d') || (d.endsWith('.') && host.contains(d)));

  /// (title, url) pairs worth keeping from one description.
  static List<(String, String)> extract(String description) {
    final text = decodeHtml(description);
    final out = <(String, String)>[];
    final seen = <String>{};
    for (final line in text.split(RegExp(r'[\r\n]+'))) {
      for (final m in _url.allMatches(line)) {
        var u = m.group(0)!.replaceAll(RegExp(r'[.,;:!؟،]+$'), '');
        final host = _host(u);
        if (host.isEmpty || !host.contains('.')) continue;
        if (_inList(host, _junk)) continue;
        final before = line.substring(0, m.start).toLowerCase();
        final keep = _inList(host, _good) ||
            _docExt.hasMatch(u) ||
            _words.any((w) => before.contains(w) || u.toLowerCase().contains(w));
        if (!keep) continue;
        if (!seen.add(u)) continue;
        var title = line.substring(0, m.start).replaceAll(RegExp(r'[\s:\-–•*>→]+$'), '').trim();
        if (title.length > 80) title = title.substring(title.length - 80);
        if (title.isEmpty) title = host;
        out.add((title, u));
      }
    }
    return out.take(10).toList();
  }

  static SupabaseClient get _c => Supabase.instance.client;

  /// Lessons already handled (so a link the admin removed never comes back).
  static Future<Set<String>> _done() async {
    try {
      final r = await _c
          .from('tenant_settings')
          .select('setting_value')
          .eq('tenant_id', TenantContext.id)
          .eq('setting_key', 'links_pulled')
          .maybeSingle();
      final v = r?['setting_value'];
      if (v is Map) return {for (final x in (v['ids'] as List? ?? const [])) '$x'};
    } catch (_) {}
    return {};
  }

  static Future<void> _saveDone(Set<String> ids) async {
    await _c.from('tenant_settings').upsert({
      'tenant_id': TenantContext.id,
      'setting_key': 'links_pulled',
      'setting_value': {'ids': ids.toList()},
    }, onConflict: 'tenant_id,setting_key');
  }

  /// Adds links for the given courses' lessons that were not handled before.
  /// Returns (lessons scanned, links added).
  static Future<(int, int)> pull(List<String> courseIds,
      {void Function(int done, int total)? onProgress}) async {
    final done = await _done();
    final lessons = <Map<String, dynamic>>[];
    for (var i = 0; i < courseIds.length; i += 20) {
      final part = courseIds.sublist(i, i + 20 > courseIds.length ? courseIds.length : i + 20);
      final r = await _c
          .from('lessons')
          .select('id, content')
          .inFilter('course_id', part)
          .limit(5000);
      lessons.addAll(List<Map<String, dynamic>>.from(r));
    }
    final todo = [for (final l in lessons) if (!done.contains('${l['id']}')) l];
    var added = 0;
    var n = 0;
    for (final l in todo) {
      final links = extract('${l['content'] ?? ''}');
      if (links.isNotEmpty) {
        try {
          final have = await _c.from('lesson_files').select('file_url').eq('lesson_id', l['id']);
          final urls = {for (final h in have) '${h['file_url']}'};
          final rows = [
            for (final (t, u) in links)
              if (!urls.contains(u))
                {'lesson_id': l['id'], 'name': t, 'file_url': u, 'tenant_id': TenantContext.id}
          ];
          if (rows.isNotEmpty) {
            await _c.from('lesson_files').insert(rows);
            added += rows.length;
          }
        } catch (_) {}
      }
      done.add('${l['id']}');
      n++;
      onProgress?.call(n, todo.length);
    }
    if (todo.isNotEmpty) {
      try {
        await _saveDone(done);
      } catch (_) {}
    }
    return (todo.length, added);
  }
}

/// Admin screen: choose courses, pull the resource links from descriptions.
class AdminLessonLinksScreen extends StatefulWidget {
  const AdminLessonLinksScreen({super.key});

  @override
  State<AdminLessonLinksScreen> createState() => _AdminLessonLinksScreenState();
}

class _AdminLessonLinksScreenState extends State<AdminLessonLinksScreen> {
  List<Map<String, dynamic>>? _courses;
  final Set<String> _picked = {};
  bool _busy = false;
  String _msg = '';
  List<Map<String, dynamic>> _sugg = [];

  Future<void> _loadSugg() async {
    try {
      final r = await Supabase.instance.client
          .from('lesson_link_suggestions')
          .select('id,lesson_id,title,url,lessons(title)')
          .eq('tenant_id', TenantContext.id)
          .order('created_at', ascending: false)
          .limit(200);
      if (mounted) setState(() => _sugg = List<Map<String, dynamic>>.from(r));
    } catch (_) {}
  }

  Future<void> _decide(Map<String, dynamic> x, bool approve) async {
    final c = Supabase.instance.client;
    try {
      if (approve) {
        await c.from('lesson_files').insert({
          'lesson_id': x['lesson_id'],
          'name': x['title'],
          'file_url': x['url'],
          'tenant_id': TenantContext.id,
        });
      }
      await c.from('lesson_link_suggestions').delete().eq('id', x['id']);
      await _loadSugg();
    } catch (_) {}
  }

  Future<void> _decideAll(bool approve) async {
    final list = List<Map<String, dynamic>>.from(_sugg);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(approve ? 'إضافة كل الاقتراحات (${list.length})؟' : 'حذف كل الاقتراحات (${list.length})؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تأكيد')),
        ],
      ),
    );
    if (ok != true) return;
    final c = Supabase.instance.client;
    for (final x in list) {
      try {
        if (approve) {
          await c.from('lesson_files').insert({
            'lesson_id': x['lesson_id'],
            'name': x['title'],
            'file_url': x['url'],
            'tenant_id': TenantContext.id,
          });
        }
        await c.from('lesson_link_suggestions').delete().eq('id', x['id']);
      } catch (_) {}
    }
    await _loadSugg();
  }

  /// Accepts only clearly safe suggestions; doubtful ones stay in the list.
  /// Safe = https link, host not junk, known file host or a document file,
  /// not already attached to that lesson, not repeated in this batch.
  Future<void> _autoAccept() async {
    final c = Supabase.instance.client;
    var ok = 0;
    var kept = 0;
    final seen = <String>{};
    for (final x in List<Map<String, dynamic>>.from(_sugg)) {
      try {
        final u = '${x['url']}'.trim();
        final host = LessonLinks._host(u);
        final safe = u.toLowerCase().startsWith('https://') &&
            host.contains('.') &&
            !LessonLinks._inList(host, LessonLinks._junk) &&
            (LessonLinks._inList(host, LessonLinks._good) || LessonLinks._docExt.hasMatch(u)) &&
            '${x['title'] ?? ''}'.trim().isNotEmpty;
        if (!safe) {
          kept++;
          continue;
        }
        final key = '${x['lesson_id']}|$u';
        final have = await c.from('lesson_files').select('file_url').eq('lesson_id', x['lesson_id']);
        final dup = !seen.add(key) || have.any((h) => '${h['file_url']}' == u);
        if (!dup) {
          await c.from('lesson_files').insert({
            'lesson_id': x['lesson_id'],
            'name': x['title'],
            'file_url': u,
            'tenant_id': TenantContext.id,
          });
          ok++;
        }
        await c.from('lesson_link_suggestions').delete().eq('id', x['id']);
      } catch (_) {
        kept++;
      }
    }
    await _loadSugg();
    if (mounted) setState(() => _msg = 'قبول تلقائي: اتضاف $ok رابط، وفضل $kept للمراجعة.');
  }

  @override
  void initState() {
    super.initState();
    _loadSugg();
    Supabase.instance.client
        .from('courses')
        .select('id,title')
        .eq('tenant_id', TenantContext.id)
        .order('created_at', ascending: false)
        .limit(1000)
        .then((r) {
      if (mounted) setState(() => _courses = List<Map<String, dynamic>>.from(r));
    }).catchError((_) {});
  }

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _msg = '';
    });
    try {
      final r = await LessonLinks.pull(_picked.toList(),
          onProgress: (d, t) => mounted ? setState(() => _msg = '$d / $t') : null);
      if (mounted) setState(() => _msg = 'خلص: اتفحص ${r.$1} درس، واتضاف ${r.$2} رابط.');
    } catch (e) {
      if (mounted) setState(() => _msg = 'حصل خطأ: $e');
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = _courses;
    return Scaffold(
      appBar: AppBar(title: const Text('سحب روابط الملفات من أوصاف الفيديوهات')),
      body: ListView(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 16), children: [
        Row(children: [
          Expanded(
            child: FilledButton(
                onPressed: _busy || _picked.isEmpty ? null : _run,
                child: Text(_busy ? 'جاري السحب...' : 'اسحب الروابط (${_picked.length} كورس)')),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: OutlinedButton(
                onPressed: _sugg.isEmpty ? null : _autoAccept,
                child: Text('مراجعة وقبول تلقائي (${_sugg.length})')),
          ),
        ]),
        if (_msg.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_msg)),
        const SizedBox(height: 6),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(14),
            child: Text(
                'بيقرا وصف كل فيديو (اللي اتحفظ وقت الاستيراد) وبيطلّع روابط الملفات: درايف، PDF، شرائح، شيتات، جيت هاب. بيتجاهل روابط السوشيال والقناة والإعلانات والمتاجر. الروابط بتظهر تحت الدرس وتقدر تحذف أي رابط من محرر الدرس. الدرس اللي اتفحص مرة مبيتفحصش تاني، فرابط حذفته مش هيرجع. بيشتغل تلقائي على الكورسات الجديدة وقت الاستيراد.'),
          ),
        ),
        if (cs == null)
          const Center(child: CircularProgressIndicator())
        else ...[
          Row(children: [
            TextButton(
                onPressed: _busy ? null : () => setState(() => _picked.addAll([for (final c in cs) '${c['id']}'])),
                child: const Text('اختر الكل')),
            TextButton(onPressed: _busy ? null : () => setState(_picked.clear), child: const Text('إلغاء')),
          ]),
          for (final c in cs)
            CheckboxListTile(
              dense: true,
              value: _picked.contains('${c['id']}'),
              title: Text('${c['title']}', maxLines: 2, overflow: TextOverflow.ellipsis),
              onChanged: _busy
                  ? null
                  : (v) => setState(() => v == true ? _picked.add('${c['id']}') : _picked.remove('${c['id']}')),
            ),
        ],
        if (_sugg.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text('روابط ذكرها المدرس في الفيديو (اقتراحات، راجعها قبل الإضافة)',
              style: TextStyle(fontWeight: FontWeight.w800)),
          Row(children: [
            TextButton(onPressed: () => _decideAll(true), child: Text('إضافة الكل (${_sugg.length})')),
            TextButton(onPressed: _autoAccept, child: const Text('قبول تلقائي')),
            TextButton(onPressed: () => _decideAll(false), child: const Text('حذف الكل')),
          ]),
          for (final x in _sugg)
            Card(
              child: ListTile(
                title: Text('${x['title']}', maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text('${x['url']}\n${(x['lessons'] is Map) ? x['lessons']['title'] : ''}',
                    maxLines: 3, overflow: TextOverflow.ellipsis),
                isThreeLine: true,
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(icon: const Icon(Icons.check_circle), onPressed: () => _decide(x, true)),
                  IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _decide(x, false)),
                ]),
              ),
            ),
        ],
      ]),
    );
  }
}
