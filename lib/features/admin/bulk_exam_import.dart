import 'dart:convert';

import '../../core/search_norm.dart';
import 'question_import.dart';

/// One question row of a bulk exam file, with the lesson it belongs to.
class BulkQuestion {
  BulkQuestion(this.course, this.lesson, this.q);
  final String course;
  final String lesson; // title, YouTube link or YouTube id
  final ParsedQuestion q;
}

const bulkTemplateCsv =
    'course,lesson,question,A,B,C,D,answer,points,type,explanation\n'
    'Intro to Accounting,https://www.youtube.com/watch?v=XXXXXXXXXXX,What is an asset?,Something owned,Something owed,A cost,A tax,A,1,mcq,Assets are owned resources\n'
    'Intro to Accounting,Lesson 2 title,Debit is on the left side,True,False,,,True,1,true_false,\n';

/// Reads rows (first row = header) of CSV/XLSX: course, lesson, question,
/// options (A, B, C ... or option1 ...), answer, points, type, explanation.
List<BulkQuestion> parseBulkRows(List<List<String>> rows) {
  if (rows.length < 2) return [];
  final head = rows.first.map((h) => h.trim().toLowerCase()).toList();
  int col(List<String> n) => head.indexWhere(n.contains);
  final ci = col(['course', 'الكورس']);
  final li = col(['lesson', 'video', 'youtube', 'url', 'الدرس', 'الفيديو']);
  final qi = col(['question', 'body', 'text', 'السؤال']);
  final ai = col(['answer', 'correct', 'الإجابة', 'الاجابة']);
  final pi = col(['points', 'score', 'الدرجة']);
  final ti = col(['type', 'النوع']);
  final ei = col(['explanation', 'الشرح']);
  final optCols = <int>[];
  for (var i = 0; i < head.length; i++) {
    if (RegExp(r'^(option\s*\d+|choice\s*\d+|[a-h]|اختيار\s*\d+)$').hasMatch(head[i])) {
      optCols.add(i);
    }
  }
  if (qi < 0 || li < 0) return [];
  final out = <BulkQuestion>[];
  var lastCourse = '';
  var lastLesson = '';
  for (final r in rows.skip(1)) {
    String at(int i) => (i >= 0 && i < r.length) ? r[i].trim() : '';
    if (at(qi).isEmpty) continue;
    // Blank course/lesson cells repeat the row above (typical in sheets).
    final course = at(ci).isEmpty ? lastCourse : at(ci);
    final lesson = at(li).isEmpty ? lastLesson : at(li);
    lastCourse = course;
    lastLesson = lesson;
    final opts = [for (final i in optCols) if (at(i).isNotEmpty) at(i)];
    final correct = ai >= 0 ? parseAnswerCells(at(ai), opts) : <int>{};
    out.add(BulkQuestion(
      course,
      lesson,
      ParsedQuestion(
        type: normQuestionType(at(ti), correct.length, opts),
        body: at(qi),
        options: opts,
        correct: correct,
        points: double.tryParse(at(pi)) ?? 1,
        explanation: at(ei).isEmpty ? null : at(ei),
      ),
    ));
  }
  return out;
}

/// JSON: [{course, lesson, question, options, answer, points, type}, ...]
List<BulkQuestion> parseBulkJson(String text) {
  final data = jsonDecode(text);
  final list = data is List
      ? data
      : (data is Map ? (data['questions'] as List? ?? const []) : const []);
  final out = <BulkQuestion>[];
  for (final item in list) {
    if (item is! Map) continue;
    final qs = parseQuestionsJson(jsonEncode([item]));
    if (qs.isEmpty) continue;
    out.add(BulkQuestion(
      '${item['course'] ?? ''}',
      '${item['lesson'] ?? item['video'] ?? item['youtube'] ?? item['url'] ?? ''}',
      qs.first,
    ));
  }
  return out;
}

/// YouTube video id from a link or a bare 11-character id; null otherwise.
String? youtubeIdOf(String input) {
  final t = input.trim();
  if (RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(t)) return t;
  final m = RegExp(r'(?:v=|youtu\.be/|/embed/|/shorts/|/live/)([A-Za-z0-9_-]{11})')
      .firstMatch(t);
  return m?.group(1);
}

/// Finds the lesson a row points at. `lessons` rows carry id, course_id,
/// title, media_url; `courseTitles` maps course id to its title.
Map<String, dynamic>? matchLesson(
  String ref,
  String course,
  List<Map<String, dynamic>> lessons,
  Map<String, String> courseTitles,
) {
  var pool = lessons;
  final c = normSearch(course);
  if (c.isNotEmpty) {
    final inCourse = lessons
        .where((l) => normSearch(courseTitles['${l['course_id']}']).contains(c))
        .toList();
    if (inCourse.isNotEmpty) pool = inCourse;
  }
  final yt = youtubeIdOf(ref);
  if (yt != null) {
    final hit = pool.where((l) => '${l['media_url'] ?? ''}'.contains(yt)).toList();
    if (hit.length == 1) return hit.first;
    if (hit.length > 1) return hit.first;
  }
  final n = normSearch(ref);
  if (n.isEmpty) return null;
  final exact = pool.where((l) => normSearch('${l['title']}') == n).toList();
  if (exact.length == 1) return exact.first;
  if (exact.length > 1) return exact.first;
  final part = pool.where((l) {
    final t = normSearch('${l['title']}');
    return t.contains(n) || n.contains(t);
  }).toList();
  return part.length == 1 ? part.first : null;
}
