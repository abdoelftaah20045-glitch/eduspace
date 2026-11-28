import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../courses/course_details_screen.dart';

import '../courses/data/course_models.dart';
import '../courses/data/courses_repo.dart';
import '../exams/data/exam_models.dart';
import '../exams/data/exams_repo.dart';
import '../exams/exam_instructions_screen.dart';
import '../planner/study_planner_screen.dart';
import 'home_widgets.dart';

Widget _title(BuildContext context, String t, {Widget? trailing}) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Expanded(
          child: Text(t,
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).colorScheme.onSurface)),
        ),
        if (trailing != null) trailing,
      ]),
    );

/// "خطتك النهاردة": three small steps, opens the study planner.
class HomePlanCard extends StatelessWidget {
  const HomePlanCard({super.key, this.continueTitle, this.onContinue});

  final String? continueTitle;
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget step(IconData i, String t, {VoidCallback? onTap}) => InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                    color: scheme.surface, shape: BoxShape.circle),
                child: Icon(i, size: 18, color: scheme.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(t,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13))),
            ]),
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _title(context, 'خطتك النهاردة',
          trailing: TextButton(
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const StudyPlannerScreen())),
              child: const Text('المخطط'))),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
        decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(16)),
        child: Column(children: [
          step(Icons.play_arrow_rounded,
              continueTitle == null || continueTitle!.isEmpty
                  ? 'ابدأ درس جديد من كورساتك'
                  : 'كمّل: $continueTitle',
              onTap: onContinue),
          step(Icons.check_circle_outline, 'حل اختبار الدرس بعد الفيديو'),
          step(Icons.menu_book_outlined, 'اقرأ 10 صفحات من كتاب'),
        ]),
      ),
      const SizedBox(height: 24),
    ]);
  }
}

/// Quote / tip of the day, rotating by date.
class HomeQuote extends StatelessWidget {
  const HomeQuote({super.key});

  static const _tips = [
    'التعلم رحلة مش سباق، خطوة صغيرة كل يوم بتفرق.',
    'المذاكرة 25 دقيقة وراحة 5 دقايق بتخلي التركيز أعلى.',
    'اللي بيراجع اللي اتعلمه بعد يوم بيفتكر أكتر بكتير.',
    'اشرح اللي اتعلمته بكلامك، لو عرفت تشرحه يبقى فهمته.',
    'النوم الكويس جزء من المذاكرة مش بديل عنها.',
    'الغلط في التمرين بيعلّمك أكتر من الإجابة الصح من أول مرة.',
    'قسّم الهدف الكبير لمهام صغيرة وخلّص واحدة كل يوم.',
    'اكتب أسئلتك أثناء الفيديو، وارجع لها بعد ما يخلص.',
    'الاستمرارية أهم من الحماس، ولو 10 دقايق كل يوم.',
    'اللي بيتعلم النهاردة بيسبق نفسه بكرة.',
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final day = now.difference(DateTime(now.year)).inDays;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            gradient: LinearGradient(
                colors: [scheme.primary, scheme.primary.withValues(alpha: .75)]),
            borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          Icon(Icons.auto_awesome, color: scheme.onPrimary),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('معلومة اليوم',
                    style: TextStyle(
                        color: scheme.onPrimary.withValues(alpha: .85),
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(_tips[day % _tips.length],
                    style: TextStyle(
                        color: scheme.onPrimary,
                        fontWeight: FontWeight.w700,
                        height: 1.4)),
              ])),
        ]),
      ),
      const SizedBox(height: 24),
    ]);
  }
}

/// Standalone exams suggested to the student.
class HomeSuggestedExams extends StatefulWidget {
  const HomeSuggestedExams({super.key});

  @override
  State<HomeSuggestedExams> createState() => _HomeSuggestedExamsState();
}

class _HomeSuggestedExamsState extends State<HomeSuggestedExams> {
  List<Exam> _exams = const [];

