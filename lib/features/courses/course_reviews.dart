import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/l10n.dart';
import 'data/course_models.dart';
import 'data/courses_repo.dart';

/// Reviews block on the course page: list + write/edit your own review
/// (enrolled students only, enforced by RLS too).
class ReviewsSection extends StatefulWidget {
  const ReviewsSection(
      {super.key, required this.courseId, required this.enrolled});

  final String courseId;
  final bool enrolled;

  @override
  State<ReviewsSection> createState() => _ReviewsSectionState();
}

class _ReviewsSectionState extends State<ReviewsSection> {
  List<CourseReview>? _reviews;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final reviews = await CoursesRepository.fetchReviews(widget.courseId);
      if (mounted) setState(() => _reviews = reviews);
    } catch (_) {
      if (mounted) setState(() => _reviews = const []);
    }
  }

  Future<void> _writeReview() async {
    final mineMatches =
        (_reviews ?? const <CourseReview>[]).where((r) => r.isMine);
    final mine = mineMatches.isEmpty ? null : mineMatches.first;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _ReviewDialog(
          courseId: widget.courseId,
          initialRating: mine?.rating ?? 0,
          initialBody: mine?.body ?? ''),
    );
    if (saved == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final reviews = _reviews ?? const <CourseReview>[];
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(s.t('reviews'),
                    style: theme.textTheme.titleMedium),
              ),
              if (widget.enrolled)
                TextButton.icon(
                  onPressed: _writeReview,
                  icon: const Icon(Icons.rate_review_outlined, size: 18),
                  label: Text(reviews.any((r) => r.isMine)
                      ? s.t('your_review')
                      : s.t('write_review')),
                ),
            ],
          ),
          if (reviews.isEmpty)
            Text(s.t('no_reviews'),
                style: const TextStyle(color: Colors.grey)),
          ...reviews.map((r) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              r.authorName.isNotEmpty
                                  ? r.authorName
                                  : s.t('student'),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          _Stars(rating: r.rating),
                        ],
                      ),
                      if (r.body.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(r.body),
                      ],
                      Text(
                        DateFormat('d MMM y', s.locale.languageCode)
                            .format(r.createdAt),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              )),
        ],
      ),
    );
  }
}

class _Stars extends StatelessWidget {
  const _Stars({required this.rating});

  final int rating;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        5,
        (i) => Icon(
          i < rating ? Icons.star : Icons.star_border,
          size: 16,
          color: Colors.amber,
        ),
      ),
    );
  }
}

class _ReviewDialog extends StatefulWidget {
  const _ReviewDialog(
      {required this.courseId, this.initialRating = 0, this.initialBody = ''});

  final String courseId;
  final int initialRating;
  final String initialBody;

  @override
  State<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<_ReviewDialog> {
  late int _rating = widget.initialRating;
  late final _body = TextEditingController(text: widget.initialBody);
  bool _busy = false;

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return AlertDialog(
      title: Text(s.t('write_review')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              5,
              (i) => IconButton(
                onPressed: () => setState(() => _rating = i + 1),
                icon: Icon(
                  i < _rating ? Icons.star : Icons.star_border,
                  color: Colors.amber,
                ),
              ),
            ),
          ),
          TextField(
            controller: _body,
            maxLines: 3,
            decoration: InputDecoration(hintText: s.t('review_hint')),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(s.t('cancel')),
        ),
        FilledButton(
          onPressed: _rating == 0 || _busy
              ? null
              : () async {
                  setState(() => _busy = true);
                  try {
                    await CoursesRepository.upsertReview(
                        widget.courseId, _rating, _body.text);
                    if (!mounted) return;
                    Navigator.of(context).pop(true);
                  } catch (_) {
                    if (mounted) {
                      setState(() => _busy = false);
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(s.t('generic_error'))));
                    }
                  }
                },
          child: Text(s.t('save')),
        ),
      ],
    );
  }
}
