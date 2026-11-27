import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/l10n.dart';
import 'data/admin_repo.dart';

/// One video of a playlist.
class YtVideo {
  YtVideo(this.id, this.title, this.seconds, this.thumb);
  final String id;
  String title;
  final int seconds;
  final String thumb;
  String description = '';
  String get url => 'https://www.youtube.com/watch?v=$id';
}

/// One playlist, shown in the preview before import.
class YtPlaylist {
  YtPlaylist(this.id, this.title, this.channel, this.thumb, this.videos);
  final String id;
  String title;
  final String channel;
  final String thumb;
  final List<YtVideo> videos;
  bool selected = true;
  int get totalSeconds => videos.fold(0, (a, v) => a + v.seconds);
}

/// Reads public YouTube playlist pages. No API key, no paid service: the
/// app downloads the public page and reads the data YouTube embeds in it.
class YtImporter {
  static const _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36';
  static const _headers = {
    'User-Agent': _ua,
    'Accept-Language': 'en-US,en;q=0.9',
    'Cookie': 'CONSENT=YES+1; SOCS=CAI',
  };

  static String? listId(String input) {
    final t = input.trim();
    final m = RegExp(r'[?&]list=([A-Za-z0-9_-]+)').firstMatch(t);
    if (m != null) return m.group(1);
    if (RegExp(r'^(PL|UU|OL|FL|RD)[A-Za-z0-9_-]{8,}$').hasMatch(t)) return t;
    return null;
  }

  static void _collect(dynamic node, String key, List<Map> out) {
    if (node is Map) {
      node.forEach((k, v) {
        if (k == key && v is Map) out.add(v);
        _collect(v, key, out);
      });
    } else if (node is List) {
      for (final v in node) {
        _collect(v, key, out);
      }
    }
  }

  static String _text(dynamic n) {
    if (n is Map) {
      if (n['simpleText'] is String) return n['simpleText'] as String;
      final runs = n['runs'];
      if (runs is List) {
        return runs.map((r) => (r is Map ? r['text'] : '') ?? '').join();
      }
    }
    return '';
  }

  static String? _token(dynamic data) {
    final out = <Map>[];
    _collect(data, 'continuationEndpoint', out);
    for (final e in out) {
      final c = e['continuationCommand'];
      if (c is Map && c['token'] is String) return c['token'] as String;
    }
    return null;
  }

  static List<YtVideo> _videos(dynamic data, Set<String> seen) {
    final out = <Map>[];
    _collect(data, 'playlistVideoRenderer', out);
    final list = <YtVideo>[];
    for (final r in out) {
      final id = r['videoId'] as String?;
      if (id == null || !seen.add(id)) continue;
      final title = _text(r['title']);
      final secs = int.tryParse('${r['lengthSeconds'] ?? ''}') ?? 0;
      final th = r['thumbnail'];
      var thumb = 'https://i.ytimg.com/vi/$id/hqdefault.jpg';
      if (th is Map && th['thumbnails'] is List && (th['thumbnails'] as List).isNotEmpty) {
        final last = (th['thumbnails'] as List).last;
        if (last is Map && last['url'] is String) thumb = last['url'] as String;
      }
      list.add(YtVideo(id, title.isEmpty ? id : title, secs, thumb));
    }
    return list;
  }

