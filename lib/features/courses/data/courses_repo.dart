import 'package:supabase_flutter/supabase_flutter.dart';

import 'course_models.dart';

/// All Supabase access for the courses feature lives here.
/// RLS on the server is the real gate; these queries assume a signed-in user.
class CoursesRepository {
  CoursesRepository._();

  static SupabaseClient get _c => Supabase.instance.client;

  static String get _uid => _c.auth.currentUser!.id;

  /// Published courses, newest first, optional free-text filter.
  static Future<List<Course>> fetchCourses({String? query}) async {
    var q = _c.from('courses').select().eq('status', 'published');
    if (query != null && query.trim().isNotEmpty) {
      final pattern = '%${query.trim()}%';
      q = q.or('title.ilike.$pattern,description.ilike.$pattern,field.ilike.$pattern');
    }
    final rows = await q.order('created_at', ascending: false).limit(50);
    return rows.map((m) => Course.fromMap(m)).toList();
  }

  /// Courses the current user is enrolled in, with progress percent.
  static Future<List<Course>> fetchMyCourses() async {
    final rows = await _c
        .from('enrollments')
        .select('*, courses(*)')
        .eq('user_id', _uid)
        .eq('status', 'active')
        .order('created_at', ascending: false);
    final progressRows = await _c
        .from('course_progress_summary')
        .select()
        .eq('user_id', _uid);
    final percentByCourse = <String, int>{
      for (final p in progressRows)
        p['course_id'] as String: (p['percent'] as num?)?.toInt() ?? 0,
    };
    final result = <Course>[];
    for (final m in rows) {
      final e = Enrollment.fromMap(m);
      final course = e.course;
      if (course == null) continue;
      result.add(Course(
        id: course.id,
        title: course.title,
        description: course.description,
        coverUrl: course.coverUrl,
        field: course.field,
        level: course.level,
        instructorName: course.instructorName,
        language: course.language,
        prerequisites: course.prerequisites,
        hours: course.hours,
        price: course.price,
        currency: course.currency,
        status: course.status,
        visibility: course.visibility,
        lessonsSequential: course.lessonsSequential,
        isEnrolled: true,
        progressPercent: percentByCourse[course.id] ?? 0,
      ));
    }
    return result;
  }

  /// One course with its sections and lessons, merged with the current
  /// user's enrollment and progress state.
  static Future<CourseDetails> fetchCourseDetails(String courseId) async {
    final courseMap = await _c
        .from('courses')
        .select('*, course_sections(*, lessons(*))')
        .eq('id', courseId)
        .single();
    final course = Course.fromMap(courseMap);
    final sectionsRaw = (courseMap['course_sections'] as List?) ?? const [];
    final sections = sectionsRaw
        .map((e) => CourseSection.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    final enrollment = await _c
        .from('enrollments')
        .select()
        .eq('user_id', _uid)
        .eq('course_id', courseId)
        .eq('status', 'active')
        .maybeSingle();
    final enrolled = enrollment != null;

    final lessonIds = <String>[
      for (final s in sections) ...s.lessons.map((l) => l.id),
    ];
    var progress = <String, LessonProgress>{};
    if (lessonIds.isNotEmpty) {
      final progressRows = await _c
          .from('lesson_progress')
          .select()
          .eq('user_id', _uid)
          .inFilter('lesson_id', lessonIds);
      progress = <String, LessonProgress>{
        for (final m in progressRows)
          m['lesson_id'] as String: LessonProgress.fromMap(m),
      };
    }

    Lesson merge(Lesson l) {
      final p = progress[l.id];
      return l.copyWith(
        completed: p?.completed ?? false,
        positionSeconds: p?.positionSeconds ?? 0,
        accessible: enrolled || l.isFreePreview,
      );
    }

    final mergedSections = sections
        .map((s) => CourseSection(
              id: s.id,
              courseId: s.courseId,
              title: s.title,
              sortOrder: s.sortOrder,
              lessons: s.lessons.map(merge).toList(),
            ))
        .toList();

    return CourseDetails(
      course: course,
      sections: mergedSections,
      enrolled: enrolled,
      progress: progress,
    );
  }

  /// Self-enroll into a free, published course (RLS enforces both).
  static Future<void> enroll(String courseId) async {
    await _c.from('enrollments').insert({
      'user_id': _uid,
      'course_id': courseId,
      'source': 'self',
    });
  }

  /// Save watch position and/or completion for a lesson.
  static Future<void> saveProgress(
    String lessonId, {
    int? positionSeconds,
    bool? completed,
  }) async {
    await _c.from('lesson_progress').upsert({
      'user_id': _uid,
      'lesson_id': lessonId,
      if (positionSeconds != null) 'position_seconds': positionSeconds,
      if (completed != null) 'completed': completed,
      if (completed == true) 'completed_at': DateTime.now().toIso8601String(),
      'last_viewed_at': DateTime.now().toIso8601String(),
    });
  }

  /// Most recently viewed enrolled lesson, for the home "continue" card.
  static Future<ContinueItem?> fetchContinueLearning() async {
    final rows = await _c
        .from('lesson_progress')
        .select('*, lessons(*, courses(*))')
        .eq('user_id', _uid)
        .order('last_viewed_at', ascending: false)
        .limit(5);
    for (final m in rows) {
      if (m['completed'] == true) continue;
      final lessonMap = m['lessons'];
      if (lessonMap == null) continue;
      final lesson = Lesson.fromMap(Map<String, dynamic>.from(lessonMap as Map));
      final courseMap = lessonMap['courses'];
      if (courseMap == null) continue;
      return ContinueItem(
        lesson: lesson,
        course: Course.fromMap(Map<String, dynamic>.from(courseMap as Map)),
        positionSeconds: (m['position_seconds'] as num?)?.toInt() ?? 0,
      );
    }
    return null;
  }
}

class CourseDetails {
  CourseDetails({
    required this.course,
    required this.sections,
    required this.enrolled,
    required this.progress,
  });

  final Course course;
  final List<CourseSection> sections;
  final bool enrolled;
  final Map<String, LessonProgress> progress;

  /// All lessons in display order: sectioned first, sectionless last.
  List<Lesson> get orderedLessons {
    final list = <Lesson>[];
    for (final s in sections) {
      list.addAll(s.lessons);
    }
    return list;
  }

  int get completedCount => orderedLessons.where((l) => l.completed).length;

  int get totalLessons => orderedLessons.length;

  int get percent =>
      totalLessons == 0 ? 0 : (100 * completedCount / totalLessons).round();

  /// The lesson "continue" should open: first incomplete accessible lesson.
  Lesson? get continueLesson {
    for (final l in orderedLessons) {
      if (!l.completed && l.accessible) return l;
    }
    return null;
  }
}
