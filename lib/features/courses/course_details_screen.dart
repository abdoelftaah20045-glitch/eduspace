import '../home/home_widgets.dart';
import 'package:flutter/material.dart';

import '../payments/payment_screen.dart';
import '../discussion/discussion_screen.dart';
import '../../core/l10n.dart';
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
        : '${course.price.toStringAsFixed(0)} ${course.currency}';
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
    final navy = theme.brightness == Brightness.dark
        ? scheme.primaryContainer
        : const Color(0xFF14264A);
    final onNavy = theme.brightness == Brightness.dark
        ? scheme.onPrimaryContainer
        : Colors.white;
    final tabs = <(int, String)>[
      (0, s.t('cd_about')),
      (1, s.t('cd_lessons')),
      (2, s.t('cd_reviews')),
      if (_lives.isNotEmpty) (3, s.t('cd_schedule')),
    ];
    String two(int n) => n.toString().padLeft(2, '0');
    String date(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';
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
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(fit: StackFit.expand, children: [
                Container(color: navy),
                if (course.coverUrl != null && course.coverUrl!.isNotEmpty)
                  Image.network(course.coverUrl!,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink())
                else
                  Center(
                      child: Icon(Icons.menu_book_rounded,
                          size: 72, color: onNavy.withValues(alpha: .6))),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: .15),
                          Colors.black.withValues(alpha: .78),
                        ],
                        stops: const [0.35, 0.6, 1],
                      ),
                    ),
                  ),
                ),
                PositionedDirectional(
                  start: 14,
                  end: 14,
                  bottom: 12,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (course.level != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Text(s.t('level_${course.level}'),
                                style: const TextStyle(
                                    color: Color(0xFF14264A),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(width: 4),
                            const Icon(Icons.signal_cellular_alt,
                                size: 13, color: Color(0xFFE53935)),
                          ]),
                        ),
                      Text(course.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800)),
                      if ((course.instructorName ?? '').isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(children: [
                            const Icon(Icons.person_outline,
                                size: 14, color: Colors.white70),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(course.instructorName!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 12.5)),
                            ),
                          ]),
                        ),
                    ],
                  ),
                ),
                if (false)
                  PositionedDirectional(
                    start: 10,
                    bottom: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(s.t('level_${course.level}'),
                            style: const TextStyle(
                                color: Color(0xFF14264A),
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(width: 4),
                        const Icon(Icons.signal_cellular_alt,
                            size: 13, color: Color(0xFFE53935)),
                      ]),
                    ),
                  ),
              ]),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Wrap(spacing: 16, runSpacing: 6, children: [
            _Meta(
                icon: Icons.groups_outlined,
                label: '$_members ${s.t('cd_students')}'),
            _Meta(
                icon: Icons.menu_book_outlined,
                label: '${details.totalLessons} ${s.t('lessons')}'),
            if (course.hours != null && course.hours! > 0)
              _Meta(
                  icon: Icons.schedule,
                  label: '${course.hours} ${s.t('hours')}'),
            if (course.ratingCount > 0)
              _Meta(
                  icon: Icons.star_outline,
                  label:
                      '${course.ratingAvg!.toStringAsFixed(1)} (${course.ratingCount})'),
          ]),
        ),
        const SizedBox(height: 12),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: .5),
              borderRadius: BorderRadius.circular(24)),
          child: Row(children: [
            for (final e in tabs)
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _tab = e.$1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: _tab == e.$1 ? navy : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Center(
                      child: Text(e.$2,
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: _tab == e.$1
                                  ? onNavy
                                  : scheme.onSurfaceVariant)),
                    ),
                  ),
                ),
              ),
          ]),
        ),
        if (_tab == 0)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _introCard(context, s, details),
                const SizedBox(height: 16),
                if (course.description.isNotEmpty) ...[
                  Text(s.t('cd_about'),
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  ExpandableText(course.description,
                      style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 16),
                ],
                if (course.instructorName != null &&
                    course.instructorName!.isNotEmpty)
                  Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: scheme.primaryContainer,
                        backgroundImage:
                            (course.instructorPhotoUrl ?? '').isNotEmpty
                                ? NetworkImage(course.instructorPhotoUrl!)
                                : null,
                        child: (course.instructorPhotoUrl ?? '').isEmpty
                            ? const Icon(Icons.person)
                            : null,
                      ),
                      title: Text(course.instructorName!,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(s.t('cd_instructor')),
                    ),
                  ),
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                        color: scheme.primary.withValues(alpha: .25)),
                  ),
                  child: Wrap(spacing: 28, runSpacing: 12, children: [
                    _Meta(
                        icon: Icons.menu_book,
                        label: '${details.totalLessons} ${s.t('lessons')}'),
                    _Meta(
                        icon: Icons.workspace_premium_outlined,
                        label: s.t('cd_certificate')),
                    if (course.hours != null && course.hours! > 0)
                      _Meta(
                          icon: Icons.schedule,
                          label: '${course.hours} ${s.t('hours')}'),
                  ]),
                ),
                if (course.skills.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(s.t('cd_skills').split(' (').first,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final k in course.skills)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: scheme.outlineVariant)),
                        child: Text(k, style: const TextStyle(fontSize: 13)),
                      ),
                  ]),
                  const SizedBox(height: 8),
                ],
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(children: [
                      Text(s.t('cd_members'),
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      const Spacer(),
                      SizedBox(
                        height: 28,
                        child: Stack(children: [
                          for (var i = 0; i < _avatars.length; i++)
                            PositionedDirectional(
                              end: i * 18.0,
                              child: CircleAvatar(
                                radius: 14,
                                backgroundImage: NetworkImage(_avatars[i]),
                              ),
                            ),
                          SizedBox(width: 28.0 + _avatars.length * 18),
                        ]),
                      ),
                      const SizedBox(width: 8),
                      Text('+$_members ${s.t('cd_students')}',
                          style: TextStyle(
                              color: scheme.primary,
                              fontWeight: FontWeight.w700,
                              fontSize: 12)),
                    ]),
                  ),
                ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.t('cd_details'),
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 15)),
                        const SizedBox(height: 6),
                        if (course.field != null && course.field!.isNotEmpty)
                          row(s.t('cd_category'), course.field!),
                        if (course.level != null)
                          row(s.t('level_label'), s.t('level_${course.level}')),
                        row(s.t('cd_language'), course.language.toUpperCase()),
                        row(
                            s.t('cd_students'),
                            course.maxStudents != null
                                ? '$_members (max ${course.maxStudents})'
                                : '$_members'),
                        if (course.availableAt != null)
                          row(s.t('cd_start'), date(course.availableAt!)),
                        if (course.availableUntil != null)
                          row(s.t('cd_end'), date(course.availableUntil!)),
                        if (course.hours != null && course.hours! > 0)
                          row(s.t('hours'), '${course.hours}'),
                        if ((course.effort ?? '').isNotEmpty)
                          row(s.t('cd_effort'), course.effort!),
                        if ((course.goals ?? '').isNotEmpty)
                          row(s.t('cd_goals'), course.goals!),
                        if (course.prerequisites != null &&
                            course.prerequisites!.isNotEmpty)
                          row(s.t('prerequisites'), course.prerequisites!),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (_tab == 1)
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
        if (_tab == 1 && details.sections.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Center(child: Text(s.t('no_lessons'))),
          ),
        if (_tab == 2)
          ReviewsSection(
            courseId: widget.courseId,
            enrolled: details.enrolled,
          ),
        if (_tab == 3)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Text(s.t('cd_complete'),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                            const Spacer(),
                            Text('${details.percent}%',
                                style: TextStyle(
                                    color: scheme.primary,
                                    fontWeight: FontWeight.w800)),
                          ]),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                              value: details.percent / 100,
                              minHeight: 8,
                              borderRadius: BorderRadius.circular(6)),
                        ]),
                  ),
                ),
                Text(s.t('cd_weekly'),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 8),
                for (var i = 0; i < _lives.length; i++)
                  Builder(builder: (_) {
                    final l = _lives[i];
                    final st = DateTime.tryParse('${l['starts_at']}')?.toLocal();
                    final dur = (l['duration_minutes'] as num?)?.toInt() ?? 60;
                    final en = st?.add(Duration(minutes: dur));
                    String hm(DateTime d) => '${two(d.hour)}:${two(d.minute)}';
                    final next = st != null && st.isAfter(DateTime.now());
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
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
                                  fontSize: 12,
                                  color: scheme.onSurfaceVariant)),
                      ]),
                    );
                  }),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildAction(BuildContext context, S s, CourseDetails details) {
    if (details.enrolled) return _actionButton(context, s, details);
    final price = details.course.isFree || !PaidCourses.enabled.value
        ? s.t('free')
        : '${details.course.price.toStringAsFixed(2)} ${details.course.currency}';
    return Row(children: [
      Text(price,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
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
              price: details.course.price,
            ),
          ));
          _load();
        },
        icon: const Icon(Icons.payments_outlined),
        label: Text(
            '${s.t('pay_title')} · ${details.course.price.toStringAsFixed(2)}'),
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
      title: Text('${_roman(index + 1)} - ${section.title}',
          style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text('${section.lessons.length} ${s.t('lessons')}'),
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
              enabled: lesson.accessible,
              onTap: lesson.accessible ? () => onLessonTap(lesson) : null,
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
