import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../courses/course_details_screen.dart';
import '../courses/data/course_models.dart';

IconData _fieldIcon(String f) {
  final x = f.toLowerCase();
  if (x.contains('prog') || x.contains('code') || x.contains('برمج')) {
    return Icons.code;
  }
  if (x.contains('design') || x.contains('تصميم')) return Icons.brush_outlined;
  if (x.contains('math') || x.contains('رياض')) return Icons.calculate_outlined;
  if (x.contains('lang') || x.contains('لغ')) return Icons.translate;
  if (x.contains('sci') || x.contains('علو')) return Icons.science_outlined;
  if (x.contains('bus') || x.contains('اعمال') || x.contains('أعمال')) {
    return Icons.business_center_outlined;
  }
  return Icons.category_outlined;
}

/// Round category chips with an icon circle and a label.
class CategoryChips extends StatelessWidget {
  const CategoryChips(
      {super.key,
      required this.fields,
      required this.selected,
      required this.onSelect});

  final List<String> fields;
  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final scheme = Theme.of(context).colorScheme;
    final items = <String?>[null, ...fields];
    return SizedBox(
      height: 86,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (_, i) {
          final f = items[i];
          final on = selected == f;
          return GestureDetector(
            onTap: () => onSelect(f),
            child: SizedBox(
              width: 68,
              child: Column(children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: on ? scheme.primary : scheme.primaryContainer,
                    boxShadow: on
                        ? [
                            BoxShadow(
                                color: scheme.primary.withValues(alpha: .35),
                                blurRadius: 10,
                                offset: const Offset(0, 4))
                          ]
                        : null,
                  ),
                  child: Icon(f == null ? Icons.apps : _fieldIcon(f),
                      color: on ? scheme.onPrimary : scheme.primary),
                ),
                const SizedBox(height: 6),
                Text(f ?? s.t('all_label'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: on ? FontWeight.w800 : FontWeight.w500)),
              ]),
            ),
          );
        },
      ),
    );
  }
}

/// Featured course card: 16:9 image shown fully, title, instructor, rating
/// and price below.
class FeaturedCourseCard extends StatelessWidget {
  const FeaturedCourseCard({super.key, required this.course});

  final Course course;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final scheme = Theme.of(context).colorScheme;
    final c = course;
    final price = c.price <= 0
        ? s.t('free')
        : '${c.price.toStringAsFixed(0)} ${c.currency}';
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => CourseDetailsScreen(courseId: c.id))),
      child: Container(
        width: 250,
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: .5)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: .08),
                blurRadius: 12,
                offset: const Offset(0, 5))
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(
              color: scheme.primaryContainer,
              child: (c.coverUrl ?? '').isEmpty
                  ? Icon(Icons.menu_book, color: scheme.primary)
                  : Image.network(c.coverUrl!,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) =>
                          Icon(Icons.menu_book, color: scheme.primary)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 14)),
              if ((c.instructorName ?? '').isNotEmpty)
                Text(c.instructorName!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant)),
              const SizedBox(height: 6),
              Row(children: [
                const Icon(Icons.star_rounded,
                    size: 16, color: Color(0xFFF29900)),
                const SizedBox(width: 2),
                Text(
                    (c.ratingAvg ?? 0) > 0
                        ? c.ratingAvg!.toStringAsFixed(1)
                        : '-',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700)),
                const Spacer(),
                Text(price,
                    style: TextStyle(
                        fontWeight: FontWeight.w800, color: scheme.primary)),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Top mentors row built from the instructors of the listed courses.
class TopMentors extends StatelessWidget {
  const TopMentors({super.key, required this.courses});

  final List<Course> courses;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final seen = <String, Course>{};
    for (final c in courses) {
      final n = (c.instructorName ?? '').trim();
      if (n.isNotEmpty && !seen.containsKey(n)) seen[n] = c;
    }
    if (seen.isEmpty) return const SizedBox.shrink();
    final list = seen.entries.take(10).toList();
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: list.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (_, i) {
          final e = list[i];
          final photo = e.value.instructorPhotoUrl;
          return SizedBox(
            width: 70,
            child: Column(children: [
              CircleAvatar(
                radius: 29,
                backgroundColor: scheme.primaryContainer,
                backgroundImage: (photo ?? '').isNotEmpty
                    ? NetworkImage(photo!)
                    : null,
                child: (photo ?? '').isEmpty
                    ? Text(e.key.characters.first.toUpperCase(),
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: scheme.primary,
                            fontSize: 20))
                    : null,
              ),
              const SizedBox(height: 6),
              Text(e.key,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5)),
            ]),
          );
        },
      ),
    );
  }
}

/// Text clamped to a few lines with a "show more / less" toggle.
class ExpandableText extends StatefulWidget {
  const ExpandableText(this.text, {super.key, this.style, this.lines = 4});

  final String text;
  final TextStyle? style;
  final int lines;

  @override
  State<ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<ExpandableText> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      AnimatedSize(
        duration: const Duration(milliseconds: 180),
        alignment: Alignment.topCenter,
        child: Text(widget.text,
            style: widget.style,
            maxLines: _open ? null : widget.lines,
            overflow: _open ? TextOverflow.visible : TextOverflow.ellipsis),
      ),
      if (widget.text.length > 140)
        GestureDetector(
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(_open ? s.t('show_less') : s.t('show_more'),
                style: TextStyle(
                    color: scheme.primary, fontWeight: FontWeight.w700)),
          ),
        ),
    ]);
  }
}
