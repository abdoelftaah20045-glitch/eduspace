import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/html_text.dart';
import '../../core/tenant.dart';
import '../courses/course_details_screen.dart';
import '../exams/data/exam_models.dart';
import '../exams/exam_instructions_screen.dart';
import '../library/books_shelf.dart';
import '../library/data/library_repo.dart';

/// Home search: one box that looks in courses, lessons, exams and books.
class GlobalSearchScreen extends StatefulWidget {
  const GlobalSearchScreen({super.key});

  @override
  State<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends State<GlobalSearchScreen> {
  final _c = TextEditingController();
  Timer? _t;
  bool _busy = false;
  String _last = '';
  List<Map<String, dynamic>> _courses = const [];
  List<Map<String, dynamic>> _lessons = const [];
  List<Map<String, dynamic>> _exams = const [];
  List<LibraryItem> _books = const [];

  SupabaseClient get _db => Supabase.instance.client;

  @override
  void dispose() {
    _t?.cancel();
    _c.dispose();
    super.dispose();
  }

  void _changed(String v) {
    _t?.cancel();
    _t = Timer(const Duration(milliseconds: 350), () => _run(v));
  }

  Future<void> _run(String raw) async {
    final q = raw.replaceAll(RegExp(r'[,()%*]'), ' ').trim();
    if (q.length < 2) {
      if (mounted) {
        setState(() {
          _last = '';
          _courses = const [];
          _lessons = const [];
          _exams = const [];
          _books = const [];
          _busy = false;
        });
      }
      return;
    }
    setState(() => _busy = true);
    final pat = '%$q%';
    Future<List<Map<String, dynamic>>> safe(
        Future<dynamic> Function() f) async {
      try {
        final r = await f();
        return List<Map<String, dynamic>>.from(r as List);
      } catch (_) {
        return const [];
      }
    }

    final res = await Future.wait([
      safe(() => _db
          .from('courses')
          .select('id,title,field,instructor_name,cover_url')
          .eq('tenant_id', TenantContext.id)
          .inFilter('status', ['published', 'draft'])
          .or('title.ilike.$pat,description.ilike.$pat,field.ilike.$pat,instructor_name.ilike.$pat')
          .order('created_at', ascending: false)
          .limit(15)),
      safe(() => _db
          .from('lessons')
          .select('id,title,course_id,courses(title)')
          .ilike('title', pat)
          .limit(15)),
      safe(() => _db
          .from('exams')
          .select()
          .eq('tenant_id', TenantContext.id)
          .eq('status', 'published')
          .filter('lesson_id', 'is', null)
          .or('title.ilike.$pat,description.ilike.$pat')
          .limit(15)),
    ]);
    var books = <LibraryItem>[];
    try {
      books = await LibraryRepository.fetchItems(query: q, limit: 15);
    } catch (_) {}
    if (!mounted || _c.text.replaceAll(RegExp(r'[,()%*]'), ' ').trim() != q) {
      return;
    }
    setState(() {
      _last = q;
      _courses = res[0];
      _lessons = res[1];
      _exams = res[2];
      _books = books;
      _busy = false;
    });
  }

  Widget _head(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 16, 8, 6),
        child: Text(t,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
      );

  Widget _row(IconData icon, String title, String sub, VoidCallback onTap) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      leading: Icon(icon),
      title: Text(decodeHtml(title), maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: sub.isEmpty
          ? null
          : Text(decodeHtml(sub), maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: onTap,
    );
  }

  void _openCourse(String id) => Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CourseDetailsScreen(courseId: id)));

  @override
  Widget build(BuildContext context) {
    final empty = _courses.isEmpty &&
        _lessons.isEmpty &&
        _exams.isEmpty &&
        _books.isEmpty;
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _c,
          autofocus: true,
          onChanged: _changed,
          textInputAction: TextInputAction.search,
          onSubmitted: _run,
          decoration: const InputDecoration(
              hintText: 'ابحث في كل التطبيق: كورسات، دروس، امتحانات، كتب',
              border: InputBorder.none),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        children: [
          if (_busy) const LinearProgressIndicator(),
          if (!_busy && _last.isNotEmpty && empty)
            const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('مفيش نتايج'))),
          if (_courses.isNotEmpty) ...[
            _head('كورسات'),
            for (final m in _courses)
              _row(Icons.video_library_outlined, '${m['title']}',
                  '${m['field'] ?? ''}', () => _openCourse('${m['id']}')),
          ],
          if (_lessons.isNotEmpty) ...[
            _head('دروس'),
            for (final m in _lessons)
              _row(
                  Icons.play_circle_outline,
                  '${m['title']}',
                  '${(m['courses'] is Map) ? (m['courses'] as Map)['title'] ?? '' : ''}',
                  () => _openCourse('${m['course_id']}')),
          ],
          if (_exams.isNotEmpty) ...[
            _head('امتحانات'),
            for (final m in _exams)
              _row(Icons.quiz_outlined, '${m['title']}',
                  '${m['description'] ?? ''}', () {
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ExamInstructionsScreen(
                        exam: Exam.fromMap(Map<String, dynamic>.from(m)))));
              }),
          ],
          if (_books.isNotEmpty) ...[
            _head('كتب'),
            for (final b in _books)
              _row(Icons.menu_book_rounded, b.title, b.author, () {
                LibraryRepository.bumpDownloads(b.id);
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => BookReaderScreen(item: b)));
              }),
          ],
        ],
      ),
    );
  }
}
