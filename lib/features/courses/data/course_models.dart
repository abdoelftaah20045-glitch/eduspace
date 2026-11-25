/// Data models for the courses feature. Plain classes parsed from
/// PostgREST maps; no code generation.
library;

class Course {
  Course({
    required this.id,
    required this.title,
    required this.description,
    this.coverUrl,
    this.field,
    this.level,
    this.instructorName,
    this.language = 'ar',
    this.prerequisites,
    this.hours,
    this.price = 0,
    this.currency = 'EGP',
    this.status = 'draft',
    this.visibility = 'everyone',
    this.lessonsSequential = false,
    this.isEnrolled = false,
    this.progressPercent,
  });

  final String id;
  final String title;
  final String description;
  final String? coverUrl;
  final String? field;
  final String? level;
  final String? instructorName;
  final String language;
  final String? prerequisites;
  final double? hours;
  final double price;
  final String currency;
  final String status;
  final String visibility;
  final bool lessonsSequential;

  /// Filled in by the repository when the current user is enrolled.
  final bool isEnrolled;
  final int? progressPercent;

  bool get isFree => price <= 0;

  factory Course.fromMap(Map<String, dynamic> m) {
    return Course(
      id: m['id'] as String,
      title: (m['title'] as String?) ?? '',
      description: (m['description'] as String?) ?? '',
      coverUrl: m['cover_url'] as String?,
      field: m['field'] as String?,
      level: m['level'] as String?,
      instructorName: m['instructor_name'] as String?,
      language: (m['language'] as String?) ?? 'ar',
      prerequisites: m['prerequisites'] as String?,
      hours: (m['hours'] as num?)?.toDouble(),
      price: (m['price'] as num?)?.toDouble() ?? 0,
      currency: (m['currency'] as String?) ?? 'EGP',
      status: (m['status'] as String?) ?? 'draft',
      visibility: (m['visibility'] as String?) ?? 'everyone',
      lessonsSequential: (m['lessons_sequential'] as bool?) ?? false,
    );
  }
}

class CourseSection {
  CourseSection({
    required this.id,
    required this.courseId,
    required this.title,
    required this.sortOrder,
    this.lessons = const [],
  });

  final String id;
  final String courseId;
  final String title;
  final int sortOrder;
  final List<Lesson> lessons;

  factory CourseSection.fromMap(Map<String, dynamic> m) {
    final rawLessons = (m['lessons'] as List?) ?? const [];
    final lessons = rawLessons
        .map((e) => Lesson.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return CourseSection(
      id: m['id'] as String,
      courseId: m['course_id'] as String,
      title: (m['title'] as String?) ?? '',
      sortOrder: (m['sort_order'] as num?)?.toInt() ?? 0,
      lessons: lessons,
    );
  }
}

class Lesson {
  Lesson({
    required this.id,
    required this.courseId,
    this.sectionId,
    required this.title,
    this.type = 'text',
    this.content = '',
    this.mediaUrl,
    this.durationSeconds,
    this.isFreePreview = false,
    this.availability = 'open',
    this.availableAt,
    this.sortOrder = 0,
    this.completed = false,
    this.positionSeconds = 0,
    this.accessible = false,
  });

  final String id;
  final String courseId;
  final String? sectionId;
  final String title;
  final String type;
  final String content;
  final String? mediaUrl;
  final int? durationSeconds;
  final bool isFreePreview;
  final String availability;
  final DateTime? availableAt;
  final int sortOrder;

  /// Client-side state merged from lesson_progress and enrollment checks.
  final bool completed;
  final int positionSeconds;
  final bool accessible;

  Lesson copyWith({bool? completed, int? positionSeconds, bool? accessible}) {
    return Lesson(
      id: id,
      courseId: courseId,
      sectionId: sectionId,
      title: title,
      type: type,
      content: content,
      mediaUrl: mediaUrl,
      durationSeconds: durationSeconds,
      isFreePreview: isFreePreview,
      availability: availability,
      availableAt: availableAt,
      sortOrder: sortOrder,
      completed: completed ?? this.completed,
      positionSeconds: positionSeconds ?? this.positionSeconds,
      accessible: accessible ?? this.accessible,
    );
  }

  factory Lesson.fromMap(Map<String, dynamic> m) {
    return Lesson(
      id: m['id'] as String,
      courseId: m['course_id'] as String,
      sectionId: m['section_id'] as String?,
      title: (m['title'] as String?) ?? '',
      type: (m['type'] as String?) ?? 'text',
      content: (m['content'] as String?) ?? '',
      mediaUrl: m['media_url'] as String?,
      durationSeconds: (m['duration_seconds'] as num?)?.toInt(),
      isFreePreview: (m['is_free_preview'] as bool?) ?? false,
      availability: (m['availability'] as String?) ?? 'open',
      availableAt: m['available_at'] != null
          ? DateTime.tryParse(m['available_at'] as String)
          : null,
      sortOrder: (m['sort_order'] as num?)?.toInt() ?? 0,
    );
  }
}

class Enrollment {
  Enrollment({
    required this.id,
    required this.userId,
    required this.courseId,
    this.status = 'active',
    this.course,
  });

  final String id;
  final String userId;
  final String courseId;
  final String status;
  final Course? course;

  factory Enrollment.fromMap(Map<String, dynamic> m) {
    return Enrollment(
      id: m['id'] as String,
      userId: m['user_id'] as String,
      courseId: m['course_id'] as String,
      status: (m['status'] as String?) ?? 'active',
      course: m['courses'] != null
          ? Course.fromMap(Map<String, dynamic>.from(m['courses'] as Map))
          : null,
    );
  }
}

class LessonProgress {
  LessonProgress({
    required this.lessonId,
    this.positionSeconds = 0,
    this.completed = false,
    this.lastViewedAt,
  });

  final String lessonId;
  final int positionSeconds;
  final bool completed;
  final DateTime? lastViewedAt;

  factory LessonProgress.fromMap(Map<String, dynamic> m) {
    return LessonProgress(
      lessonId: m['lesson_id'] as String,
      positionSeconds: (m['position_seconds'] as num?)?.toInt() ?? 0,
      completed: (m['completed'] as bool?) ?? false,
      lastViewedAt: m['last_viewed_at'] != null
          ? DateTime.tryParse(m['last_viewed_at'] as String)
          : null,
    );
  }
}

/// One row of the "continue learning" card: the most recently viewed lesson.
class ContinueItem {
  ContinueItem({required this.lesson, required this.course, this.positionSeconds = 0});

  final Lesson lesson;
  final Course course;
  final int positionSeconds;
}
