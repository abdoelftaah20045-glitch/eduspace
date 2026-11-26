import '../../core/maintenance.dart';
import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import 'course_details_screen.dart';
import 'data/course_models.dart';
import 'data/courses_repo.dart';

/// My Courses: All / Ongoing / Completed with thumbnail, instructor,
/// duration and a progress bar per course.
class MyCoursesScreen extends StatefulWidget {
  const MyCoursesScreen({super.key});

  @override
  State<MyCoursesScreen> createState() => _MyCoursesScreenState();
}

class _MyCoursesScreenState extends State<MyCoursesScreen> {
  List<Course>? _items;
  bool _failed = false;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await CoursesRepository.fetchMyCourses()
          .timeout(const Duration(seconds: 20));
      if (mounted) {
        setState(() {
          _items = r;
          _failed = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) =>
      MaintenanceGate(pageKey: 'my_courses', child: Builder(builder: _mtBuild));

  Widget _mtBuild(BuildContext context) {
    final s = S.of(context);
    final scheme = Theme.of(context).colorScheme;
    final all = _items;
    final shown = all == null
        ? <Course>[]
        : all.where((c) {
            final p = c.progressPercent ?? 0;
            return _tab == 0 || (_tab == 1 ? p < 100 : p >= 100);
          }).toList();
    final tabs = [s.t('mc_all'), s.t('mc_ongoing'), s.t('mc_completed')];
    return Scaffold(
      appBar: AppBar(title: Text(s.t('my_courses'))),
      body: Column(children: [
        Container(
          margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: .5),
              borderRadius: BorderRadius.circular(24)),
          child: Row(children: [
            for (var i = 0; i < tabs.length; i++)
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _tab = i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                        color: _tab == i ? scheme.primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(20)),
                    child: Center(
                      child: Text(tabs[i],
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: _tab == i
                                  ? scheme.onPrimary
                                  : scheme.onSurfaceVariant)),
                    ),
                  ),
                ),
              ),
          ]),
        ),
        Expanded(
          child: all == null
              ? Center(
                  child: _failed
                      ? Column(mainAxisSize: MainAxisSize.min, children: [
                          Text(s.t('generic_error')),
                          const SizedBox(height: 8),
                          OutlinedButton(
                              onPressed: _load, child: Text(s.t('retry'))),
                        ])
                      : const CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: shown.isEmpty
                      ? ListView(children: [
                          const SizedBox(height: 100),
                          Center(child: Text(s.t('no_my_courses'))),
                        ])
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          itemCount: shown.length,
                          itemBuilder: (_, i) {
                            final c = shown[i];
                            final p = (c.progressPercent ?? 0).clamp(0, 100);
                            return InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () => Navigator.of(context)
                                  .push(MaterialPageRoute(
                                      builder: (_) =>
                                          CourseDetailsScreen(courseId: c.id)))
                                  .then((_) => _load()),
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: scheme.surface,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                        color:
                                            Colors.black.withValues(alpha: .07),
                                        blurRadius: 10,
                                        offset: const Offset(0, 4)),
                                  ],
                                ),
                                child: Row(children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: SizedBox(
                                      width: 96,
                                      height: 54,
                                      child: Container(
                                        color: scheme.primaryContainer,
                                        child: (c.coverUrl ?? '').isNotEmpty
                                            ? Image.network(c.coverUrl!,
                                                fit: BoxFit.contain,
                                                errorBuilder: (_, __, ___) =>
                                                    const Icon(Icons.menu_book))
                                            : const Icon(Icons.menu_book),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(c.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w800)),
                                        const SizedBox(height: 2),
                                        Text(
                                            '${c.instructorName ?? ''}${c.hours != null && c.hours! > 0 ? '  |  ${c.hours} ${s.t('hours')}' : ''}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                                fontSize: 11,
                                                color:
                                                    scheme.onSurfaceVariant)),
                                        const SizedBox(height: 8),
                                        Row(children: [
                                          Expanded(
                                            child: LinearProgressIndicator(
                                              value: p / 100,
                                              minHeight: 6,
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              color: p >= 100
                                                  ? const Color(0xFF16A34A)
                                                  : scheme.primary,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text('$p%',
                                              style: const TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700)),
                                        ]),
                                      ],
                                    ),
                                  ),
                                ]),
                              ),
                            );
                          },
                        ),
                ),
        ),
      ]),
    );
  }
}
