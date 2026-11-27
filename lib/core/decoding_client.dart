import 'dart:convert';

import 'package:http/http.dart' as http;

import 'html_text.dart';

/// Wraps the HTTP client of the data layer: every JSON answer from the
/// database API passes through here, and HTML entity codes (&#1606; and
/// friends, also double-encoded) inside any text value are turned into the
/// real characters. So titles, names and categories read right in every
/// screen, whatever is stored.
class DecodingHttpClient extends http.BaseClient {
  DecodingHttpClient(this._inner);
  final http.Client _inner;

  static final _marker =
      RegExp(r'&(#\d|#[xX][0-9a-fA-F]|amp;|lt;|gt;|quot;|apos;|nbsp;)');

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final res = await _inner.send(request);
    try {
      final type = res.headers['content-type'] ?? '';
      if (!request.url.path.contains('/rest/v1/') || !type.contains('json')) {
        return res;
      }
      final bytes = await res.stream.toBytes();
      var out = bytes;
      try {
        final text = utf8.decode(bytes);
        if (_marker.hasMatch(text)) {
          out = utf8.encode(jsonEncode(_deep(jsonDecode(text))));
        }
      } catch (_) {
        out = bytes;
      }
      final headers = Map<String, String>.from(res.headers)
        ..remove('content-encoding')
        ..remove('content-length');
      return http.StreamedResponse(
        Stream.value(out),
        res.statusCode,
        contentLength: out.length,
        request: res.request,
        headers: headers,
        isRedirect: res.isRedirect,
        persistentConnection: res.persistentConnection,
        reasonPhrase: res.reasonPhrase,
      );
    } catch (_) {
      return res;
    }
  }

  static dynamic _deep(dynamic v) {
    if (v is String) return v.contains('&') ? decodeHtml(v) : v;
    if (v is List) return [for (final e in v) _deep(e)];
    if (v is Map) return {for (final e in v.entries) e.key: _deep(e.value)};
    return v;
  }

  @override
  void close() => _inner.close();
}
