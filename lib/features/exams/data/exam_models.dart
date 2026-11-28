/// Data models for exams. Plain classes parsed from PostgREST maps.
library;

class Exam {
  Exam({
    required this.id,
    required this.title,
    this.description = '',
    this.courseId,
    this.durationMinutes,
    this.passGrade = 0,
    this.maxAttempts = 1,
    this.shuffleQuestions = false,
    this.status = 'draft',
    this.availableFrom,
    this.availableUntil,
    this.attemptCount = 0,
    this.bestScore,
    this.bestMaxScore,
  });

  final String id;
  final String title;
  final String description;
  final String? courseId;
  final int? durationMinutes;
  final double passGrade;
  final int maxAttempts;
  final bool shuffleQuestions;
  final String status;
  final DateTime? availableFrom;
  final DateTime? availableUntil;

  /// Client-side: attempts the current user already made, and best score.
  final int attemptCount;
  final double? bestScore;
  final double? bestMaxScore;

  bool get isOpen {
    final now = DateTime.now();
    if (availableFrom != null && now.isBefore(availableFrom!)) return false;
    if (availableUntil != null && now.isAfter(availableUntil!)) return false;
    return true;
  }

  bool get attemptsExhausted => attemptCount >= maxAttempts;

  factory Exam.fromMap(Map<String, dynamic> m) {
    return Exam(
      id: m['id'] as String,
      title: (m['title'] as String?) ?? '',
      description: (m['description'] as String?) ?? '',
      courseId: m['course_id'] as String?,
      durationMinutes: (m['duration_minutes'] as num?)?.toInt(),
      passGrade: (m['pass_grade'] as num?)?.toDouble() ?? 0,
      maxAttempts: (m['max_attempts'] as num?)?.toInt() ?? 1,
      shuffleQuestions: (m['shuffle_questions'] as bool?) ?? false,
      status: (m['status'] as String?) ?? 'draft',
      availableFrom: m['available_from'] != null
          ? DateTime.tryParse(m['available_from'] as String)
          : null,
      availableUntil: m['available_until'] != null
          ? DateTime.tryParse(m['available_until'] as String)
          : null,
    );
  }
}

class ExamQuestion {
  ExamQuestion({
    required this.id,
    required this.type,
    required this.body,
    this.points = 1,
    this.options = const [],
    this.bankId,
  });

  final String? bankId;
  final String id;
  final String type; // mcq, true_false, multi, fill_blank, essay
  final String body;
  final double points;
  final List<ExamOption> options;

  factory ExamQuestion.fromMap(Map<String, dynamic> m) {
    final rawOptions = (m['question_options'] as List?) ?? const [];
    final options = rawOptions
        .map((e) => ExamOption.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return ExamQuestion(
      id: m['id'] as String,
      type: (m['type'] as String?) ?? 'mcq',
      body: (m['body'] as String?) ?? '',
      points: (m['points'] as num?)?.toDouble() ?? 1,
      options: options,
      bankId: m['bank_id'] as String?,
    );
  }
}

class ExamOption {
  ExamOption({
    required this.id,
    required this.body,
    this.isCorrect = false,
    this.sortOrder = 0,
  });

  final String id;
  final String body;
  final bool isCorrect;
  final int sortOrder;

  factory ExamOption.fromMap(Map<String, dynamic> m) {
    return ExamOption(
      id: m['id'] as String,
      body: (m['body'] as String?) ?? '',
      isCorrect: (m['is_correct'] as bool?) ?? false,
      sortOrder: (m['sort_order'] as num?)?.toInt() ?? 0,
    );
  }
}