  @override
  void initState() {
    super.initState();
    ExamsRepository.fetchExams().then((r) {
      if (mounted) setState(() => _exams = r.take(8).toList());
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    if (_exams.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _title(context, 'اختبارات مقترحة ليك'),
      SizedBox(
        height: 112,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _exams.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (_, i) {
            final e = _exams[i];
            return InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ExamInstructionsScreen(exam: e))),
              child: Container(
                width: 190,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: scheme.outlineVariant)),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.quiz_outlined, color: scheme.primary),
                      const SizedBox(height: 6),
                      Expanded(
                        child: Text(e.title,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 13)),
                      ),
                    ]),
              ),
            );
          },
        ),
      ),
      const SizedBox(height: 24),
    ]);
  }
}

/// Newest courses.
class HomeNewCourses extends StatefulWidget {
  const HomeNewCourses({super.key});

  @override
  State<HomeNewCourses> createState() => _HomeNewCoursesState();
}

class _HomeNewCoursesState extends State<HomeNewCourses> {
  List<Course> _list = const [];

  @override
  void initState() {
    super.initState();
    CoursesRepository.fetchCourses().then((r) {
      final l = r.where((c) => !c.title.contains('مسودة')).take(8).toList();
      if (mounted) setState(() => _list = l);
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    if (_list.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _title(context, 'كورسات جديدة'),
      SizedBox(
        height: 250,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _list.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (_, i) => FeaturedCourseCard(course: _list[i]),
        ),
      ),
      const SizedBox(height: 24),
    ]);
  }
}

/// A different set of lesson videos from inside the courses on every visit.
/// The pool is fetched once (random slice) and kept in memory, so remounting
/// the section only reshuffles it, instantly.
class HomeVideos extends StatefulWidget {
  const HomeVideos({super.key});

  /// Emptied on pull-to-refresh so the next build fetches a new random slice.
  static List<Map<String, dynamic>> pool = [];

  @override
  State<HomeVideos> createState() => _HomeVideosState();
}

class _HomeVideosState extends State<HomeVideos> {
  List<Map<String, dynamic>> _list = const [];

  static String? _yt(String? url) {
    if (url == null) return null;
    final m = RegExp(r'(?:youtu\.be/|v=|/embed/|/live/|/shorts/)([A-Za-z0-9_-]{11})')
        .firstMatch(url);
    return m?.group(1);
  }

  void _pick() {
    final l = [...HomeVideos.pool]..shuffle(math.Random());
    _list = l.take(12).toList();
  }

  @override
  void initState() {
    super.initState();
    if (HomeVideos.pool.isNotEmpty) {
      _pick();
    } else {
      _fetch();
    }
  }

  Future<void> _fetch() async {
    final db = Supabase.instance.client;
    Future<List<Map<String, dynamic>>> slice(int off) async {
      final r = await db
          .from('lessons')
          .select('id,title,course_id,media_url,courses(title)')
          .not('media_url', 'is', null)
          .range(off, off + 79);
      return List<Map<String, dynamic>>.from(r as List)
          .where((x) => _yt('${x['media_url']}') != null)
          .toList();
    }

    try {
      var r = <Map<String, dynamic>>[];
      try {
        r = await slice(math.Random().nextInt(1500));
      } catch (_) {}
      if (r.length < 6) r = await slice(0);
      HomeVideos.pool = r;
      if (mounted) setState(_pick);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_list.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _title(context, 'فيديوهات من الكورسات'),
      SizedBox(
        height: 168,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _list.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (_, i) {
            final x = _list[i];
            final id = _yt('${x['media_url']}');
            final cn = (x['courses'] is Map) ? '${x['courses']['title'] ?? ''}' : '';
            return InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => CourseDetailsScreen(courseId: '${x['course_id']}'))),
              child: SizedBox(
                width: 190,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Image.network('https://i.ytimg.com/vi/$id/hqdefault.jpg',
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const ColoredBox(color: Colors.black12)),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('${x['title']}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  if (cn.isNotEmpty)
                    Text(cn,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10.5, color: Colors.black54)),
                ]),
              ),
            );
          },
        ),
      ),
      const SizedBox(height: 20),
    ]);
  }
}
