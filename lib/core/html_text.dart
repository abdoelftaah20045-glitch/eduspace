/// Decodes HTML entities (numeric, hex and the common named ones), also
/// when they were encoded more than once (&amp;#1601; -> &#1601; -> ف).
String decodeHtml(String? input) {
  var s = input ?? '';
  if (!s.contains('&')) return s;
  const named = {
    'amp': '&', 'lt': '<', 'gt': '>', 'quot': '"', 'apos': "'", 'nbsp': ' ',
    'laquo': '«', 'raquo': '»', 'hellip': '…', 'ndash': '–', 'mdash': '—',
    'lsquo': '‘', 'rsquo': '’', 'ldquo': '“', 'rdquo': '”', 'copy': '©',
    'reg': '®', 'trade': '™', 'middot': '·', 'bull': '•',
  };
  final re = RegExp(r'&(?:#(\d{1,7})|#[xX]([0-9a-fA-F]{1,6})|([A-Za-z]{2,8}));?');
  for (var i = 0; i < 5; i++) {
    final next = s.replaceAllMapped(re, (m) {
      if (m.group(1) != null) {
        final c = int.tryParse(m.group(1)!);
        return (c != null && c > 0 && c <= 0x10FFFF) ? String.fromCharCode(c) : m.group(0)!;
      }
      if (m.group(2) != null) {
        final c = int.tryParse(m.group(2)!, radix: 16);
        return (c != null && c > 0 && c <= 0x10FFFF) ? String.fromCharCode(c) : m.group(0)!;
      }
      final n = named[m.group(3)!.toLowerCase()];
      // Named entities only count with their closing semicolon.
      if (n != null && m.group(0)!.endsWith(';')) return n;
      return m.group(0)!;
    });
    if (next == s) break;
    s = next;
  }
  return s;
}