  static Future<YtPlaylist> fetchPlaylist(String id) async {
    final res = await http
        .get(Uri.parse('https://www.youtube.com/playlist?list=$id&hl=en'),
            headers: _headers)
        .timeout(const Duration(seconds: 25));
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    final html = utf8.decode(res.bodyBytes);
    final start = html.indexOf('ytInitialData = ');
    if (start < 0) throw Exception('playlist page not readable');
    final from = html.indexOf('{', start);
    var end = html.indexOf(';</script>', from);
    if (end < 0) end = html.length;
    final data = jsonDecode(html.substring(from, end));
    final seen = <String>{};
    final videos = _videos(data, seen);
    // Header
    var title = '';
    var channel = '';
    final hs = <Map>[];
    _collect(data, 'playlistHeaderRenderer', hs);
    if (hs.isNotEmpty) {
      title = _text(hs.first['title']);
      channel = _text(hs.first['ownerText']);
    }
    if (title.isEmpty) {
      final m = RegExp(r'<meta property="og:title" content="([^"]*)"')
          .firstMatch(html);
      title = m?.group(1) ?? id;
    }
    if (channel.isEmpty) {
      final bl = <Map>[];
      _collect(data, 'playlistVideoRenderer', bl);
      if (bl.isNotEmpty) channel = _text(bl.first['shortBylineText']);
    }
    title = title
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
    // Continuations (playlists longer than 100 videos).
    final key = RegExp(r'"INNERTUBE_API_KEY":"([^"]+)"').firstMatch(html)?.group(1);
    final ver = RegExp(r'"INNERTUBE_CONTEXT_CLIENT_VERSION":"([^"]+)"')
            .firstMatch(html)
            ?.group(1) ??
        '2.20240101.00.00';
    var token = _token(data);
    var guard = 0;
    while (token != null && key != null && videos.length < 500 && guard < 6) {
      guard++;
      final r = await http
          .post(
            Uri.parse('https://www.youtube.com/youtubei/v1/browse?key=$key'),
            headers: {..._headers, 'Content-Type': 'application/json'},
            body: jsonEncode({
              'context': {
                'client': {'clientName': 'WEB', 'clientVersion': ver, 'hl': 'en'}
              },
              'continuation': token,
            }),
          )
          .timeout(const Duration(seconds: 25));
      if (r.statusCode != 200) break;
      final d = jsonDecode(utf8.decode(r.bodyBytes));
      final more = _videos(d, seen);
      if (more.isEmpty) break;
      videos.addAll(more);
      token = _token(d);
    }
    if (videos.isEmpty) throw Exception('no videos (private or empty playlist?)');
    return YtPlaylist(id, title, channel, videos.first.thumb, videos);
  }

  /// Real description of one video (from its public page), or ''.
  static Future<String> fetchDescription(String videoId) async {
    try {
      final res = await http
          .get(Uri.parse('https://www.youtube.com/watch?v=$videoId&hl=en'),
              headers: _headers)
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return '';
      final html = utf8.decode(res.bodyBytes);
      final m = RegExp(r'"shortDescription":"((?:[^"\\]|\\.)*)"').firstMatch(html);
      if (m == null) return '';
      final d = jsonDecode('"${m.group(1)}"') as String;
      return d.length > 1500 ? d.substring(0, 1500) : d;
    } catch (_) {
      return '';
    }
  }
}

String _mmss(int s) {
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = s % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(sec)}' : '${two(m)}:${two(sec)}';
}

/// Admin: paste YouTube playlist links, preview, import as draft courses.
class YoutubeImportScreen extends StatefulWidget {
  const YoutubeImportScreen({super.key});

  @override
  State<YoutubeImportScreen> createState() => _YoutubeImportScreenState();
}

class _YoutubeImportScreenState extends State<YoutubeImportScreen> {
  final _links = TextEditingController();
  final _field = TextEditingController();
  final List<YtPlaylist> _lists = [];
  final List<String> _errors = [];
  bool _loading = false;
  bool _importing = false;
  bool _withDesc = true;
  String _progress = '';

