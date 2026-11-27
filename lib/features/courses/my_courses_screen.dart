import '../../core/cached_avatar.dart';
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
          decoration: BoxDecoration(
              border: Border(
                  bottom: BorderSide(color: scheme.outlineVariant))),
          child: Row(children: [
            for (var i = 0; i < tabs.length; i++)
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _tab = i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                        border: Border(
                            bottom: BorderSide(
                                width: 3,
                                color: _tab == i
                                    ? scheme.primary
                                    : Colors.transparent))),
                    child: Center(
                      child: Text(tabs[i],
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: _tab == i
                                  ? scheme.primary
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
                            final done = p >= 100;
                            final green = const Color(0xFF16A34A);
                            return InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: () => Navigator.of(context)
                                  .push(MaterialPageRoute(
                                      builder: (_) =>
                                          CourseDetailsScreen(courseId: c.id)))
                                  .then((_) => _load()),
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 16),
                                clipBehavior: Clip.antiAlias,
                                decoration: BoxDecoration(
                                  color: scheme.surface,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: scheme.outlineVariant),
                                  boxShadow: [
                                    BoxShadow(
                                        color: Colors.black.withValues(alpha: .06),
                                        blurRadius: 14,
                                        offset: const Offset(0, 6)),
                                  ],
                                ),
                                child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      AspectRatio(
                                        aspectRatio: 16 / 8,
                                        child: Stack(fit: StackFit.expand, children: [
                                          Container(
                                            color: scheme.primaryContainer,
                                            child: (c.coverUrl ?? '').isNotEmpty
                                                ? CachedImage(c.coverUrl!,
                                                    fit: BoxFit.cover,
                                                    errorBuilder: (_, __, ___) =>
                                                        const SizedBox.shrink())
                                                : null,
                                          ),
                                          const DecoratedBox(
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                begin: Alignment.topCenter,
                                                end: Alignment.bottomCenter,
                                                colors: [Colors.transparent, Colors.black54],
                                              ),
                                            ),
                                          ),
                                          if ((c.field ?? '').trim().isNotEmpty)
                                            PositionedDirectional(
                                              top: 10,
                                              start: 10,
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(
                                                    horizontal: 10, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: Colors.black54,
                                                  borderRadius: BorderRadius.circular(20),
                                                ),
                                                child: Text(c.field!.trim(),
                                                    style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.w700)),
                                              ),
                                            ),
                                          PositionedDirectional(
                                            top: 10,
                                            end: 10,
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(
                                                  horizontal: 10, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: done ? green : scheme.primary,
                                                borderRadius: BorderRadius.circular(20),
                                              ),
                                              child: Text(
                                                  done ? s.t('completed') : '$p%',
                                                  style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.w800)),
                                            ),
                                          ),
                                          PositionedDirectional(
                                            bottom: 10,
                                            end: 12,
                                            child: CircleAvatar(
                                              radius: 20,
                                              backgroundColor: Colors.white,
                                              child: Icon(Icons.play_arrow,
                                                  color: scheme.primary, size: 26),
                                            ),
                                          ),
                                        ]),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(c.title,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 16)),
                                            if ((c.instructorName ?? '').isNotEmpty) ...[
                                              const SizedBox(height: 4),
                                              Text(c.instructorName!,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                      fontSize: 12.5,
                                                      color: scheme.onSurfaceVariant)),
                                            ],
                                            const SizedBox(height: 12),
                                            ClipRRect(
                                              borderRadius: BorderRadius.circular(6),
                                              child: LinearProgressIndicator(
                                                value: p / 100,
                                                minHeight: 7,
                                                backgroundColor:
                                                    scheme.surfaceContainerHighest,
                                                color: done ? green : scheme.primary,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Row(children: [
                                              Expanded(
                                                  child: Text(done ? s.t('completed') : '$p%',
                                                      style: TextStyle(
                                                          fontSize: 12,
                                                          fontWeight: FontWeight.w700,
                                                          color: done
                                                              ? green
                                                              : scheme.onSurfaceVariant))),
                                              Text(done ? '' : s.t('continue_learning'),
                                                  style: TextStyle(
                                                      fontSize: 13,
                                                      fontWeight: FontWeight.w800,
                                                      color: scheme.primary)),
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
