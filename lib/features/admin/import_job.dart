import 'auto_category.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/bg_guard.dart';
import '../../core/html_text.dart';
import '../../core/l10n.dart';
import 'data/admin_repo.dart';
import 'data/admin_tools_repo.dart';
import 'playlist_import.dart';
import 'server_import.dart';
import 'youtube_import_screen.dart';

/// One playlist line of an import.
class ImportRow {
  ImportRow(this.line, this.category, this.url, this.title, this.language,
      this.level,
      {this.status = 'wait', this.note = '', this.courseId = '', this.review = ''});
  final int line;
  String category;
  final String url;
  final String title;
  final String language;
  final String level;
  String status; // wait, run, ok, skip, err
  String note;
  String courseId;
  String review; // '' = waiting for review, approved, rejected

  Map<String, dynamic> toJson() => {
        'l': line,
        'c': category,
        'u': url,
        't': title,
        'g': language,
        'v': level,
        's': status,
        'n': note,
        'ci': courseId,
        'rv': review,
      };

  static ImportRow fromJson(Map<String, dynamic> j) => ImportRow(
        (j['l'] as num?)?.toInt() ?? 0,
        '${j['c'] ?? ''}',
        '${j['u'] ?? ''}',
        '${j['t'] ?? ''}',
        '${j['g'] ?? ''}',
        '${j['v'] ?? ''}',
        status: '${j['s'] ?? 'wait'}',
        note: decodeHtml('${j['n'] ?? ''}'),
        courseId: '${j['ci'] ?? ''}',
        review: '${j['rv'] ?? ''}',
      );
}

/// App-wide import job. It does not belong to a screen: leaving the screen
/// or the app does not stop it, every step is saved on the phone, and when
/// the app opens again an unfinished job continues by itself.
class ImportJob extends ChangeNotifier {
  ImportJob._();
  static final ImportJob instance = ImportJob._();

  /// Bumped after every finished playlist so course lists can refresh.
  static final ValueNotifier<int> courseTick = ValueNotifier<int>(0);

  static const _key = 'import_job_v1';

  final List<ImportRow> rows = [];
  String fileName = '';
  bool withDesc = true;
  bool running = false;
  /// Set when the last start was handed to the server.
  String serverJobId = '';
  String progress = '';
  bool _stop = false;