  @override
  void dispose() {
    _links.dispose();
    _field.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    final ids = <String>[];
    for (final line in _links.text.split(RegExp(r'[\n\s,]+'))) {
      if (line.trim().isEmpty) continue;
      final id = YtImporter.listId(line);
      if (id != null && !ids.contains(id)) ids.add(id);
    }
    if (ids.isEmpty) return;
    setState(() {
      _loading = true;
      _lists.clear();
      _errors.clear();
    });
    for (final id in ids) {
      try {
        final p = await YtImporter.fetchPlaylist(id);
        if (mounted) setState(() => _lists.add(p));
      } catch (e) {
        if (mounted) setState(() => _errors.add('$id: $e'));
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _import() async {
    final s = S.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final chosen = _lists.where((p) => p.selected).toList();
    if (chosen.isEmpty) return;
    setState(() => _importing = true);
    var done = 0;
    try {
      for (final p in chosen) {
        if (_withDesc) {
          // Four at a time, to stay polite and fast.
          for (var i = 0; i < p.videos.length; i += 4) {
            final batch = p.videos.skip(i).take(4).toList();
            if (mounted) {
              setState(() => _progress =
                  '${p.title}: ${s.t('yt_reading')} ${i + 1}/${p.videos.length}');
            }
            final res = await Future.wait(
                batch.map((v) => YtImporter.fetchDescription(v.id)));
            for (var k = 0; k < batch.length; k++) {
              batch[k].description = res[k];
            }
          }
        }
        final n = p.videos.length;
        for (var i = 0; i < n; i++) {
          final v = p.videos[i];
          if (v.description.trim().isEmpty) {
            v.description =
                '${s.t('yt_lesson')} ${i + 1}/$n: ${v.title} (${_mmss(v.seconds)})${p.channel.isEmpty ? '' : ' - ${p.channel}'}';
          }
        }
        if (mounted) setState(() => _progress = '${p.title}: ${s.t('yt_saving')}');
        final hours = p.totalSeconds / 3600;
        final courseId = await AdminRepository.createCourse({
          'title': p.title,
          'description':
              '${p.channel.isEmpty ? '' : '${p.channel} - '}$n ${s.t('lessons')}, ${hours.toStringAsFixed(1)} ${s.t('hours')}',
          'field': _field.text.trim(),
          'instructor_name': p.channel,
          'cover_url': p.thumb,
          'hours': double.parse(hours.toStringAsFixed(1)),
          'price': 0,
          'status': 'draft',
        });
        await AdminRepository.addSection(courseId, p.title, 0);
        final sections = await AdminRepository.fetchSections(courseId);
        final sectionId = sections.first['id'] as String;
        for (var i = 0; i < n; i++) {
          final v = p.videos[i];
          await AdminRepository.addLesson({
            'course_id': courseId,
            'section_id': sectionId,
            'title': v.title,
            'type': 'video',
            'content': v.description,
            'media_url': v.url,
            'duration_seconds': v.seconds > 0 ? v.seconds : null,
            'sort_order': i,
          });
        }
        done++;
      }
      messenger.showSnackBar(
          SnackBar(content: Text('${s.t('yt_done')}: $done')));
      if (mounted) {
        setState(() {
          _lists.removeWhere((p) => p.selected);
          _progress = '';
        });
      }
    } catch (e) {
      final t = '$e';
      messenger.showSnackBar(SnackBar(
          content: Text(
              '${s.t('generic_error')}: ${t.length > 140 ? t.substring(0, 140) : t}')));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final picked = _lists.where((p) => p.selected).length;
    return Scaffold(
      appBar: AppBar(title: Text(s.t('yt_import'))),
      bottomNavigationBar: _lists.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (_importing) ...[
                    const LinearProgressIndicator(),
                    const SizedBox(height: 6),
                    Text(_progress,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall),
                    const SizedBox(height: 6),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: (_importing || picked == 0) ? null : _import,
                      icon: const Icon(Icons.cloud_download_outlined),
                      label: Text('${s.t('yt_import_btn')} ($picked)'),
                    ),
                  ),
                ]),
              ),
            ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(s.t('yt_hint'), style: theme.textTheme.bodyMedium),
          const SizedBox(height: 12),
          TextField(
            controller: _links,
            minLines: 3,
            maxLines: 8,
            keyboardType: TextInputType.multiline,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: s.t('yt_links'),
              hintText: 'https://www.youtube.com/playlist?list=...',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _field,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: s.t('yt_category'),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _withDesc,
            onChanged: (v) => setState(() => _withDesc = v),
            title: Text(s.t('yt_with_desc')),
            subtitle: Text(s.t('yt_with_desc_sub')),
          ),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _loading || _importing ? null : _fetch,
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.search),
              label: Text(s.t('yt_preview')),
            ),
          ),
          for (final e in _errors)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(e, style: const TextStyle(color: Colors.red, fontSize: 12)),
            ),
          const SizedBox(height: 12),
          for (final p in _lists)
            Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Checkbox(
                        value: p.selected,
                        onChanged: (v) => setState(() => p.selected = v ?? false),
                      ),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(p.thumb,
                            width: 96,
                            height: 54,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                                width: 96,
                                height: 54,
                                color: scheme.surfaceContainerHighest)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextFormField(
                              initialValue: p.title,
                              onChanged: (v) => p.title = v,
                              style: const TextStyle(fontWeight: FontWeight.w800),
                              decoration: const InputDecoration(
                                  isDense: true, border: InputBorder.none),
                            ),
                            Text(
                                '${p.channel}  \u00b7  ${p.videos.length} ${s.t('lessons')}  \u00b7  ${_mmss(p.totalSeconds)}',
                                style: theme.textTheme.bodySmall),
                          ],
                        ),
                      ),
                    ]),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: Text(s.t('yt_videos'),
                          style: const TextStyle(fontSize: 13)),
                      children: [
                        for (var i = 0; i < p.videos.length; i++)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Text('${i + 1}'),
                            title: Text(p.videos[i].title,
                                maxLines: 2, overflow: TextOverflow.ellipsis),
                            trailing: Text(_mmss(p.videos[i].seconds)),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
