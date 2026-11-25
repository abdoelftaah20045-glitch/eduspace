import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import 'courses_screen.dart';
import 'data/course_models.dart';
import 'data/courses_repo.dart';

/// Favorite courses (doc section 20).
class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  List<Course>? _courses;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final courses = await CoursesRepository.fetchFavoriteCourses();
      if (mounted) setState(() => _courses = courses);
    } catch (_) {
      if (mounted) setState(() => _courses = const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final courses = _courses;
    return Scaffold(
      appBar: AppBar(title: Text(s.t('favorites'))),
      body: RefreshIndicator(
        onRefresh: _load,
        child: courses == null
            ? const Center(child: CircularProgressIndicator())
            : courses.isEmpty
                ? ListView(
                    padding: const EdgeInsets.all(32),
                    children: [
                      const SizedBox(height: 80),
                      const Icon(Icons.favorite_border,
                          size: 56, color: Colors.grey),
                      const SizedBox(height: 12),
                      Center(
                        child: Text(s.t('no_favorites'),
                            style: const TextStyle(color: Colors.grey)),
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: courses.length,
                    itemBuilder: (context, i) =>
                        CourseCard(course: courses[i]),
                  ),
      ),
    );
  }
}
