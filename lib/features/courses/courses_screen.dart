import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../core/widgets.dart';
import 'course_details_screen.dart';
import 'data/course_models.dart';
import 'data/courses_repo.dart';

/// Courses tab: search plus the published catalog.
class CoursesScreen extends StatefulWidget {
  const CoursesScreen({super.key});

  @override
  State<CoursesScreen> createState() => _CoursesScreenState();
}

class _CoursesScreenState extends State<CoursesScreen> {
  final _searchController = TextEditingController();
  List<Course>? _courses;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final courses =
          await CoursesRepository.fetchCourses(query: _searchController.text);
      if (!mounted) return;
      setState(() {
        _courses = courses;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'load');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('tab_courses'))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _load(),
              decoration: InputDecoration(
                hintText: s.t('search_courses'),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    _load();
                  },
                ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(child: _buildBody(s)),
        ],
      ),
    );
  }

  Widget _buildBody(S s) {
    if (_error != null) {
      return Center(child: Text(s.t('generic_error')));
    }
    final courses = _courses;
    if (courses == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (courses.isEmpty) {
      return Center(child: Text(s.t('no_courses')));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: courses.length,
        itemBuilder: (context, i) => FadeSlideIn(
          delay: Duration(milliseconds: 60 * (i < 8 ? i : 8)),
          child: CourseCard(course: courses[i]),
        ),
      ),
    );
  }
}

/// One course in a list. Used by the catalog and by My Courses.
class CourseCard extends StatelessWidget {
  const CourseCard({super.key, required this.course});

  final Course course;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => CourseDetailsScreen(courseId: course.id),
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 7,
              child: course.coverUrl != null && course.coverUrl!.isNotEmpty
                  ? Image.network(
                      course.coverUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const _CoverPlaceholder(),
                    )
                  : const _CoverPlaceholder(),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(course.title, style: theme.textTheme.titleMedium),
                  if (course.instructorName != null &&
                      course.instructorName!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      course.instructorName!,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _MetaChip(
                        icon: course.isFree
                            ? Icons.lock_open
                            : Icons.payments_outlined,
                        label: course.isFree
                            ? s.t('free')
                            : '${course.price.toStringAsFixed(0)} ${course.currency}',
                      ),
                      if (course.level != null) ...[
                        const SizedBox(width: 8),
                        _MetaChip(
                          icon: Icons.signal_cellular_alt,
                          label: s.t('level_${course.level}'),
                        ),
                      ],
                    ],
                  ),
                  if (course.isEnrolled &&
                      course.progressPercent != null) ...[
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: course.progressPercent! / 100,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${course.progressPercent}%',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Center(child: Icon(Icons.menu_book, size: 48)),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

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
