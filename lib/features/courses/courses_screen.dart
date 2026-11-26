import 'package:flutter/material.dart';
import '../../core/pressable.dart';

import '../../core/l10n.dart';
import '../../core/paid_courses.dart';
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
  bool _searching = false;

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
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _load(),
                decoration: InputDecoration(
                  hintText: s.t('search_courses'),
                  border: InputBorder.none,
                ),
              )
            : Text(s.t('tab_courses')),
        actions: [
          IconButton(
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: () {
              if (_searching) {
                final had = _searchController.text.isNotEmpty;
                _searchController.clear();
                setState(() => _searching = false);
                if (had) _load();
              } else {
                setState(() => _searching = true);
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
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
    final palette =
        _catalogPalette[course.title.hashCode.abs() % _catalogPalette.length];
    return PressScale(child: Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => CourseDetailsScreen(courseId: course.id),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: SizedBox(
                      width: 96,
                      height: 96,
                      child: course.coverUrl != null &&
                              course.coverUrl!.isNotEmpty
                          ? Image.network(
                              course.coverUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  _Thumb(color: palette),
                            )
                          : _Thumb(color: palette),
                    ),
                  ),
                  PositionedDirectional(
                    top: 2,
                    end: 2,
                    child: _FavoriteButton(
                        courseId: course.id, initial: course.isFavorite),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      course.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    if (course.instructorName != null &&
                        course.instructorName!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        course.instructorName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 6,
                      children: [
                        ValueListenableBuilder<bool>(
                          valueListenable: PaidCourses.enabled,
                          builder: (_, paid, __) {
                            final showPrice = paid && !course.isFree;
                            return _MetaChip(
                              icon: showPrice
                                  ? Icons.payments_outlined
                                  : Icons.lock_open,
                              label: showPrice
                                  ? '${course.price.toStringAsFixed(0)} ${course.currency}'
                                  : s.t('free'),
                            );
                          },
                        ),
                        if (course.level != null)
                          _MetaChip(
                            icon: Icons.signal_cellular_alt,
                            label: s.t('level_${course.level}'),
                          ),
                      ],
                    ),
                    if (course.ratingCount > 0) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.star_rounded,
                              size: 16, color: Color(0xFFF29900)),
                          const SizedBox(width: 3),
                          Text(
                            '${course.ratingAvg!.toStringAsFixed(1)} (${course.ratingCount})',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ],
                    if (course.isEnrolled &&
                        course.progressPercent != null) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: course.progressPercent! / 100,
                          minHeight: 6,
                          backgroundColor:
                              theme.colorScheme.surfaceContainerHighest,
                        ),
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
      ),
    ));
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: color.withValues(alpha: .18),
      child: Center(child: Icon(Icons.menu_book_rounded, color: color, size: 36)),
    );
  }
}

const _catalogPalette = <Color>[
  Color(0xFF2196F3),
  Color(0xFF7C4DFF),
  Color(0xFFFF7043),
  Color(0xFF2E9E5B),
  Color(0xFFF29900),
];

/// Small heart toggle that keeps its own optimistic state.
class _FavoriteButton extends StatefulWidget {
  const _FavoriteButton({required this.courseId, required this.initial});

  final String courseId;
  final bool initial;

  @override
  State<_FavoriteButton> createState() => _FavoriteButtonState();
}

class _FavoriteButtonState extends State<_FavoriteButton> {
  late bool _fav = widget.initial;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black38,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () async {
          setState(() => _fav = !_fav);
          try {
            await CoursesRepository.setFavorite(widget.courseId, _fav);
          } catch (_) {
            if (mounted) setState(() => _fav = !_fav);
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(
            _fav ? Icons.favorite : Icons.favorite_border,
            color: _fav ? Colors.redAccent : Colors.white,
            size: 20,
          ),
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
