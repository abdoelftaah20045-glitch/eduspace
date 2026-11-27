/// Turns a pasted book link (Drive, Archive.org, Dropbox, direct PDF) into a
/// reader URL and a cover URL. Nothing is stored on our servers: only the
/// link and these derived URLs are used.
class BookLink {
  const BookLink({required this.readerUrl, this.coverUrl, this.kind = 'link'});
  final String readerUrl;
  final String? coverUrl;
  final String kind;
}

class BookLinks {
  BookLinks._();

  static String? driveId(String url) {
    final u = url.trim();
    if (!u.contains('drive.google.com') && !u.contains('docs.google.com')) {
      return null;
    }
    final m1 = RegExp(r'/d/([A-Za-z0-9_-]{10,})').firstMatch(u);
    if (m1 != null) return m1.group(1);
    final m2 = RegExp(r'[?&]id=([A-Za-z0-9_-]{10,})').firstMatch(u);
    return m2?.group(1);
  }

  static String? archiveId(String url) {
    final m = RegExp(r'archive\.org/(?:details|download|embed|stream)/([^/?#]+)')
        .firstMatch(url.trim());
    return m?.group(1);
  }

  static BookLink resolve(String raw, {String? coverOverride}) {
    final url = raw.trim();
    final cover = (coverOverride ?? '').trim();
    final d = driveId(url);
    if (d != null) {
      return BookLink(
        readerUrl: 'https://drive.google.com/file/d/$d/preview',
        coverUrl: cover.isNotEmpty
            ? cover
            : 'https://drive.google.com/thumbnail?id=$d&sz=w500',
        kind: 'drive',
      );
    }
    final a = archiveId(url);
    if (a != null) {
      return BookLink(
        readerUrl: 'https://archive.org/embed/$a',
        coverUrl: cover.isNotEmpty
            ? cover
            : 'https://archive.org/services/img/$a',
        kind: 'archive',
      );
    }
    var direct = url;
    if (direct.contains('dropbox.com')) {
      direct = direct
          .replaceAll('?dl=0', '?raw=1')
          .replaceAll('&dl=0', '&raw=1');
      if (!direct.contains('raw=1') && !direct.contains('dl=1')) {
        direct += direct.contains('?') ? '&raw=1' : '?raw=1';
      }
    }
    final isPdf = direct.toLowerCase().contains('.pdf') ||
        direct.contains('dropbox.com');
    return BookLink(
      readerUrl: isPdf
          ? 'https://docs.google.com/viewer?embedded=true&url=${Uri.encodeComponent(direct)}'
          : direct,
      coverUrl: cover.isEmpty ? null : cover,
      kind: isPdf ? 'pdf' : 'link',
    );
  }

  /// Warm colour for the generated book spine, stable per title.
  static int spineColor(String title) {
    const palette = [
      0xFF8E3B46, 0xFF1F6F8B, 0xFF4C6E45, 0xFF7A4E9A, 0xFFB5651D,
      0xFF2F4858, 0xFF9C2F63, 0xFF3F6A5F, 0xFF55657F, 0xFF8A6D1F,
    ];
    var h = 0;
    for (final c in title.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return palette[h % palette.length];
  }
}
