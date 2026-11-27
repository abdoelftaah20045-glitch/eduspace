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