  int get done =>
      rows.where((r) => r.status == 'ok' || r.status == 'skip' || r.status == 'err').length;
  bool get hasPending =>
      rows.any((r) => r.status == 'wait' || r.status == 'run');

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
          _key,
          jsonEncode({
            'file': fileName,
            'desc': withDesc,
            'rows': rows.map((r) => r.toJson()).toList(),
          }));
    } catch (_) {}
  }

  Future<void> restore() async {
    if (rows.isNotEmpty || running) return;
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key);
      if (raw == null) return;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      fileName = '${m['file'] ?? ''}';
      withDesc = m['desc'] != false;
      for (final r in (m['rows'] as List? ?? const [])) {
        final row = ImportRow.fromJson(Map<String, dynamic>.from(r as Map));
        if (row.status == 'run') row.status = 'wait';
        rows.add(row);
      }
      notifyListeners();
    } catch (_) {}
  }

  void setRows(List<ImportRow> list, String name) {
    rows
      ..clear()
      ..addAll(list);
    fileName = name;
    progress = '';
    _save();
    notifyListeners();
  }

  void setWithDesc(bool v) {
    withDesc = v;
    _save();
    notifyListeners();
  }

  /// Imported courses waiting for the admin's decision.
  Set<String>? draftIds;

  /// Ids of courses still in draft (what the review queue may show).
  Future<void> refreshDrafts() async {
    try {
      final r = await Supabase.instance.client
          .from('courses')
          .select('id')
          .eq('status', 'draft')
          .limit(2000);
      draftIds = {for (final m in r as List) '${(m as Map)['id']}'};
      notifyListeners();
    } catch (_) {}
  }

  /// Also lists playlists that were skipped because they were imported
  /// before, as long as their course is still a draft.
  List<ImportRow> get reviewQueue {
    final seen = <String>{};
    return rows.where((r) {
      if (r.courseId.isEmpty || r.review.isNotEmpty) return false;
      if (r.status != 'ok' && r.status != 'skip') return false;
      if (draftIds != null && !draftIds!.contains(r.courseId)) return false;
      return seen.add(r.courseId);
    }).toList();
  }

  Future<void> approve(ImportRow r, {bool notify = false}) async {
    await AdminToolsRepository.setCourseStatus(r.courseId, 'published',
        notify: notify);
    r.review = 'approved';
    await _save();
    courseTick.value++;
    notifyListeners();
  }

  Future<void> reject(ImportRow r) async {
    await AdminRepository.deleteCourse(r.courseId);
    r.review = 'rejected';
    await _save();
    courseTick.value++;
    notifyListeners();
  }

  void stop() {
    _stop = true;
  }

  static bool _isNetwork(Object e) {
    if (e is SocketException || e is TimeoutException || e is http.ClientException) {
      return true;
    }
    final t = '$e'.toLowerCase();
    return t.contains('socket') ||
        t.contains('host lookup') ||
        t.contains('connection') ||
        t.contains('timed out') ||
        t.contains('timeout') ||
        t.contains('network') ||
        t.contains('handshake') ||
        t.contains('retryable') ||
        t.contains('clientexception');
  }

  /// Runs every waiting row. [retryErrors] also re-queues failed rows.
  Future<void> start(S s, {bool retryErrors = false}) async {
    if (running) return;
    if (retryErrors) {
      for (final r in rows) {
        if (r.status == 'err') r.status = 'wait';
      }
    }
    if (!hasPending) return;
    // Preferred: the server does the whole import (keeps going with the app
    // closed, retries by itself). Falls back to the in-app loop below when
    // the server part is not installed yet.
    final waiting = rows.where((r) => r.status == 'wait').toList();
    if (waiting.isNotEmpty) {
      final id = await ServerPlaylist.enqueue(
        title: fileName,
        withDesc: withDesc,
        items: [
          for (final r in waiting)
            {
              'line': r.line,
              'category': r.category,
              'url': r.url,
              'title': r.title,
              'lang': r.language,
              'level': r.level,
            }
        ],
      );
      if (id != null) {
        rows.removeWhere((r) => r.status == 'wait');
        progress = '';
        await _save();
        serverJobId = id;
        notifyListeners();
        return;
      }
    }
    running = true;
    _stop = false;
    final title = s.t('bg_import_running');
    notifyListeners();
    await BgGuard.begin(title, '$done/${rows.length}');
    final known = <String>{};
    final names = <String>[];
    try {
      for (final c in await AdminToolsRepository.fetchCategories()) {
        if (c['kind'] == 'category') {
          known.add((c['name'] as String).trim().toLowerCase());
          names.add((c['name'] as String).trim());
        }
      }
    } catch (_) {}
    var okCount = 0;
    var errCount = 0;
    for (final row in rows) {
      if (_stop) break;
      if (row.status != 'wait') continue;
      row.status = 'run';
      row.note = '';
      notifyListeners();
      var wait = 5;
      while (true) {
        if (_stop) {
          row.status = 'wait';
          break;
        }
        try {
          final id = YtImporter.listId(row.url);
          if (id == null) throw s.t('fi_bad_link');
          final p = await YtImporter.fetchPlaylist(id);
          if (row.title.isNotEmpty) p.title = row.title;
          if (row.category.isEmpty) {
            // No category given: classify from the content (free rules).
            // Not sure -> stays empty and waits for the admin in the review.
            final pk = AutoCategory.pick(
              title: p.title,
              videoTitles: [for (final v in p.videos) v.title],
              existing: names,
              channel: p.channel,
            );
            if (pk != null) {
              final par = pk.parent;
              if (par != null && !known.contains(par.toLowerCase())) {
                await AdminToolsRepository.addCategory('category', par);
                known.add(par.toLowerCase());
                names.add(par);
              }
              row.category = pk.name;
            }
          }
          if (row.category.isNotEmpty &&
              !known.contains(row.category.toLowerCase())) {
            await AdminToolsRepository.addCategory('category', decodeHtml(row.category));
            known.add(row.category.toLowerCase());
            names.add(row.category);
          }
          final res = await PlaylistImport.run(
            p,
            s: s,
            withDesc: withDesc,
            field: row.category,
            level: row.level,
            language: row.language,
            onProgress: (t) {
              progress = decodeHtml(t);
              notifyListeners();
              BgGuard.update(title,
                  '$done/${rows.length} - ${s.t('bg_err_word')}: $errCount\n$t');
            },
          );
          final added = res.$1;
          row.courseId = res.$2;
          await refreshDrafts();
          if (added < 0) {
            row.status = 'skip';
            row.note = '${p.title} (${s.t('fi_already')})';
          } else {
            row.status = 'ok';
            row.note = '${p.title} ($added)';
            okCount++;
          }
          break;
        } catch (e) {
          if (_isNetwork(e)) {
            row.note = s.t('bg_waiting_net');
            progress = s.t('bg_waiting_net');
            notifyListeners();
            BgGuard.update(title, s.t('bg_waiting_net'));
            await Future<void>.delayed(Duration(seconds: wait));
            wait = wait >= 60 ? 60 : wait * 2;
            continue;
          }
          final t = '$e';
          row.status = 'err';
          row.note = t.length > 160 ? t.substring(0, 160) : t;
          errCount++;
          break;
        }
      }
      await _save();
      courseTick.value++;
      notifyListeners();
    }
    running = false;
    progress = '';
    await _save();
    await BgGuard.end();
    if (!_stop) {
      await BgGuard.notify(4712, s.t('bg_import_done'),
          '${s.t('bg_done_word')}: $okCount - ${s.t('bg_err_word')}: $errCount');
    }
    _stop = false;
    notifyListeners();
  }

  /// Called when the app starts: continue an unfinished job.
  Future<void> resumeIfPending(S s) async {
    await restore();
    if (running || !hasPending) return;
    try {
      if (Supabase.instance.client.auth.currentUser == null) return;
    } catch (_) {
      return;
    }
    unawaited(start(s));
  }
}
