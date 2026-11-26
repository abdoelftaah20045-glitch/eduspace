import '../../core/in_app_player.dart';
import 'package:flutter/material.dart';
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

  Widget _quick(BuildContext context, IconData icon, String label,
      Color color, Widget page) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => page))
          .then((_) => _load()),
      child: Column(children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .14),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Icon(icon, color: color, size: 26),
        ),
        const SizedBox(height: 6),
        Text(label,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11.5)),
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
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Builder(
                      builder: (ctx) => IconButton(
                        icon: const Icon(Icons.menu),
                        onPressed: () => Scaffold.of(ctx).openDrawer(),
                      ),
                    ),
                    CircleAvatar(
                      radius: 24,
                      backgroundColor:
                          scheme.primary.withValues(alpha: .15),
                      backgroundImage:
                          (_avatarUrl != null && _avatarUrl!.isNotEmpty)
                              ? NetworkImage(_avatarUrl!)
                              : null,
                      child: (_avatarUrl == null || _avatarUrl!.isEmpty)
                          ? Icon(Icons.person,
                              color: scheme.primary, size: 26)
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ValueListenableBuilder<String>(
                            valueListenable:
                                TenantContext.instance.currentName,
                            builder: (context, tenantName, _) {
                              // The current organization must always be
                              // obvious (exec guide section 3).
                              final org =
                                  tenantName == TenantContext.defaultTenantName ||
                                          tenantName.isEmpty
                                      ? s.t('app_name')
                                      : tenantName;
                              return Text(
                                org,
                                style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant),
                              );
                            },
                          ),
                          Text(
                            '${s.t('welcome')}${_name.isNotEmpty ? '، $_name' : ''} 👋',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: s.t('notifications'),
                      style: IconButton.styleFrom(
                        backgroundColor:
                            scheme.primary.withValues(alpha: .08),
                      ),
                      icon: Badge(
                        label: Text('$_unread'),
                        isLabelVisible: _unread > 0,
                        child:
                            const Icon(Icons.notifications_outlined),
                      ),
                      onPressed: () {
                        Navigator.of(context)
                            .push(
                              MaterialPageRoute(
                                  builder: (_) =>
                                      const NotificationsScreen()),
                            )
                            .then((_) => _load());
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Promo banner (reference: blue illustrated banner).
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: AlignmentDirectional.topStart,
                  end: AlignmentDirectional.bottomEnd,
                  colors: [scheme.primary, const Color(0xFF1565C0)],
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: scheme.primary.withValues(alpha: .3),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.t('promo_title'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          s.t('promo_subtitle'),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .9),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.rocket_launch_rounded,
                        color: Colors.white, size: 32),
                  ),
                ],
              ),
            ),
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
            // Quick dashboard grid (reference: round icon tiles).
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 8,
              childAspectRatio: .85,
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
            const SizedBox(height: 20),
            if (!_loaded)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (item != null) ...[
              Text(s.t('continue_learning'),
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              FadeSlideIn(
                child: Material(
                  color: const Color(0xFFFFF3D6),
                  borderRadius: BorderRadius.circular(20),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => LessonScreen(lesson: item.lesson),
                        ),
                      ).then((_) => _load());
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: const BoxDecoration(
                              color: Color(0xFFF29900),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.play_arrow_rounded,
                                color: Colors.white, size: 30),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.lesson.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color: Color(0xFF5D4300),
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  item.course.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF8A6A1F),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
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
            if (_trending.isNotEmpty) ...[
              Text(s.t('trending_now'),
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              SizedBox(
                height: 150,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _trending.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (_, i) {
                    final c = _trending[i];
                    final pal = _coursePalette[i % _coursePalette.length];
                    return SizedBox(
                      width: 160,
                      child: Material(
                        color: pal.$1,
                        borderRadius: BorderRadius.circular(18),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) =>
                                      CourseDetailsScreen(courseId: c.id))),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                      color: pal.$2,
                                      borderRadius: BorderRadius.circular(12)),
                                  child: const Icon(Icons.trending_up,
                                      color: Colors.white),
                                ),
                                const Spacer(),
                                Text(c.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),
            ],
            Row(
              children: [
                Expanded(
                  child: Text(s.t('my_courses'),
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ),
                Text(
                  s.t('see_all'),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.primary),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_loaded && myCourses.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(s.t('no_my_courses')),
                ),
              ),
            ...List.generate(
              myCourses.length < 3 ? myCourses.length : 3,
              (i) {
                final c = myCourses[i];
                final palette = _coursePalette[i % _coursePalette.length];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Material(
                    color: palette.$1,
                    borderRadius: BorderRadius.circular(20),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                CourseDetailsScreen(courseId: c.id),
                          ),
                        ).then((_) => _load());
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: palette.$2,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(Icons.menu_book_rounded,
                                  color: Colors.white, size: 24),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    c.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold),
                                  ),
                                  if (c.progressPercent != null) ...[
                                    const SizedBox(height: 6),
                                    ClipRRect(
                                      borderRadius:
                                          BorderRadius.circular(6),
                                      child: LinearProgressIndicator(
                                        value: c.progressPercent! / 100,
                                        minHeight: 6,
                                        backgroundColor:
                                            Colors.white.withValues(alpha: .7),
                                        valueColor:
                                            AlwaysStoppedAnimation(palette.$2),
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      '${c.progressPercent}%',
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(Icons.arrow_forward_ios,
                                size: 16,
                                color: theme.colorScheme.onSurfaceVariant),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
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
