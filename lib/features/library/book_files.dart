import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'book_links.dart';

/// Device-only book files. Nothing is stored on our server.
/// Cache lives in the temp folder (the phone may clear it); a book saved
/// "offline" lives in the app documents folder until the user removes it.
class BookFiles {
  BookFiles._();

  static Future<File> offlineFile(String id) async {
    final d = await getApplicationDocumentsDirectory();
    final dir = Directory('${d.path}/books');
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}/$id.pdf');
  }

  static Future<File> cacheFile(String id) async {
    final d = await getTemporaryDirectory();
    final dir = Directory('${d.path}/books_cache');
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}/$id.pdf');
  }

  static Future<bool> isOffline(String id) async =>
      (await offlineFile(id)).exists();

  static Future<void> removeOffline(String id) async {
    final f = await offlineFile(id);
    if (await f.exists()) await f.delete();
  }

  static Future<void> saveOffline(String id) async {
    final c = await cacheFile(id);
    if (await c.exists()) {
      await c.copy((await offlineFile(id)).path);
    }
  }

  /// Direct PDF URL for a stored link, or null when the link is not a PDF
  /// (then the reader falls back to the web view).
  static Future<String?> pdfUrl(String link) async {
    final u = link.trim();
    final d = BookLinks.driveId(u);
    if (d != null) {
      return 'https://drive.google.com/uc?export=download&id=$d';
    }
    final a = BookLinks.archiveId(u);
    if (a != null) {
      try {
        final r = await http
            .get(Uri.parse('https://archive.org/metadata/$a'))
            .timeout(const Duration(seconds: 20));
        final files = (jsonDecode(r.body)['files'] as List?) ?? const [];
        String? best;
        for (final f in files) {
          final name = (f['name'] ?? '').toString();
          if (!name.toLowerCase().endsWith('.pdf')) continue;
          final fmt = (f['format'] ?? '').toString().toLowerCase();
          if (fmt.contains('text pdf')) return _arch(a, name);
          best ??= name;
        }
        if (best != null) return _arch(a, best);
      } catch (_) {}
      return null;
    }
    var x = u;
    if (x.contains('dropbox.com')) {
      x = x.replaceAll('?dl=0', '?raw=1').replaceAll('&dl=0', '&raw=1');
      if (!x.contains('raw=1') && !x.contains('dl=1')) {
        x += x.contains('?') ? '&raw=1' : '?raw=1';
      }
      return x;
    }
    if (x.toLowerCase().contains('.pdf')) return x;
    return null;
  }

  static String _arch(String id, String name) =>
      'https://archive.org/download/$id/${Uri.encodeComponent(name)}';

  /// Downloads [url] into [dest]. Throws if the result is not a PDF
  /// (for example a Drive "virus scan" page).
  static Future<void> download(
    String url,
    File dest, {
    void Function(double? p)? onProgress,
  }) async {
    final client = http.Client();
    final tmp = File('${dest.path}.part');
    try {
      final req = http.Request('GET', Uri.parse(url));
      final res = await client.send(req).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) throw Exception('http ${res.statusCode}');
      final total = res.contentLength ?? 0;
      var got = 0;
      final sink = tmp.openWrite();
      await for (final chunk in res.stream) {
        sink.add(chunk);
        got += chunk.length;
        if (onProgress != null) {
          onProgress(total > 0 ? got / total : null);
        }
      }
      await sink.close();
      final head = await tmp.openRead(0, 5).first;
      if (String.fromCharCodes(head) != '%PDF-') {
        await tmp.delete();
        throw Exception('not a pdf');
      }
      if (await dest.exists()) await dest.delete();
      await tmp.rename(dest.path);
    } catch (e) {
      if (await tmp.exists()) await tmp.delete();
      rethrow;
    } finally {
      client.close();
    }
  }
}
