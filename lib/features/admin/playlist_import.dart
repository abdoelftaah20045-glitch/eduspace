import '../../core/html_text.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/l10n.dart';
import 'data/admin_repo.dart';
import 'youtube_import_screen.dart';
import 'lesson_links.dart';

String _mmss(int sec) {
  final m = sec ~/ 60;
  final r = sec % 60;
  return '$m:${r.toString().padLeft(2, '0')}';
}

/// Resume-aware playlist import shared by the link screen and the file
/// screen. A playlist that was only half imported (app killed, network
/// lost) is completed: only the missing videos are added to the existing
/// course. A playlist that is complete is skipped.
class PlaylistImport {
  PlaylistImport._();

  /// Returns the number of lessons added, or -1 when the playlist was
  /// already fully imported.
  static Future<(int, String)> run(
    YtPlaylist p, {
    required S s,
    required bool withDesc,
    String field = '',
    String level = '',
    String language = '',
    void Function(String text)? onProgress,
  }) async {
    final db = Supabase.instance.client;
    final n = p.videos.length;
    var courseId = '';
    var sectionId = '';
    final have = <String>{};

    final hit = await db
        .from('lessons')
        .select('course_id')
        .ilike('media_url', '%list=${p.id}%')
        .limit(1);
    if ((hit as List).isNotEmpty) {
      courseId = '${(hit.first as Map)['course_id']}';
      final rows = await db
          .from('lessons')
          .select('media_url, section_id')
          .eq('course_id', courseId)
          .limit(5000);
      final re = RegExp(r'[?&]v=([A-Za-z0-9_-]{11})');
      for (final r in rows as List) {
        final m = r as Map;
        final u = '${m['media_url'] ?? ''}';
        final mt = re.firstMatch(u);
        if (mt != null) have.add(mt.group(1)!);
        if (sectionId.isEmpty && m['section_id'] != null) {
          sectionId = '${m['section_id']}';
        }
      }
      if (p.videos.every((v) => have.contains(v.id))) {
        if (p.avatar.isNotEmpty) {
          try {
            await db
                .from('courses')
                .update({'instructor_photo_url': p.avatar})
                .eq('id', courseId)
                .or('instructor_photo_url.is.null,instructor_photo_url.eq.');
          } catch (_) {}
        }
        return (-1, courseId);
      }
    }

    final todo = <int>[];
    for (var i = 0; i < n; i++) {
      if (!have.contains(p.videos[i].id)) todo.add(i);
    }

    if (withDesc) {
      for (var i = 0; i < todo.length; i += 4) {
        final batch = todo.skip(i).take(4).toList();
        onProgress?.call(
            '${p.title}: ${s.t('yt_reading')} ${i + 1}/${todo.length}');
        final res = await Future.wait(
            batch.map((k) => YtImporter.fetchDescription(p.videos[k].id)));
        for (var k = 0; k < batch.length; k++) {
          p.videos[batch[k]].description = res[k];
        }
      }
    }
    for (final i in todo) {
      final v = p.videos[i];
      if (v.description.trim().isEmpty) {
        v.description =
            '${s.t('yt_lesson')} ${i + 1}/$n: ${v.title} (${_mmss(v.seconds)})${p.channel.isEmpty ? '' : ' - ${p.channel}'}';
      }
    }

    onProgress?.call('${p.title}: ${s.t('yt_saving')}');
    var createdHere = false;
    if (courseId.isEmpty) {
      // A previous run may have died right after creating the course and
      // before its first lesson: reuse that empty draft instead of making
      // a duplicate.
      try {
        final cand = await db
            .from('courses')
            .select('id')
            .eq('title', p.title)
            .eq('instructor_name', p.channel)
            .eq('status', 'draft')
            .limit(5);
        for (final c in cand as List) {
          final id = '${(c as Map)['id']}';
          final any =
              await db.from('lessons').select('id').eq('course_id', id).limit(1);
          if ((any as List).isEmpty) {
            courseId = id;
            break;
          }
        }
      } catch (_) {}
    }
    if (courseId.isEmpty) {
      createdHere = true;
      final hours = p.totalSeconds / 3600;
      courseId = await AdminRepository.createCourse({
        'title': p.title,
        'description':
            '${p.channel.isEmpty ? '' : '${p.channel} - '}$n ${s.t('lessons')}, ${hours.toStringAsFixed(1)} ${s.t('hours')}',
        'field': decodeHtml(field),
        'instructor_name': p.channel,
        'cover_url': p.thumb,
        'hours': double.parse(hours.toStringAsFixed(1)),
        'price': 0,
        'status': 'draft',
        if (level.isNotEmpty) 'level': level,
        if (language.isNotEmpty) 'language': language,
      });
    }
    // Teacher picture (best effort: needs the instructor_photo_url column
    // from SQL part 33; never blocks the import).
    if (p.avatar.isNotEmpty) {
      try {
        await db
            .from('courses')
            .update({'instructor_photo_url': p.avatar})
            .eq('id', courseId)
            .or('instructor_photo_url.is.null,instructor_photo_url.eq.');
      } catch (_) {}
    }
    try {
    if (sectionId.isEmpty) {
      final sections = await AdminRepository.fetchSections(courseId);
      if (sections.isEmpty) {
        await AdminRepository.addSection(courseId, p.title, 0);
        final again = await AdminRepository.fetchSections(courseId);
        sectionId = again.first['id'] as String;
      } else {
        sectionId = sections.first['id'] as String;
      }
    }

    final rows = <Map<String, dynamic>>[];
    for (final i in todo) {
      final v = p.videos[i];
      rows.add({
        'course_id': courseId,
        'section_id': sectionId,
        'title': v.title,
        'type': 'video',
        'content': v.description,
        'media_url': '${v.url}&list=${p.id}',
        'duration_seconds': v.seconds > 0 ? v.seconds : null,
        'sort_order': i,
      });
    }
    for (var i = 0; i < rows.length; i += 50) {
      await db.from('lessons').insert(rows.skip(i).take(50).toList());
    }
    try {
      await LessonLinks.pull([courseId]);
    } catch (_) {}
    return (rows.length, courseId);
    } catch (e) {
      // Do not leave an empty draft course behind when we created it.
      if (createdHere) {
        try {
          final any = await db
              .from('lessons')
              .select('id')
              .eq('course_id', courseId)
              .limit(1);
          if ((any as List).isEmpty) await AdminRepository.deleteCourse(courseId);
        } catch (_) {}
      }
      rethrow;
    }
  }
}
