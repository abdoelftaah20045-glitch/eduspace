import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/tenant.dart';

/// Server-side import jobs (part45_import_jobs.sql). The database does the
/// work, so it keeps going with the app closed.
class ServerImport {
  ServerImport._();

  static SupabaseClient get _c => Supabase.instance.client;

  /// Saves a job. Returns its id, or null when the server part is not
  /// installed yet (the caller then falls back to the old in-app import).
  static Future<String?> enqueue({
    required String kind,
    required String title,
    required List<Map<String, dynamic>> items,
    Map<String, dynamic> params = const {},
  }) async {
    try {
      final row = await _c
          .from('import_jobs')
          .insert({
            'tenant_id': TenantContext.id,
            'kind': kind,
            'title': title,
            'items': items,
            'params': params,
            'total': items.length,
          })
          .select('id')
          .single();
      unawaited(kick());
      return row['id'] as String;
    } catch (_) {
      return null;
    }
  }

  /// Runs batches right away while work remains (the cron does the rest).
  static Future<void> kick() async {
    try {
      for (var i = 0; i < 40; i++) {
        final n = await _c.rpc('kick_import_jobs');
        if (n is int && n == 0) break;
      }
    } catch (_) {}
  }

  static Future<List<Map<String, dynamic>>> list() async {
    final rows = await _c
        .from('import_jobs')
        .select('id,kind,title,status,total,done,failed,cursor,last_error,created_at')
        .order('created_at', ascending: false)
        .limit(30);
    return List<Map<String, dynamic>>.from(rows);
  }

  static Future<void> stop(String id) async {
    await _c.rpc('stop_import_job', params: {'p_id': id});
  }

  static Future<void> start(String id) async {
    await _c.rpc('start_import_job', params: {'p_id': id});
    unawaited(kick());
  }
}


/// Server-side course-list (playlist) import (part49 + function playlist-import).
class ServerPlaylist {
  ServerPlaylist._();
  static SupabaseClient get _c => Supabase.instance.client;

  /// Saves the job on the server. Returns its id, or null when the server
  /// part is not installed yet (the caller keeps the old in-app import).
  static Future<String?> enqueue({
    required String title,
    required bool withDesc,
    required List<Map<String, dynamic>> items,
  }) async {
    try {
      final res = await _c.functions.invoke('playlist-import', body: {
        'action': 'create',
        'tenant_id': TenantContext.id,
        'title': title,
        'with_desc': withDesc,
        'items': items,
      }).timeout(const Duration(seconds: 60));
      final d = res.data;
      if (d is Map && d['ok'] == true) return '${d['job_id']}';
    } catch (_) {}
    return null;
  }

  static Future<List<Map<String, dynamic>>> list() async {
    final rows = await _c
        .from('playlist_jobs')
        .select('id,title,status,total,done,failed,stop,last_error,items,created_at')
        .order('created_at', ascending: false)
        .limit(10);
    return List<Map<String, dynamic>>.from(rows);
  }

  static Future<void> stop(String id) async {
    await _c
        .from('playlist_jobs')
        .update({'stop': true, 'status': 'stopped'}).eq('id', id);
  }

  /// Continue / retry: failed lists go back to waiting.
  static Future<void> resume(String id) async {
    final row =
        await _c.from('playlist_jobs').select('items').eq('id', id).single();
    final items = [
      for (final i in (row['items'] as List? ?? const []))
        if (i is Map)
          {
            ...Map<String, dynamic>.from(i),
            if (i['state'] == 'err') ...{'state': 'wait', 'tries': 0, 'note': ''},
          }
    ];
    await _c.from('playlist_jobs').update({
      'items': items,
      'stop': false,
      'status': 'queued',
      'paused_until': null,
      'busy_until': null,
    }).eq('id', id);
  }
}
