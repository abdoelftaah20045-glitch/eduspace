import '../../core/maintenance.dart';
import 'price_view.dart';
import 'package:flutter/material.dart';
import '../../core/pressable.dart';

import '../../core/l10n.dart';
import '../../core/paid_courses.dart';
import '../../core/widgets.dart';
import 'course_details_screen.dart';
import 'data/course_models.dart';
import 'data/courses_repo.dart';

/// Courses tab: search, category chips, filters, continue strip, catalog.
class CoursesScreen extends StatefulWidget {
  const CoursesScreen({super.key});

  @override
  State<CoursesScreen> createState() => _CoursesScreenState();
}

class _CoursesScreenState extends State<CoursesScreen> {
  final _searchController = TextEditingController();
  List<Course>? _courses;
  Map<String, Course> _mine = {};
  String? _error;
  String _category = '';
  String _filter = 'all';

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
      try {
        final mine = await CoursesRepository.fetchMyCourses();
        _mine = {for (final c in mine) c.id: c};
      } catch (_) {}
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
  Widget build(BuildContext context) =>
      MaintenanceGate(pageKey: 'courses', child: Builder(builder: _mtBuild));

  Course _merged(Course c) {
    final m = _mine[c.id];
    if (m == null) return c;
    return Course(
      id: c.id,
      title: c.title,
      description: c.description,
      coverUrl: c.coverUrl,
      field: c.field,
      level: c.level,
      instructorName: c.instructorName,
      language: c.language,
      hours: c.hours,
      price: c.price,
      currency: c.currency,
      status: c.status,
      isEnrolled: true,
      progressPercent: m.progressPercent,
      isFavorite: c.isFavorite,
      ratingAvg: c.ratingAvg,
      ratingCount: c.ratingCount,
      discountPercent: c.discountPercent,
      discountStartsAt: c.discountStartsAt,
      discountEndsAt: c.discountEndsAt,
    );
  }

  Widget _mtBuild(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('tab_courses'),
            style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: _buildBody(s),
    );
  }

  Widget _chip(String label, bool on, VoidCallback tap) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: on,
        onSelected: (_) => tap(),
        showCheckmark: false,
        selectedColor: scheme.primary,
        labelStyle: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
            color: on ? scheme.onPrimary : null),
      ),
    );
  }

  Widget _buildBody(S s) {
    if (_error != null) {
      return Center(child: Text(s.t('generic_error')));
    }
    final all = _courses;
    if (all == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final theme = Theme.of(context);
    final merged = all.map(_merged).toList();
    final cats = <String>{
      for (final c in merged)
        if ((c.field ?? '').trim().isNotEmpty) c.field!.trim()
    }.toList();
    var list = merged.where((c) {
      if (_category.isNotEmpty && (c.field ?? '').trim() != _category) {
        return false;
      }
      if (_filter == 'free') return c.isFree || !PaidCourses.enabled.value;
      if (_filter == 'progress') {
        return c.isEnrolled && (c.progressPercent ?? 0) < 100;
      }
      return true;
    }).toList();
    final cont = merged
        .where((c) => c.isEnrolled && (c.progressPercent ?? 0) < 100)
        .toList();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _load(),
              decoration: InputDecoration(
                hintText: s.t('search_courses'),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                          _load();
                        }),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: .6),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(28),
                    borderSide: BorderSide.none),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          if (cats.isNotEmpty)
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _chip(s.t('cat_all'), _category.isEmpty,
                      () => setState(() => _category = '')),
                  for (final c in cats)
                    _chip(c, _category == c, () => setState(() => _category = c)),
                ],
              ),
            ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _chip(s.t('cat_all'), _filter == 'all',
                    () => setState(() => _filter = 'all')),
                _chip(s.t('free'), _filter == 'free',
                    () => setState(() => _filter = 'free')),
                _chip(s.t('cat_in_progress'), _filter == 'progress',
                    () => setState(() => _filter = 'progress')),
              ],
            ),
          ),
          if (cont.isNotEmpty && _filter == 'all' && _category.isEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(s.t('continue_learning'),
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800)),
            ),
            SizedBox(
              height: 128,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: cont.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, i) => _ContinueTile(course: cont[i]),
              ),
            ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('${s.t('cat_results')} (${list.length})',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
          ),
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(child: Text(s.t('no_courses'))),
            ),
          for (var i = 0; i < list.length; i++)
            FadeSlideIn(
              delay: Duration(milliseconds: 40 * (i < 8 ? i : 8)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: CourseCard(course: list[i]),
              ),
            ),
        ],
      ),
    );
  }
}

