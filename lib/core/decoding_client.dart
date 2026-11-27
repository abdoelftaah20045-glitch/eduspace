import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

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

  static Directory? _dir;

  Future<File?> _file(http.BaseRequest request) async {
    try {
      _dir ??= Directory('${(await getTemporaryDirectory()).path}/api_cache');
      if (!_dir!.existsSync()) _dir!.createSync(recursive: true);
      // Cache is per signed-in user (id from the access token).
      var who = 'anon';
      final auth = request.headers['Authorization'] ?? '';
      final parts = auth.replaceFirst('Bearer ', '').split('.');
      if (parts.length == 3) {
        try {
          final m = jsonDecode(
              utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
          who = '${m['sub'] ?? 'anon'}';
        } catch (_) {}
      }
      final key = '$who|${request.url}'.hashCode.toRadixString(16);
      return File('${_dir!.path}/${who.hashCode.toRadixString(16)}_$key');
    } catch (_) {
      return null;
    }
  }

  Future<http.StreamedResponse?> _fromCache(http.BaseRequest request) async {
    try {
      final f = await _file(request);
      if (f == null || !f.existsSync()) return null;
      final m = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      final body = utf8.encode(m['b'] as String);
      return http.StreamedResponse(Stream.value(body), 200,
          contentLength: body.length,
          request: request,
          headers: {
            'content-type': 'application/json; charset=utf-8',
            if (m['r'] != null) 'content-range': '${m['r']}',
            'x-from-cache': '1',
          });
    } catch (_) {
      return null;
    }
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final isRest = request.url.path.contains('/rest/v1/');
    final isGet = request.method == 'GET';
    http.StreamedResponse res;
    try {
      res = isRest && isGet
          ? await _inner.send(request).timeout(const Duration(seconds: 15))
          : await _inner.send(request);
    } catch (e) {
      if (isRest && isGet) {
        final c = await _fromCache(request);
        if (c != null) return c;
      }
      rethrow;
    }
    try {
      final type = res.headers['content-type'] ?? '';
      if (!isRest || !type.contains('json')) {
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
      if (isGet && res.statusCode == 200 && out.length < 1500000) {
        // Remember the last good answer for weak or missing connections.
        try {
          final f = await _file(request);
          await f?.writeAsString(jsonEncode(
              {'b': utf8.decode(out), 'r': res.headers['content-range']}));
        } catch (_) {}
      } else if (isGet && res.statusCode >= 500) {
        final c = await _fromCache(request);
        if (c != null) return c;
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
