import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'storage_urls.dart';

/// Lesson files saved on the device so they open without internet.
class OfflineStore {
  OfflineStore._();

  static const _key = 'offline_files_v1';

  static Future<List<Map<String, dynamic>>> list() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    if (raw == null) return [];
    try {
      return [
        for (final e in jsonDecode(raw) as List) Map<String, dynamic>.from(e)
      ];
    } catch (_) {
      return [];
    }
  }

  static Future<void> _save(List<Map<String, dynamic>> l) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode(l));
  }

  /// Local path for a remote file id, or null when not downloaded.
  static Future<String?> localPath(String id) async {
    for (final e in await list()) {
      if (e['id'] == id) {
        final path = e['path'] as String?;
        if (path != null && File(path).existsSync()) return path;
      }
    }
    return null;
  }

  static Future<String> download(
      {required String id, required String name, required String url}) async {
    final resolved = await resolveStorageUrl(url);
    final dir = await getApplicationDocumentsDirectory();
    final safe = name.replaceAll(RegExp(r'[^\w.\-]'), '_');
    final file = File('${dir.path}/offline_${id}_$safe');
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(resolved));
      final res = await req.close();
      if (res.statusCode != 200) {
        throw HttpException('status ${res.statusCode}');
      }
      final sink = file.openWrite();
      await res.pipe(sink);
    } finally {
      client.close();
    }
    final l = await list();
    l.removeWhere((e) => e['id'] == id);
    l.add({
      'id': id,
      'name': name,
      'path': file.path,
      'size': file.lengthSync(),
      'at': DateTime.now().toIso8601String(),
    });
    await _save(l);
    return file.path;
  }

  static Future<void> remove(String id) async {
    final l = await list();
    for (final e in l.where((e) => e['id'] == id)) {
      try {
        File(e['path'] as String).deleteSync();
      } catch (_) {}
    }
    l.removeWhere((e) => e['id'] == id);
    await _save(l);
  }
}
