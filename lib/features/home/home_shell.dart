import '../../core/in_app_player.dart';
import 'package:flutter/material.dart';
import '../../core/pressable.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/l10n.dart';
import '../../core/paid_courses.dart';
import '../../core/tenant.dart';
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
import '../certificates/my_certificates_screen.dart';
import '../library/library_screen.dart';
import '../lives/lives_screen.dart';
import '../qbank/question_bank_screen.dart';
import '../schedule/schedule_screen.dart';
import '../support/support_screen.dart';
import 'app_drawer.dart';

/// Bottom navigation shell: Home / Courses / Exams / Account.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    PaidCourses.load();
  }

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
  List<Course> _trending = [];
  bool _loaded = false;
  String _name = '';
  String? _avatarUrl;

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
      var trending = <Course>[];
      try {
        trending = (await CoursesRepository.fetchCourses()).take(8).toList();
      } catch (_) {}
      try {
        final uid = Supabase.instance.client.auth.currentUser?.id;
        if (uid != null) {
          final row = await Supabase.instance.client
              .from('profiles')
              .select('full_name, avatar_url')
              .eq('id', uid)
              .maybeSingle();
          if (row != null) {
            _name = (row['full_name'] as String? ?? '').trim();
            _avatarUrl = row['avatar_url'] as String?;
          }
        }
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _continueItem = results[0] as ContinueItem?;
        _myCourses = results[1] as List<Course>;
        _unread = unread;
        _announcement = announcement;
        _lives = lives;
        _trending = trending;
        _loaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loaded = true);
    }
  }

  int _progressOf(String courseId) {
    for (final c in _myCourses ?? const <Course>[]) {
      if (c.id == courseId) return c.progressPercent ?? 0;
    }
    return 0;
  }

  String? _discoverField;

  List<Course> get _discoverList => _discoverField == null
      ? _trending
      : _trending.where((c) => c.field == _discoverField).toList();

  Widget _sqBtn(BuildContext context, IconData icon, VoidCallback onTap,
      {int badge = 0}) {
    return SizedBox(
      width: 46,
      height: 46,
      child: Pressable(
        radius: 14,
        onTap: onTap,
        child: Center(
          child: Badge(
            label: Text('$badge'),
            isLabelVisible: badge > 0,
            child: Icon(icon, color: const Color(0xFF14264A)),
          ),
        ),
      ),
    );
  }

  Widget _courseCard(BuildContext context, Course c, int i, String sub) {
    final pal = _coursePalette[i % _coursePalette.length];
    return SizedBox(
      width: 168,
      child: Pressable(
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(
                builder: (_) => CourseDetailsScreen(courseId: c.id)))
            .then((_) => _load()),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 86,
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                    colors: [pal.$2.withValues(alpha: .65), pal.$2]),
                image: (c.coverUrl != null && c.coverUrl!.isNotEmpty)
                    ? DecorationImage(
                        image: NetworkImage(c.coverUrl!), fit: BoxFit.cover)
                    : null,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF14264A))),
                  const SizedBox(height: 4),
                  Text(sub,
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF6B7A99))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quick(BuildContext context, IconData icon, String label,
      Color color, Widget page) {
    return Pressable(
      radius: 18,
      shadowColor: color,
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => page))
          .then((_) => _load()),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [color.withValues(alpha: .75), color]),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: Colors.white, size: 24),
        ),
        const SizedBox(height: 6),
        Text(label,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final item = _continueItem;
    final myCourses = _myCourses ?? const <Course>[];
    final scheme = theme.colorScheme;
    return Scaffold(
      drawer: AppDrawer(name: _name, avatarUrl: _avatarUrl),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Builder(
                      builder: (ctx) => _sqBtn(
                          context, Icons.menu, () => Scaffold.of(ctx).openDrawer()),
                    ),
                    Expanded(
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.play_lesson_rounded,
                                color: scheme.primary, size: 26),
                            const SizedBox(width: 6),
                            Text(s.t('app_name'),
                                style: TextStyle(
                                    color: scheme.primary,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ),
                    ),
                    _sqBtn(
                      context,
                      Icons.notifications_outlined,
                      () => Navigator.of(context)
                          .push(MaterialPageRoute(
                              builder: (_) => const NotificationsScreen()))
                          .then((_) => _load()),
                      badge: _unread,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              '${s.t('welcome')}${_name.isNotEmpty ? ' يا ${_name.split(' ').first}' : ''}',
              style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF14264A)),
            ),
            const SizedBox(height: 4),
            Text(s.t('home_sub'),
                style: TextStyle(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 14),
            // Search bar (reference: "Search here" on the student dashboard).
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CoursesScreen())),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Row(children: [
                  Icon(Icons.search, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 10),
                  Text(s.t('home_search'),
                      style: TextStyle(color: scheme.onSurfaceVariant)),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            const SizedBox(height: 14),
            if (!_loaded)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (item != null) ...[
              FadeSlideIn(
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2563EB),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.t('continue_learning'),
                          style: const TextStyle(color: Colors.white70)),
                      const SizedBox(height: 6),
                      Text(item.course.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(item.lesson.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12)),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: _progressOf(item.course.id) / 100,
                          minHeight: 7,
                          backgroundColor: Colors.white24,
                          valueColor: const AlwaysStoppedAnimation(Colors.white),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: const Color(0xFF2563EB)),
                            onPressed: () => Navigator.of(context)
                                .push(MaterialPageRoute(
                                    builder: (_) =>
                                        LessonScreen(lesson: item.lesson)))
                                .then((_) => _load()),
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: Text(s.t('resume_lesson')),
                          ),
                          const Spacer(),
                          Text('${_progressOf(item.course.id)}%',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
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
            const SizedBox(height: 4),
            if (myCourses.isNotEmpty) ...[
            Row(children: [
              Expanded(
                child: Text(s.t('my_courses'),
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF14264A))),
              ),
            ]),
            const SizedBox(height: 10),
              SizedBox(
                height: 168,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: myCourses.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (_, i) => _courseCard(
                      context, myCourses[i], i,
                      '${myCourses[i].progressPercent ?? 0}%'),
                ),
              ),
              const SizedBox(height: 20),
            ] else if (_loaded)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(s.t('no_my_courses')),
                ),
              ),
            if (_lives.isNotEmpty) ...[
              _UpcomingLives(lives: _lives),
              const SizedBox(height: 24),
            ],
            if (_trending.isNotEmpty) ...[
            Row(children: [
              Expanded(
                child: Text(s.t('discover_label'),
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF14264A))),
              ),
            ]),
            const SizedBox(height: 10),
              SizedBox(
                height: 38,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final f in <String?>[
                      null,
                      ..._trending
                          .map((c) => c.field)
                          .whereType<String>()
                          .where((x) => x.trim().isNotEmpty)
                          .toSet()
                    ])
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 8),
                        child: ChoiceChip(
                          label: Text(f ?? s.t('all_label')),
                          selected: _discoverField == f,
                          onSelected: (_) => setState(() => _discoverField = f),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 168,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _discoverList.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (_, i) => _courseCard(
                      context, _discoverList[i], i + 2,
                      _discoverList[i].price <= 0
                          ? s.t('free')
                          : '${_discoverList[i].price.toStringAsFixed(0)} ${_discoverList[i].currency}'),
                ),
              ),
              const SizedBox(height: 20),
            ],
            Text(s.t('sections_label'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF14264A))),
            const SizedBox(height: 12),
            // Quick dashboard grid (reference: round icon tiles).
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 8,
              childAspectRatio: .8,
              children: [
                _quick(context, Icons.menu_book_outlined, s.t('my_courses'),
                    const Color(0xFF2196F3), const CoursesScreen()),
                _quick(context, Icons.video_camera_front_outlined,
                    s.t('lv_title'), const Color(0xFFE53935), const LivesScreen()),
                _quick(context, Icons.quiz_outlined, s.t('tab_exams'),
                    const Color(0xFF7C4DFF), const ExamsScreen()),
                _quick(context, Icons.folder_open, s.t('library_label'),
                    const Color(0xFF00ACC1), const LibraryScreen()),
                _quick(context, Icons.fact_check_outlined, s.t('qb_title'),
                    const Color(0xFFF29900), const QuestionBankScreen()),
                _quick(context, Icons.event_outlined, s.t('sch_title'),
                    const Color(0xFF2E9E5B), const ScheduleScreen()),
                _quick(context, Icons.workspace_premium_outlined,
                    s.t('my_certificates'), const Color(0xFFC9A227),
                    const MyCertificatesScreen()),
                _quick(context, Icons.support_agent, s.t('support'),
                    const Color(0xFFAB47BC), const SupportScreen()),
              ],
            ),
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
                            ? () => Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => InAppPlayerScreen(
                                    url: l.joinUrl, title: l.title)))
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

/// Pastel card palette for My Courses (reference: colorful course cards).
const _coursePalette = <(Color, Color)>[
  (Color(0xFFE3F0FF), Color(0xFF2196F3)),
  (Color(0xFFFFE9E1), Color(0xFFFF7043)),
  (Color(0xFFE8F7EE), Color(0xFF2E9E5B)),
  (Color(0xFFF3E9FF), Color(0xFF7C4DFF)),
];
