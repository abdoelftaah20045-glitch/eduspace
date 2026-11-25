import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../certificates/data/certificates_repo.dart';
import 'data/course_models.dart';
import 'data/courses_repo.dart';
import 'lesson_screen.dart';

/// Course page: meta, enroll button, progress, sections and lessons.
class CourseDetailsScreen extends StatefulWidget {
  const CourseDetailsScreen({super.key, required this.courseId});

  final String courseId;

  @override
  State<CourseDetailsScreen> createState() => _CourseDetailsScreenState();
}

class _CourseDetailsScreenState extends State<CourseDetailsScreen> {
  CourseDetails? _details;
  String? _error;
  bool _enrolling = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final details = await CoursesRepository.fetchCourseDetails(widget.courseId);
      if (!mounted) return;
      setState(() {
        _details = details;
        _error = null;
      });
      // A fully completed course earns its certificate automatically.
      if (details.enrolled && details.percent == 100) {
        CertificatesRepository.ensureIssued(details).catchError((_) {});
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'load');
    }
  }

  Future<void> _enroll() async {
    setState(() => _enrolling = true);
    try {
      await CoursesRepository.enroll(widget.courseId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.of(context).t('enroll_success'))),
      );
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.of(context).t('generic_error'))),
      );
    } finally {
      if (mounted) setState(() => _enrolling = false);
    }
  }

  void _openLesson(Lesson lesson) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(builder: (_) => LessonScreen(lesson: lesson)),
        )
        .then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final details = _details;
    return Scaffold(
      appBar: AppBar(title: Text(details?.course.title ?? '')),
      body: _error != null
          ? Center(child: Text(s.t('generic_error')))
          : details == null
              ? const Center(child: CircularProgressIndicator())
              : _buildContent(context, s, details),
    );
  }

  Widget _buildContent(BuildContext context, S s, CourseDetails details) {
    final course = details.course;
    final theme = Theme.of(context);
    return ListView(
      children: [
        if (course.coverUrl != null && course.coverUrl!.isNotEmpty)
          AspectRatio(
            aspectRatio: 16 / 8,
            child: Image.network(
              course.coverUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(course.title, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  _Meta(icon: Icons.play_lesson, label: '${details.totalLessons} ${s.t('lessons')}'),
                  if (course.hours != null && course.hours! > 0)
                    _Meta(icon: Icons.schedule, label: '${course.hours} ${s.t('hours')}'),
                  if (course.level != null)
                    _Meta(icon: Icons.signal_cellular_alt, label: s.t('level_${course.level}')),
                  if (course.field != null && course.field!.isNotEmpty)
                    _Meta(icon: Icons.category_outlined, label: course.field!),
                ],
              ),
              if (course.instructorName != null &&
                  course.instructorName!.isNotEmpty) ...[
                const SizedBox(height: 8),
                _Meta(icon: Icons.person_outline, label: course.instructorName!),
              ],
              const SizedBox(height: 16),
              if (course.description.isNotEmpty)
                Text(course.description, style: theme.textTheme.bodyMedium),
              if (course.prerequisites != null &&
                  course.prerequisites!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(s.t('prerequisites'),
                    style: theme.textTheme.titleSmall),
                Text(course.prerequisites!),
              ],
              const SizedBox(height: 20),
              _buildAction(context, s, details),
              const SizedBox(height: 24),
            ],
          ),
        ),
        ...details.sections.map((section) => _SectionTile(
              section: section,
              onLessonTap: _openLesson,
            )),
        if (details.sections.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Center(child: Text(s.t('no_lessons'))),
          ),
      ],
    );
  }

  Widget _buildAction(BuildContext context, S s, CourseDetails details) {
    final theme = Theme.of(context);
    if (details.enrolled) {
      final next = details.continueLesson;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: LinearProgressIndicator(value: details.percent / 100),
              ),
              const SizedBox(width: 12),
              Text('${details.percent}%'),
            ],
          ),
          const SizedBox(height: 12),
          if (next != null)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _openLesson(next),
                icon: const Icon(Icons.play_arrow),
                label: Text(s.t('continue_learning')),
              ),
            ),
        ],
      );
    }
    if (details.course.isFree) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: _enrolling ? null : _enroll,
          icon: _enrolling
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.add),
          label: Text(s.t('enroll')),
        ),
      );
    }
    return Card(
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.payments_outlined),
            const SizedBox(width: 12),
            Expanded(child: Text(s.t('paid_contact_admin'))),
          ],
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _SectionTile extends StatelessWidget {
  const _SectionTile({required this.section, required this.onLessonTap});

  final CourseSection section;
  final void Function(Lesson) onLessonTap;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return ExpansionTile(
      initiallyExpanded: true,
      title: Text(section.title),
      subtitle: Text('${section.lessons.length} ${s.t('lessons')}'),
      children: section.lessons
          .map((lesson) => ListTile(
                leading: Icon(_iconFor(lesson.type)),
                title: Text(lesson.title),
                subtitle: lesson.durationSeconds != null
                    ? Text('${(lesson.durationSeconds! / 60).ceil()} ${s.t('minutes')}')
                    : null,
                trailing: lesson.completed
                    ? Icon(Icons.check_circle,
                        color: Theme.of(context).colorScheme.primary)
                    : lesson.accessible
                        ? null
                        : const Icon(Icons.lock_outline),
                enabled: lesson.accessible,
                onTap: lesson.accessible ? () => onLessonTap(lesson) : null,
              ))
          .toList(),
    );
  }

  static IconData _iconFor(String type) {
    return switch (type) {
      'video' => Icons.play_circle_outline,
      'text' => Icons.article_outlined,
      'pdf' => Icons.picture_as_pdf_outlined,
      'document' => Icons.description_outlined,
      'presentation' => Icons.slideshow_outlined,
      'audio' => Icons.headphones_outlined,
      'link' => Icons.link,
      'live' => Icons.videocam_outlined,
      'quiz' => Icons.quiz_outlined,
      'assignment' => Icons.assignment_outlined,
      _ => Icons.article_outlined,
    };
  }
}