class _ContinueTile extends StatelessWidget {
  const _ContinueTile({required this.course});
  final Course course;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = (course.progressPercent ?? 0) / 100;
    return PressScale(
      child: SizedBox(
        width: 250,
        child: Card(
          clipBehavior: Clip.antiAlias,
          margin: EdgeInsets.zero,
          child: InkWell(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => CourseDetailsScreen(courseId: course.id))),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(course.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const Spacer(),
                  Row(children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(value: p, minHeight: 6),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('${course.progressPercent ?? 0}%',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One course in a list (Coursera style: thumbnail left, details right).
class CourseCard extends StatelessWidget {
  const CourseCard({super.key, required this.course});

  final Course course;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final palette =
        _catalogPalette[course.title.hashCode.abs() % _catalogPalette.length];
    return PressScale(
      child: Card(
        clipBehavior: Clip.antiAlias,
        margin: const EdgeInsets.only(bottom: 12),
        elevation: 1,
        child: InkWell(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => CourseDetailsScreen(courseId: course.id),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 112,
                  child: Stack(children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: course.coverUrl != null &&
                                course.coverUrl!.isNotEmpty
                            ? Image.network(course.coverUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    _Thumb(color: palette))
                            : _Thumb(color: palette),
                      ),
                    ),
                    PositionedDirectional(
                      top: 2,
                      end: 2,
                      child: _FavoriteButton(
                          courseId: course.id, initial: course.isFavorite),
                    ),
                  ]),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if ((course.field ?? '').isNotEmpty)
                        Text(course.field!.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 10.5,
                                letterSpacing: .6,
                                fontWeight: FontWeight.w700,
                                color: theme.colorScheme.primary)),
                      const SizedBox(height: 2),
                      Text(course.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800)),
                      if ((course.instructorName ?? '').isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(course.instructorName!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall),
                      ],
                      if (course.ratingCount > 0) ...[
                        const SizedBox(height: 4),
                        Row(children: [
                          Text(course.ratingAvg!.toStringAsFixed(1),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 12.5)),
                          const SizedBox(width: 2),
                          const Icon(Icons.star_rounded,
                              size: 15, color: Color(0xFFF29900)),
                          Text(' (${course.ratingCount})',
                              style: theme.textTheme.bodySmall),
                        ]),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (course.level != null) s.t('level_${course.level}'),
                          if (course.hours != null && course.hours! > 0)
                            '${course.hours} ${s.t('hours')}',
                        ].join(' \u00b7 '),
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 6),
                      if (course.isEnrolled && course.progressPercent != null)
                        Row(children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                value: course.progressPercent! / 100,
                                minHeight: 6,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text('${course.progressPercent}%',
                              style: theme.textTheme.bodySmall),
                        ])
                      else
                        ValueListenableBuilder<bool>(
                          valueListenable: PaidCourses.enabled,
                          builder: (_, paid, __) {
                            final showPrice = paid && !course.isFree;
                            if (showPrice && course.hasDiscount) {
                              return PriceView(course: course, size: 14);
                            }
                            return Text(
                              showPrice
                                  ? '${course.price.toStringAsFixed(0)} ${course.currency}'
                                  : s.t('free'),
                              style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: showPrice
                                      ? null
                                      : const Color(0xFF2E9E5B)),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
