import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../courses/course_details_screen.dart';
import '../courses/data/course_models.dart';
import '../courses/data/courses_repo.dart';
import '../courses/my_courses_screen.dart';

/// Horizontal carousel of the student's enrolled courses on the profile.
class CoursesStrip extends StatefulWidget {
  const CoursesStrip({super.key});

  @override
  State<CoursesStrip> createState() => _CoursesStripState();
}

class _CoursesStripState extends State<CoursesStrip> {
  List<Course>? _items;

  @override
  void initState() {
    super.initState();
    CoursesRepository.fetchMyCourses()
        .timeout(const Duration(seconds: 20))
        .then((c) {
      if (mounted) setState(() => _items = c);
    }).catchError((_) {
      if (mounted) setState(() => _items = const []);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final scheme = Theme.of(context).colorScheme;
    final items = _items;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(children: [
            Expanded(
                child: Text(s.t('my_courses'),
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold))),
            TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const MyCoursesScreen())),
              child: Text(s.t('see_all')),
            ),
          ]),
        ),
        if (items == null)
          const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()))
        else if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(s.t('pf_no_courses'),
                style: Theme.of(context).textTheme.bodySmall),
          )
        else
          SizedBox(
            height: 190,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) {
                final c = items[i];
                final p = (c.progressPercent ?? 0).clamp(0, 100);
                return InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => CourseDetailsScreen(courseId: c.id))),
                  child: Container(
                    width: 190,
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest
                          .withValues(alpha: .5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AspectRatio(
                            aspectRatio: 16 / 9,
                            child: (c.coverUrl ?? '').isEmpty
                                ? Container(
                                    color: scheme.primaryContainer,
                                    child: const Icon(Icons.menu_book))
                                : Image.network(c.coverUrl!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                        color: scheme.primaryContainer)),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(c.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13)),
                                  const SizedBox(height: 8),
                                  LinearProgressIndicator(
                                      value: p / 100,
                                      minHeight: 5,
                                      borderRadius: BorderRadius.circular(4)),
                                  const SizedBox(height: 4),
                                  Text('$p%',
                                      style: const TextStyle(fontSize: 11)),
                                ]),
                          ),
                        ]),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
