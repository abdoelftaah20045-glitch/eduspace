import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// True when [url] is a plain video file (or our own storage), which the
/// native video player handles. Everything else is shown in the in-app web
/// player (YouTube, Vimeo, Zoom/Meet/Teams pages, Facebook, Twitch...).
bool isDirectVideoUrl(String url) {
  final u = url.toLowerCase();
  if (u.contains('/storage/v1/')) return true;
  final path = Uri.tryParse(u)?.path ?? u;
  return ['.mp4', '.m4v', '.webm', '.mov', '.mkv', '.m3u8']
      .any((e) => path.endsWith(e));
}

String? _youtubeId(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return null;
  final host = uri.host.toLowerCase();
  if (host.contains('youtu.be')) {
    return uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
  }
  if (host.contains('youtube.com')) {
    final v = uri.queryParameters['v'];
    if (v != null && v.isNotEmpty) return v;
    final seg = uri.pathSegments;
    for (final key in ['live', 'embed', 'shorts']) {
      final i = seg.indexOf(key);
      if (i >= 0 && i + 1 < seg.length) return seg[i + 1];
    }
  }
  return null;
}

String? _vimeoId(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.host.toLowerCase().contains('vimeo.com')) {
    return null;
  }
  for (final p in uri.pathSegments) {
    if (RegExp(r'^\d+$').hasMatch(p)) return p;
  }
  return null;
}

String _iframePage(String src) => '<html><head><meta name="viewport" '
    'content="width=device-width, initial-scale=1"></head>'
    '<body style="margin:0;background:#000">'
    '<iframe src="$src" frameborder="0" allowfullscreen '
    'allow="autoplay; encrypted-media; fullscreen; picture-in-picture" '
    'style="position:absolute;top:0;left:0;width:100%;height:100%"></iframe>'
    '</body></html>';

/// Plays a page or stream inside the app (no external browser).
class InAppWebPlayer extends StatefulWidget {
  const InAppWebPlayer({super.key, required this.url});

  final String url;

  @override
  State<InAppWebPlayer> createState() => _InAppWebPlayerState();
}

class _InAppWebPlayerState extends State<InAppWebPlayer> {
  late final WebViewController _c;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          if (mounted) setState(() => _loading = false);
        },
        onWebResourceError: (e) {
          if (e.isForMainFrame == true && mounted) {
            setState(() {
              _failed = true;
              _loading = false;
            });
          }
        },
      ));
    final yt = _youtubeId(widget.url);
    final vm = _vimeoId(widget.url);
    if (yt != null) {
      _c.loadHtmlString(
        _iframePage('https://www.youtube.com/embed/$yt?playsinline=1&rel=0&autoplay=1'),
        baseUrl: 'https://www.youtube.com',
      );
    } else if (vm != null) {
      _c.loadHtmlString(
        _iframePage('https://player.vimeo.com/video/$vm?autoplay=1'),
        baseUrl: 'https://player.vimeo.com',
      );
    } else if (isDirectVideoUrl(widget.url)) {
      _c.loadHtmlString(
        '<html><head><meta name="viewport" content="width=device-width, initial-scale=1"></head>'
        '<body style="margin:0;background:#000"><video controls autoplay playsinline '
        'style="width:100%;height:100%" src="${widget.url}"></video></body></html>',
        baseUrl: 'https://eduspace.app',
      );
    } else {
      _c.loadRequest(Uri.parse(widget.url));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        WebViewWidget(controller: _c),
        if (_loading) const Center(child: CircularProgressIndicator()),
        if (_failed)
          Container(
            color: Colors.black87,
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 40),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () {
                    setState(() {
                      _failed = false;
                      _loading = true;
                    });
                    _c.reload();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Full-screen in-app player for live sessions and recordings.
class InAppPlayerScreen extends StatelessWidget {
  const InAppPlayerScreen({super.key, required this.url, required this.title});

  final String url;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: SafeArea(child: InAppWebPlayer(url: url)),
    );
  }
}
