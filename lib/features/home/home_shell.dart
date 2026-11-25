import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/l10n.dart';
import '../../core/widgets.dart';
import '../courses/course_details_screen.dart';
import '../courses/courses_screen.dart';
import '../courses/data/course_models.dart';
import '../courses/data/courses_repo.dart';
import '../courses/lesson_screen.dart';
import '../exams/exams_screen.dart';
import '../notifications/data/notifications_repo.dart';
import '../lives/data/lives_repo.dart';
import '../notifications/notifications_screen.dart';
import '../profile/profile_screen.dart';

/// Bottom navigation shell: Home / Courses / Exams / Account.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final pages = [
      const _HomeTab(),
      const CoursesScreen(),
      const ExamsScreen(),
      const ProfileScreen(),
    ];
    return Scaffold(
      body: pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            label: s.t('tab_home'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.menu_book_outlined),
            label: s.t('tab_courses'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.quiz_outlined),
            label: s.t('tab_exams'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline),
            label: s.t('tab_account'),
          ),
        ],
      ),
    );
  }
}

class _HomeTab extends StatefulWidget {
  const _HomeTab();

  @override
  State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab> {
  ContinueItem? _continueItem;
  List<Course>? _myCourses;
  Announcement? _announcement;
  List<LiveSession> _lives = const [];
  int _unread = 0;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        CoursesRepository.fetchContinueLearning(),
        CoursesRepository.fetchMyCourses(),
      ]);
      // Notifications tables may not exist yet on older backends; never
      // let them break the home tab.
      var unread = 0;
      Announcement? announcement;
      var lives = <LiveSession>[];
      try {
        unread = await NotificationsRepository.unreadCount();
        announcement = await NotificationsRepository.fetchActiveAnnouncement();
      } catch (_) {}
      try {
        lives = await LivesRepository.fetchUpcoming();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _continueItem = results[0] as ContinueItem?;
        _myCourses = results[1] as List<Course>;
        _unread = unread;
        _announcement = announcement;
        _lives = lives;
        _loaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final item = _continueItem;
    final myCourses = _myCourses ?? const <Course>[];
    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('app_name')),
        actions: [
          IconButton(
            tooltip: s.t('notifications'),
            icon: Badge(
              label: Text('$_unread'),
              isLabelVisible: _unread > 0,
              child: const Icon(Icons.notifications_outlined),
            ),
            onPressed: () {
              Navigator.of(context)
                  .push(
                    MaterialPageRoute(
                        builder: (_) => const NotificationsScreen()),
                  )
                  .then((_) => _load());
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (!_loaded)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (item != null) ...[
              Text(s.t('continue_learning'),
                  style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              FadeSlideIn(
                child: Card(
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  leading: const Icon(Icons.play_circle, size: 36),
                  title: Text(item.lesson.title),
                  subtitle: Text(item.course.title),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => LessonScreen(lesson: item.lesson),
                      ),
                    ).then((_) => _load());
                  },
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
            if (_announcement != null) ...[
              FadeSlideIn(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: theme.colorScheme.primary.withValues(alpha: .25),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.campaign_outlined,
                          color: theme.colorScheme.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _announcement!.title,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold),
                            ),
                            if (_announcement!.body.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(_announcement!.body,
                                  style: const TextStyle(fontSize: 13)),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
            if (_lives.isNotEmpty) ...[
              _UpcomingLives(lives: _lives),
              const SizedBox(height: 24),
            ],
            Text(s.t('my_courses'), style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_loaded && myCourses.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(s.t('no_my_courses')),
                ),
              ),
            ...myCourses.take(3).map((c) => Card(
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    leading: const Icon(Icons.menu_book),
                    title: Text(c.title),
                    subtitle: c.progressPercent != null
                        ? LinearProgressIndicator(
                            value: c.progressPercent! / 100,
                          )
                        : null,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              CourseDetailsScreen(courseId: c.id),
                        ),
                      ).then((_) => _load());
                    },
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

/// Upcoming live sessions strip on the home tab (doc section 13).
class _UpcomingLives extends StatelessWidget {
  const _UpcomingLives({required this.lives});

  final List<LiveSession> lives;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(s.t('upcoming_lives'), style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        ...lives.take(3).map(
              (l) => Card(
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.video_camera_front_outlined,
                          color: theme.colorScheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(l.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            Text(
                              '${DateFormat('d MMM, h:mm a', s.locale.languageCode).format(l.startsAt)}'
                              ' · ${l.durationMinutes} ${s.t('minutes_unit')}'
                              '${l.hostName != null && l.hostName!.isNotEmpty ? ' · ${l.hostName}' : ''}',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: l.canJoinNow
                            ? () => launchUrl(Uri.parse(l.joinUrl),
                                mode: LaunchMode.externalApplication)
                            : null,
                        child: Text(s.t('join_live')),
                      ),
                    ],
                  ),
                ),
              ),
            ),
      ],
    );
  }
}
