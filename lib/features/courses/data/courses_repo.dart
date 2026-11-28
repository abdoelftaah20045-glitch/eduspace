import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/tenant.dart';
import '../../admin/data/admin_repo.dart';

import 'course_models.dart';

/// All Supabase access for the courses feature lives here.
/// RLS on the server is the real gate; these queries assume a signed-in user.
class CoursesRepository {
  CoursesRepository._();

  static SupabaseClient get _c => Supabase.instance.client;

  static String get _uid => _c.auth.currentUser!.id;

  /// Published courses, newest first, optional free-text filter.
  static Future<List<Course>> fetchCourses({String? query, int limit = 300}) async {
    // The server (RLS) decides who may see drafts: tenant admins get them,
    // students only ever get published rows.
    const admin = true;
    var q = _c
        .from('courses')
        .select()
        .inFilter('status', ['published', 'draft'])
        .eq('tenant_id', TenantContext.id);
    if (query != null && query.trim().isNotEmpty) {
      final pattern = '%${query.trim()}%';
      q = q.or('title.ilike.$pattern,description.ilike.$pattern,field.ilike.$pattern');
    }
    final rows = await q.order('created_at', ascending: false).limit(limit);
    return _mergeSocial(rows.map((m) {
      // Admins also see drafts (marked); students only ever get published.
      if (admin && m['status'] == 'draft') {
        return Course.fromMap({...m, 'title': '${m['title']}  (مسودة / draft)'});
      }
      return Course.fromMap(m);
    }).toList());
  }

  static String? _adminFor;
  static bool _adminVal = false;

  static Future<bool> _adminCached() async {
    final uid = _c.auth.currentUser?.id;
    if (uid == null) return false;
    if (_adminFor != uid) {
      _adminVal = await AdminRepository.isAdmin();
      _adminFor = uid;
    }
    return _adminVal;
  }

  /// Merges favorites and rating stats into courses.
  static Future<List<Course>> _mergeSocial(List<Course> courses) async {
    if (courses.isEmpty) return courses;
    final ids = courses.map((c) => c.id).toList();
    Set<String> favorites = {};
    try {
      final favRows = await _c
          .from('favorites')
          .select('course_id')
          .eq('user_id', _uid)
          .eq('tenant_id', TenantContext.id)
          .inFilter('course_id', ids);
      favorites = favRows.map((m) => m['course_id'] as String).toSet();
    } catch (_) {}
    final ratingSum = <String, double>{};
    final ratingCount = <String, int>{};
    try {
      final reviewRows = await _c
          .from('course_reviews')
          .select('course_id, rating')
          .inFilter('course_id', ids);
      for (final m in reviewRows) {
        final id = m['course_id'] as String;
        ratingSum[id] =
            (ratingSum[id] ?? 0) + ((m['rating'] as num?)?.toDouble() ?? 0);
        ratingCount[id] = (ratingCount[id] ?? 0) + 1;
      }
    } catch (_) {}
    return [
      for (final c in courses)
        c.withSocial(
          isFavorite: favorites.contains(c.id),
          ratingAvg: (ratingCount[c.id] ?? 0) > 0
              ? ratingSum[c.id]! / ratingCount[c.id]!
              : null,
          ratingCount: ratingCount[c.id] ?? 0,
        ),
    ];
  }

