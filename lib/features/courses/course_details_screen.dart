import '../../core/cached_avatar.dart';
import '../../core/maintenance.dart';
import 'price_view.dart';
import '../home/home_widgets.dart';
import 'package:flutter/material.dart';

import '../payments/payment_screen.dart';
import '../discussion/discussion_screen.dart';
import '../../core/l10n.dart';
import '../../core/remote_ui.dart';
import '../../core/paid_courses.dart';
import '../assignments/assignments_screen.dart';
import '../certificates/data/certificates_repo.dart';
import 'course_reviews.dart';
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
  bool _isFav = false;
  int _tab = 0;
  int _members = 0;
  List<String> _avatars = [];
  List<Map<String, dynamic>> _lives = [];

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
        _isFav = details.course.isFavorite;
      });
      CoursesRepository.fetchMembers(widget.courseId).then((m) {
        if (mounted) setState(() {
          _members = m.n;
          _avatars = m.avatars;
        });
      });
      CoursesRepository.fetchCourseLives(widget.courseId).then((r) {
        if (mounted) setState(() => _lives = r);
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
    if (!lesson.accessible) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('الدرس ده مقفول. كمّل مشاهدة الفيديو اللي قبله واعدّي اختباره الأول (أو سجّل في الكورس).')));
      return;
    }
    Navigator.of(context)
        .push(
          MaterialPageRoute(builder: (_) => LessonScreen(lesson: lesson)),
        )
        .then((_) => _load());
  }

  @override
  Widget build(BuildContext context) =>
      MaintenanceGate(pageKey: 'course_details', child: Builder(builder: _mtBuild));

  Widget _mtBuild(BuildContext context) {
    final s = S.of(context);
    final details = _details;
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const SizedBox.shrink(),
        actions: [
          IconButton(
            tooltip: s.t('favorites'),
            icon: Icon(
                _isFav ? Icons.favorite : Icons.favorite_border,
                color: _isFav ? Colors.redAccent : null),
            onPressed: () async {
              setState(() => _isFav = !_isFav);
              try {
                await CoursesRepository.setFavorite(
                    widget.courseId, _isFav);
              } catch (_) {
                if (mounted) setState(() => _isFav = !_isFav);
              }
            },
          ),
          if (details?.enrolled == true)
            IconButton(
              tooltip: s.t('disc_title_screen'),
              icon: const Icon(Icons.forum_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DiscussionScreen(courseId: widget.courseId),
                ),
              ),
            ),
          if (details?.enrolled == true)
            IconButton(
              tooltip: s.t('assignments_label'),
              icon: const Icon(Icons.assignment_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      AssignmentsScreen(courseId: widget.courseId),
                ),
              ),
            ),
        ],
      ),
      body: _error != null
          ? Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(s.t('generic_error')),
                const SizedBox(height: 8),
                OutlinedButton(onPressed: _load, child: Text(s.t('retry'))),
              ]),
            )
          : details == null
              ? const Center(child: CircularProgressIndicator())
              : Column(children: [
                  Expanded(child: _buildContent(context, s, details)),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                      child: _buildAction(context, s, details),
                    ),
                  ),
                ]),
    );
  }

  Widget _introCard(BuildContext context, S s, CourseDetails details) {
    final course = details.course;
    final scheme = Theme.of(context).colorScheme;
    final price = course.isFree || !PaidCourses.enabled.value
        ? s.t('free')
        : '${course.effectivePrice.toStringAsFixed(0)} ${course.currency}${course.hasDiscount ? '  (-${course.discountPercent!.toStringAsFixed(0)}%)' : ''}';
    final contents = <String>[
      for (final sec in details.sections)
        for (final l in sec.lessons) l.title,
    ].take(4).toList();
    Widget stat(String v, String label) => Expanded(
          child: Column(children: [
            Text(v,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800)),
            Text(label,
                style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ]),
        );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              scheme.primary,
              Color.lerp(scheme.primary, const Color(0xFF6C5CE7), .55)!
            ]),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
              color: scheme.primary.withValues(alpha: .3),
              blurRadius: 16,
              offset: const Offset(0, 8))
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(course.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(12)),
            child: Text(price,
                style: TextStyle(
                    color: scheme.primary, fontWeight: FontWeight.w800)),
          ),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          stat('$_members', s.t('cd_students')),
          stat(
              course.ratingCount > 0
                  ? course.ratingAvg!.toStringAsFixed(1)
                  : '-',
              s.t('cd_reviews')),
          stat('${details.totalLessons}', s.t('lessons')),
        ]),
        if (contents.isNotEmpty) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .16),
                borderRadius: BorderRadius.circular(16)),
            child: Column(children: [
              for (var i = 0; i < contents.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    CircleAvatar(
                        radius: 11,
                        backgroundColor: Colors.white,
                        child: Text('${i + 1}',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: scheme.primary))),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(contents[i],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13)),
                    ),
                  ]),
                ),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _buildContent(BuildContext context, S s, CourseDetails details) {
    final course = details.course;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final navy = dark ? scheme.primaryContainer : const Color(0xFF0B1F44);
    final onNavy = dark ? scheme.onPrimaryContainer : Colors.white;
    String two(int n) => n.toString().padLeft(2, '0');
    String date(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';
    Widget h(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 10),
          child: Text(t,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800)),
        );
    final allLessons = [for (final sec in details.sections) ...sec.lessons];
    final doneCount = allLessons.where((l) => l.completed).length;
    var learn = <String>[
      for (final g in (course.goals ?? '').split(RegExp(r'[\n\u2022;]')))
        if (g.trim().isNotEmpty) g.trim()
    ];
    if (learn.isEmpty) {
      learn = [
        for (final sec in details.sections)
          if (sec.title.trim().isNotEmpty) sec.title.trim()
      ].take(6).toList();
    }
    Widget stat(IconData i, String top, String bottom) => Expanded(
          child: Column(children: [
            Icon(i, size: 22, color: scheme.primary),
            const SizedBox(height: 6),
            Text(top,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 13)),
            Text(bottom,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11, color: scheme.onSurfaceVariant)),
          ]),
        );
    Widget row(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
                width: 110,
                child: Text(k,
                    style: TextStyle(
                        color: scheme.onSurfaceVariant, fontSize: 13))),
            Expanded(
                child: Text(v,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13))),
          ]),
        );
    final parts = <String, List<Widget>>{};
    List<Widget> _part(String id, List<Widget> w) {
      parts[id] = w;
      return const [];
    }
    final head = <Widget>[
        // Hero: cover then dark info block, like a Coursera course page.
        AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(fit: StackFit.expand, children: [
            Container(color: navy),
            if (course.coverUrl != null && course.coverUrl!.isNotEmpty)
              CachedImage(course.coverUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink())
            else
              Center(
                  child: Icon(Icons.menu_book_rounded,
                      size: 72, color: onNavy.withValues(alpha: .6))),
          ]),
        ),
        Container(
          color: navy,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if ((course.field ?? '').isNotEmpty)
                Text(course.field!.toUpperCase(),
                    style: TextStyle(
                        color: onNavy.withValues(alpha: .7),
                        fontSize: 11,
                        letterSpacing: .8,
                        fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(course.title,
                  style: TextStyle(
                      color: onNavy,
                      fontSize: 24,
                      height: 1.2,
                      fontWeight: FontWeight.w800)),
              if ((course.instructorName ?? '').isNotEmpty) ...[
                const SizedBox(height: 10),
                Row(children: [
                  CachedAvatar(
                    url: course.instructorPhotoUrl,
                    radius: 13,
                    backgroundColor: Colors.white24,
                    fallback: Icon(Icons.person, size: 16, color: onNavy),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                        '${s.t('cd_instructor')}: ${course.instructorName!}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: onNavy, fontSize: 13.5)),
                  ),
                ]),
              ],
              const SizedBox(height: 12),
              Wrap(spacing: 16, runSpacing: 6, children: [
                if (course.ratingCount > 0)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.star_rounded,
                        size: 18, color: Color(0xFFF29900)),
                    const SizedBox(width: 3),
                    Text(
                        '${course.ratingAvg!.toStringAsFixed(1)} (${course.ratingCount} ${s.t('cd_reviews')})',
                        style: TextStyle(color: onNavy, fontSize: 13)),
                  ]),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.groups_outlined, size: 18, color: onNavy),
                  const SizedBox(width: 4),
                  Text('$_members ${s.t('cd_students')}',
                      style: TextStyle(color: onNavy, fontSize: 13)),
                ]),
              ]),
            ],
          ),
        ),
        ..._part('course.progress', [
        if (details.enrolled)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(s.t('cd_complete'),
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  const Spacer(),
                  Text('${details.percent}%',
                      style: TextStyle(
                          color: scheme.primary, fontWeight: FontWeight.w800)),
                ]),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                      value: details.percent / 100, minHeight: 8),
                ),
                const SizedBox(height: 6),
                Text('$doneCount / ${allLessons.length} ${s.t('lessons')}',
                    style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ]),
        ..._part('course.stats', [
        Container(
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Row(children: [
            stat(Icons.signal_cellular_alt,
                course.level != null ? s.t('level_${course.level}') : '-',
                s.t('level_label')),
            stat(
                Icons.schedule,
                course.hours != null && course.hours! > 0
                    ? '${course.hours} ${s.t('hours')}'
                    : '${allLessons.length}',
                course.hours != null && course.hours! > 0
                    ? s.t('cd_effort')
                    : s.t('lessons')),
            stat(Icons.translate, course.language.toUpperCase(),
                s.t('cd_language')),
            stat(Icons.workspace_premium_outlined, s.t('cd_certificate'), ' '),
          ]),
        ),
        ]),
        ..._part('course.learn', [
        if (learn.isNotEmpty) ...[
          h(s.t('cd_learn')),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Column(children: [
              for (final g in learn)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.check, size: 20, color: scheme.primary),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Text(g,
                                style: const TextStyle(
                                    fontSize: 14, height: 1.35))),
                      ]),
                ),
            ]),
          ),
        ],
        ]),
        ..._part('course.skills', [
        if (course.skills.isNotEmpty) ...[
          h(s.t('cd_skills').split(' (').first),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final k in course.skills)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: .08),
                      borderRadius: BorderRadius.circular(20)),
                  child: Text(k,
                      style: TextStyle(
                          fontSize: 13,
                          color: scheme.primary,
                          fontWeight: FontWeight.w600)),
                ),
            ]),
          ),
        ],
        ]),
        ..._part('course.about', [
        if (course.description.isNotEmpty) ...[
          h(s.t('cd_about')),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child:
                ExpandableText(course.description, style: theme.textTheme.bodyMedium),
          ),
        ],
        ]),
        ..._part('course.syllabus', [
        h(s.t('cd_syllabus')),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(
              '${details.sections.length} ${s.t('cd_modules')} \u00b7 ${allLessons.length} ${s.t('lessons')}',
              style: theme.textTheme.bodySmall),
        ),
        if (details.sections.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Center(child: Text(s.t('no_lessons'))),
          ),
        ...List<Widget>.generate(details.sections.length, (si) {
          var n = 0;
          for (var k = 0; k < si; k++) {
            n += details.sections[k].lessons.length;
          }
          return _SectionTile(
            section: details.sections[si],
            index: si,
            startNumber: n,
            currentId: details.continueLesson?.id,
            onLessonTap: _openLesson,
          );
        }),
        ]),
        ..._part('course.schedule', [
        if (_lives.isNotEmpty) ...[
          h(s.t('cd_weekly')),
          for (var i = 0; i < _lives.length; i++)
            Builder(builder: (_) {
              final l = _lives[i];
              final st = DateTime.tryParse('${l['starts_at']}')?.toLocal();
              final dur = (l['duration_minutes'] as num?)?.toInt() ?? 60;
              final en = st?.add(Duration(minutes: dur));
              String hm(DateTime d) => '${two(d.hour)}:${two(d.minute)}';
              final next = st != null && st.isAfter(DateTime.now());
              return Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: next ? scheme.primary : scheme.outlineVariant,
                      width: next ? 1.6 : 1),
                ),
                child: Row(children: [
                  Text('${s.t('cd_session_no')} ${i + 1}',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const Spacer(),
                  if (st != null)
                    Text('${date(st)}  ${hm(st)} - ${hm(en!)}',
                        style: TextStyle(
                            fontSize: 12, color: scheme.onSurfaceVariant)),
                ]),
              );
            }),
        ],
        ]),
        ..._part('course.instructor', [
        if ((course.instructorName ?? '').isNotEmpty) ...[
          h(s.t('cd_instructor')),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: ListTile(
              leading: CachedAvatar(
                url: course.instructorPhotoUrl,
                radius: 20,
                backgroundColor: scheme.primaryContainer,
                fallback: const Icon(Icons.person),
              ),
              title: Text(course.instructorName!,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
        ]),
        ..._part('course.details', [
        h(s.t('cd_details')),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (course.field != null && course.field!.isNotEmpty)
                  row(s.t('cd_category'), course.field!),
                if (course.level != null)
                  row(s.t('level_label'), s.t('level_${course.level}')),
                row(s.t('cd_language'), course.language.toUpperCase()),
                if (course.availableAt != null)
                  row(s.t('cd_start'), date(course.availableAt!)),
                if (course.availableUntil != null)
                  row(s.t('cd_end'), date(course.availableUntil!)),
                if ((course.effort ?? '').isNotEmpty)
                  row(s.t('cd_effort'), course.effort!),
                if (course.prerequisites != null &&
                    course.prerequisites!.isNotEmpty)
                  row(s.t('prerequisites'), course.prerequisites!),
              ],
            ),
          ),
        ),
        ]),
        ..._part('course.reviews', [
        h(s.t('cd_reviews')),
        ReviewsSection(
          courseId: widget.courseId,
          enrolled: details.enrolled,
        ),
        ]),
    ];
    final keys = parts.keys.toList();
    final ids = keys.where(RemoteUi.visible).toList()
      ..sort((a, b) => RemoteUi.order(a, keys.indexOf(a))
          .compareTo(RemoteUi.order(b, keys.indexOf(b))));
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        ...head,
        for (final id in ids) ...parts[id]!,
      ],
    );
  }

  Widget _buildAction(BuildContext context, S s, CourseDetails details) {
    if (details.enrolled) return _actionButton(context, s, details);
    final price = details.course.isFree || !PaidCourses.enabled.value
        ? s.t('free')
        : '';
    return Row(children: [
      details.course.isFree || !PaidCourses.enabled.value
          ? Text(price,
              style:
                  const TextStyle(fontWeight: FontWeight.w800, fontSize: 18))
          : PriceView(course: details.course, size: 18),
      const SizedBox(width: 16),
      Expanded(child: _actionButton(context, s, details)),
    ]);
  }

  Widget _actionButton(BuildContext context, S s, CourseDetails details) {
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
    if (details.course.isFree || !PaidCourses.enabled.value) {
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
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: () async {
          await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => PaymentScreen(
              courseId: widget.courseId,
              title: details.course.title,
              price: details.course.effectivePrice,
            ),
          ));
          _load();
        },
        icon: const Icon(Icons.payments_outlined),
        label: Text(
            '${s.t('pay_title')} · ${details.course.effectivePrice.toStringAsFixed(2)}'),
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
  const _SectionTile(
      {required this.section,
      required this.onLessonTap,
      this.index = 0,
      this.startNumber = 0,
      this.currentId});

  final int index;
  final int startNumber;
  final String? currentId;
  final CourseSection section;
  final void Function(Lesson) onLessonTap;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return ExpansionTile(
      initiallyExpanded: true,
      title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${s.t('cd_module')} ${index + 1}',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
        Text(section.title,
            style: const TextStyle(fontWeight: FontWeight.w800)),
      ]),
      subtitle: Text(
          '${section.lessons.where((l) => l.completed).length}/${section.lessons.length} ${s.t('lessons')}'),
      children: [
        for (var i = 0; i < section.lessons.length; i++)
          Builder(builder: (_) {
            final lesson = section.lessons[i];
            final typeKey = 'type_${lesson.type}';
            final typeLabel = s.t(typeKey) == typeKey ? lesson.type : s.t(typeKey);
            final mins = lesson.durationSeconds != null
                ? ' · ${(lesson.durationSeconds! / 60).ceil()} ${s.t('minutes')}'
                : '';
            final isCurrent = lesson.id == currentId && lesson.accessible;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: isCurrent
                  ? BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: .08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: Theme.of(context).colorScheme.primary))
                  : null,
              child: ListTile(
              leading: SizedBox(
                width: 54,
                child: Row(children: [
                  Text('${(startNumber + i + 1).toString().padLeft(2, '0')}',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12)),
                  const SizedBox(width: 8),
                  Icon(_iconFor(lesson.type)),
                ]),
              ),
              title: Text(lesson.title,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('$typeLabel$mins'),
              trailing: lesson.completed
                  ? Icon(Icons.check_circle,
                      color: Theme.of(context).colorScheme.primary)
                  : isCurrent
                      ? Icon(Icons.play_arrow_rounded,
                          color: Theme.of(context).colorScheme.primary)
                      : lesson.accessible
                          ? null
                          : const Icon(Icons.lock_outline),
              onTap: () => onLessonTap(lesson),
            ));
          }),
      ],
    );
  }

  static String _roman(int n) {
    const m = [
      (10, 'X'), (9, 'IX'), (5, 'V'), (4, 'IV'), (1, 'I')
    ];
    var r = '';
    for (final e in m) {
      while (n >= e.$1) {
        r += e.$2;
        n -= e.$1;
      }
    }
    return r;
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
