import 'package:flutter/widgets.dart' show TextDirection;
import 'html_text.dart';

/// Search-friendly form of a text: entity codes decoded, lower case,
/// Arabic diacritics and tatweel removed, letter variants unified
/// (أ إ آ ٱ -> ا, ة -> ه, ى -> ي, ؤ -> و, ئ -> ي) and digits unified.
String normSearch(String? input) {
  if (input == null || input.isEmpty) return '';
  var t = decodeHtml(input).toLowerCase();
  const map = {
    'أ': 'ا', 'إ': 'ا', 'آ': 'ا', 'ٱ': 'ا',
    'ة': 'ه', 'ى': 'ي', 'ؤ': 'و', 'ئ': 'ي', 'ک': 'ك', 'ی': 'ي',
    '٠': '0', '١': '1', '٢': '2', '٣': '3', '٤': '4',
    '٥': '5', '٦': '6', '٧': '7', '٨': '8', '٩': '9',
  };
  final b = StringBuffer();
  for (final r in t.runes) {
    // diacritics 064B-065F, 0670, tatweel 0640
    if ((r >= 0x064B && r <= 0x065F) || r == 0x0670 || r == 0x0640) continue;
    final ch = String.fromCharCode(r);
    b.write(map[ch] ?? ch);
  }
  return b.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// True when every word typed appears in the haystack.
bool matchesSearch(String query, Iterable<String?> fields) {
  final q = normSearch(query);
  if (q.isEmpty) return true;
  final hay = fields.map(normSearch).join(' ');
  return q.split(' ').every(hay.contains);
}

/// Search over every text value of a row (map / list / string).
bool matchesAny(String query, Object? row) {
  if (normSearch(query).isEmpty) return true;
  final b = StringBuffer();
  void walk(Object? v, int d) {
    if (d > 3 || v == null) return;
    if (v is String) {
      b.write('$v ');
    } else if (v is num) {
      b.write('$v ');
    } else if (v is Map) {
      for (final e in v.values) {
        walk(e, d + 1);
      }
    } else if (v is Iterable) {
      for (final e in v) {
        walk(e, d + 1);
      }
    }
  }
  walk(row, 0);
  return matchesSearch(query, [b.toString()]);
}

/// Direction of a typed text by its first strong letter: Arabic letters give
/// RTL, Latin letters give LTR, empty or digits keep [fallback].
TextDirection dirOfText(String t, TextDirection fallback) {
  for (final r in t.runes) {
    if ((r >= 0x0590 && r <= 0x08FF) || (r >= 0xFB1D && r <= 0xFEFF)) {
      return TextDirection.rtl;
    }
    if ((r >= 0x41 && r <= 0x5A) || (r >= 0x61 && r <= 0x7A)) {
      return TextDirection.ltr;
    }
  }
  return fallback;
}

const _xlang = <List<String>>[
  ['تمريض', 'nursing'], ['برمجة', 'programming'], ['تصميم', 'design'],
  ['رياضيات', 'math'], ['فيزياء', 'physics'], ['كيمياء', 'chemistry'],
  ['احياء', 'biology'], ['طب', 'medicine'], ['لغة', 'language'],
  ['انجليزي', 'english'], ['اعمال', 'business'], ['تسويق', 'marketing'],
  ['محاسبة', 'accounting'], ['ادارة', 'management'], ['بيانات', 'data'],
  ['شبكات', 'network'], ['قواعد بيانات', 'database'], ['تشريح', 'anatomy'],
  ['صيدلة', 'pharmacy'], ['هندسة', 'engineering'], ['تاريخ', 'history'],
  ['اقتصاد', 'economics'], ['علم نفس', 'psychology'], ['قانون', 'law'],
  ['جرافيك', 'graphic'], ['مونتاج', 'editing'], ['تصوير', 'photography'],
  ['اكسل', 'excel'], ['بايثون', 'python'], ['جافا', 'java'],
  ['ذكاء اصطناعي', 'artificial intelligence'], ['امن سيبراني', 'cyber security'],
  ['مواقع', 'web'], ['تطبيقات', 'apps'], ['موبايل', 'mobile'],
  ['اسعافات', 'first aid'], ['تغذية', 'nutrition'], ['اطفال', 'pediatric'],
];

/// The query plus its Arabic/English counterparts for common subject words,
/// so an Arabic search also finds English titles and the other way round.
List<String> crossLangQueries(String query) {
  final q = normSearch(query);
  final out = <String>{q};
  for (final p in _xlang) {
    final ar = normSearch(p[0]);
    final en = p[1];
    if (q.contains(ar)) out.add(q.replaceAll(ar, en));
    if (q.contains(en)) out.add(q.replaceAll(en, ar));
  }
  return out.where((x) => x.trim().isNotEmpty).toList();
}