  /// Courses the current user is enrolled in, with progress percent.
  static Future<List<Course>> fetchMyCourses() async {
    final rows = await _c
        .from('enrollments')
        .select('*, courses(*)')
        .eq('user_id', _uid)
        .eq('status', 'active')
        .eq('tenant_id', TenantContext.id)
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
        discountPercent: course.discountPercent,
        discountStartsAt: course.discountStartsAt,
        discountEndsAt: course.discountEndsAt,
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
  /// Members count + a few avatars (needs SQL part 23; zeros otherwise).
  static Future<({int n, List<String> avatars})> fetchMembers(
      String courseId) async {
    try {
      final r = await _c.rpc('course_members', params: {'p_course': courseId});
      final m = Map<String, dynamic>.from(r as Map);
      return (
        n: (m['n'] as num?)?.toInt() ?? 0,
        avatars: [for (final a in (m['avatars'] as List? ?? const [])) '$a'],
      );
    } catch (_) {
      return (n: 0, avatars: <String>[]);
    }
  }

  /// Live sessions linked to the course, soonest first (weekly calendar).
  static Future<List<Map<String, dynamic>>> fetchCourseLives(
      String courseId) async {
    try {
      final rows = await _c
          .from('live_sessions')
          .select('id, title, starts_at, duration_minutes, status')
          .eq('course_id', courseId)
          .order('starts_at');
      return List<Map<String, dynamic>>.from(rows);
    } catch (_) {
      return [];
    }
  }

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

    // Lessons locked until the previous lesson's exam is passed (server decides).
    var locked = <String>{};
    if (enrolled) {
      try {
        final r = await _c.rpc('locked_lessons', params: {'p_course': courseId});
        locked = {for (final x in (r as List)) '$x'};
      } catch (_) {}
    }

    Lesson merge(Lesson l) {
      final p = progress[l.id];
      return l.copyWith(
        completed: p?.completed ?? false,
        positionSeconds: p?.positionSeconds ?? 0,
        accessible: (enrolled || l.isFreePreview) &&
            !locked.contains(l.id) &&
            !(l.availability == 'date' &&
                l.availableAt != null &&
                l.availableAt!.isAfter(DateTime.now())),
      );
    }

    final mergedSections = sections
        .map((s) => CourseSection(
              id: s.id,
              courseId: s.courseId,
              title: s.title,
              sortOrder: s.sortOrder,
              lessons: s.lessons.where((l) => !l.isHidden).map(merge).toList(),
            ))
        .toList();

    final mergedCourse = (await _mergeSocial([course])).first;
    return CourseDetails(
      course: mergedCourse,
      sections: mergedSections,
      enrolled: enrolled,
      progress: progress,
    );
  }

  // ---------- favorites & reviews (doc 20) ----------

  static Future<void> setFavorite(String courseId, bool favorite) async {
    if (favorite) {
      await _c.from('favorites').upsert({
        'user_id': _uid,
        'course_id': courseId,
        'tenant_id': TenantContext.id,
      });
    } else {
      await _c
          .from('favorites')
          .delete()
          .eq('user_id', _uid)
          .eq('course_id', courseId);
    }
  }

  /// Favorite courses, newest favorite first.
  static Future<List<Course>> fetchFavoriteCourses() async {
    final rows = await _c
        .from('favorites')
        .select('*, courses(*)')
        .eq('user_id', _uid)
        .eq('tenant_id', TenantContext.id)
        .order('created_at', ascending: false);
    final courses = <Course>[];
    for (final m in rows) {
      final c = m['courses'];
      if (c == null) continue;
      courses.add(Course.fromMap(Map<String, dynamic>.from(c as Map))
          .withSocial(isFavorite: true));
    }
    return _mergeSocial(courses);
  }

  static Future<List<CourseReview>> fetchReviews(String courseId) async {
    final rows = await _c
        .from('course_reviews')
        .select('*, profiles(full_name)')
        .eq('course_id', courseId)
        .order('created_at', ascending: false)
        .limit(50);
    return rows
        .map((m) => CourseReview.fromMap(m, viewerId: _uid))
        .toList();
  }

  static Future<void> upsertReview(
      String courseId, int rating, String body) async {
    await _c.from('course_reviews').upsert({
      'user_id': _uid,
      'course_id': courseId,
      'tenant_id': TenantContext.id,
      'rating': rating,
      'body': body.trim(),
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'user_id,course_id');
  }

  /// Self-enroll into a free, published course (RLS enforces both).
  static Future<void> enroll(String courseId) async {
    await _c.from('enrollments').insert({
      'user_id': _uid,
      'course_id': courseId,
      'source': 'self',
      'tenant_id': TenantContext.id,
    });
  }

  /// Save watch position and/or completion for a lesson.
  static Future<void> saveProgress(
    String lessonId, {
    int? positionSeconds,
    bool? completed,
    int? watchedSeconds,
  }) async {
    final row = {
      'user_id': _uid,
      'lesson_id': lessonId,
      if (positionSeconds != null) 'position_seconds': positionSeconds,
      if (completed != null) 'completed': completed,
      if (completed == true) 'completed_at': DateTime.now().toIso8601String(),
      'last_viewed_at': DateTime.now().toIso8601String(),
    };
    if (watchedSeconds != null) {
      try {
        await _c
            .from('lesson_progress')
            .upsert({...row, 'watched_seconds': watchedSeconds});
        return;
      } catch (e) {
        // Server rejected completion: not watched enough. Anything else
        // (e.g. SQL 21 not run yet) falls back to the plain save.
        if (e.toString().contains('watch_required')) rethrow;
      }
    }
    await _c.from('lesson_progress').upsert(row);
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
