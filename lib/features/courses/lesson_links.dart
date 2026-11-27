import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

final RegExp _urlRe = RegExp(r'https?://[^\s<>"\u200f\u200e]+', caseSensitive: false);

List<String> extractLinks(String text) {
  final seen = <String>{};
  final out = <String>[];
  for (final m in _urlRe.allMatches(text)) {
    var u = m.group(0)!;
    while (u.isNotEmpty && '.,;:!?)]}،؛'.contains(u[u.length - 1])) {
      u = u.substring(0, u.length - 1);
    }
    if (u.length > 8 && seen.add(u)) out.add(u);
  }
  return out;
}

Future<void> _open(String u) async {
  try {
    await launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication);
  } catch (_) {}
}

/// Lesson description with tappable links, followed by a "روابط الفيديو" list.
class LessonDescription extends StatelessWidget {
  const LessonDescription({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final links = extractLinks(text);
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in _urlRe.allMatches(text)) {
      if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
      var u = m.group(0)!;
      var tail = '';
      while (u.isNotEmpty && '.,;:!?)]}،؛'.contains(u[u.length - 1])) {
        tail = u[u.length - 1] + tail;
        u = u.substring(0, u.length - 1);
      }
      final link = u;
      spans.add(TextSpan(
        text: link,
        style: TextStyle(color: scheme.primary, decoration: TextDecoration.underline),
        recognizer: TapGestureRecognizer()..onTap = () => _open(link),
      ));
      if (tail.isNotEmpty) spans.add(TextSpan(text: tail));
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text.rich(TextSpan(
          style: DefaultTextStyle.of(context).style, children: spans)),
      if (links.isNotEmpty) ...[
        const SizedBox(height: 14),
        Text('روابط الفيديو',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        for (final u in links)
          InkWell(
            onTap: () => _open(u),
            child: Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                Icon(Icons.link, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(u,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textDirection: TextDirection.ltr,
                        style: TextStyle(color: scheme.primary, fontSize: 13))),
              ]),
            ),
          ),
      ],
    ]);
  }
}
