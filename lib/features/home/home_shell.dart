import '../../core/push_service.dart';
import '../../core/cached_avatar.dart';
import '../../core/security.dart';
import '../../core/maintenance.dart';
import 'dart:async';
import 'dart:math' as math;
import '../../core/in_app_player.dart';
import 'package:flutter/material.dart';
import '../../core/pressable.dart';
import '../../core/image_carousel.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/l10n.dart';
import '../../core/paid_courses.dart';
import '../../core/tenant.dart';
import 'global_search_screen.dart';
import '../../core/widgets.dart';
import 'home_blocks.dart';
import 'home_books.dart';
import 'home_extras.dart';
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
import '../library/books_shelf.dart';
import '../lives/lives_screen.dart';
import '../qbank/question_bank_screen.dart';
import '../schedule/schedule_screen.dart';
import '../support/support_screen.dart';
import '../../core/remote_ui.dart';
import '../courses/my_courses_screen.dart';
import '../admin/import_job.dart';
import 'app_drawer.dart';
import 'home_widgets.dart';

class _CoursesTabHook {
  static void enter() => CoursesScreen.reshuffle.value++;
}

/// Bumped when the Home tab is opened again: courses and teachers reshuffle
/// from the data already in memory.
final ValueNotifier<int> _homeReshuffle = ValueNotifier(0);

/// Bottom navigation shell: Home / Courses / Exams / Account.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  // Tabs stay alive once opened (no reload on every switch); a tab that was
  // left for more than 10 minutes is rebuilt fresh the next time.
  final Set<String> _seen = {'home'};
  final Map<String, DateTime> _left = {};
  final Map<String, int> _gen = {};

  @override
  void initState() {
    super.initState();
    PaidCourses.load();
    ScreenProtection.sync();
    // Warm the other main tabs a few seconds after Home so they open instantly.
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) setState(() => _seen.addAll(const ['my', 'courses', 'exams', 'library', 'account']));
    });
    RemoteUi.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return ValueListenableBuilder<int>(
      valueListenable: RemoteUi.version,
      builder: (context, _, __) => _shell(context, s),
    );
  }

  Widget _shell(BuildContext context, S s) {
    // Home first and Account last are fixed; the three middle tabs can be
    // hidden or reordered by the admin (ui_layout: tab.my / tab.courses / tab.exams).
    final mid = <(String, Widget, IconData, String)>[
      ('my', const MyCoursesScreen(), Icons.school_outlined, s.t('my_courses')),
      ('courses', const CoursesScreen(), Icons.video_library_outlined, s.t('tab_courses')),
      ('exams', const ExamsScreen(), Icons.quiz_outlined, s.t('tab_exams')),
      ('library', const BooksShelfScreen(), Icons.menu_book_rounded, s.t('library_label')),
    ];
    final order = {for (var i = 0; i < mid.length; i++) mid[i].$1: RemoteUi.order('tab.${mid[i].$1}', i)};
    final shownMid = mid.where((t) => RemoteUi.visible('tab.${t.$1}')).toList()
      ..sort((a, b) => order[a.$1]!.compareTo(order[b.$1]!));
    final tabs = <(String, Widget, IconData, String)>[
      ('home', const MaintenanceGate(pageKey: 'home', child: _HomeTab()), Icons.home_outlined, s.t('tab_home')),
      ...shownMid,
      ('account', const ProfileScreen(), Icons.person_outline, s.t('tab_account')),
    ];
    final idx = _index.clamp(0, tabs.length - 1);
    _seen.add(tabs[idx].$1);
    return PopScope(
      canPop: idx == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && idx != 0) setState(() => _index = 0);
      },
      child: Scaffold(
      body: IndexedStack(
        index: idx,
        children: [
          for (final t in tabs)
            _seen.contains(t.$1)
                ? KeyedSubtree(
                    key: ValueKey('tab_${t.$1}_${_gen[t.$1] ?? 0}'),
                    child: t.$2)
                : const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
          child: Material(
            elevation: 10,
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(30),
            clipBehavior: Clip.antiAlias,
            child: NavigationBar(
        height: 64,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
        selectedIndex: idx,
        onDestinationSelected: (i) => setState(() {
          final now = DateTime.now();
          _left[tabs[idx].$1] = now;
          final back = _left[tabs[i].$1];
          if (back != null && now.difference(back).inMinutes >= 10) {
            _gen[tabs[i].$1] = (_gen[tabs[i].$1] ?? 0) + 1;
          }
          _index = i;
          if (tabs[i].$1 == 'courses' && i != idx) _CoursesTabHook.enter();
          if (tabs[i].$1 == 'home' && i != idx) _homeReshuffle.value++;
        }),
        destinations: [
          for (final t in tabs)
            NavigationDestination(icon: Icon(t.$3), label: t.$4),
        ],
      ),
          ),
        ),
      ),
    ));
  }
}

class _HomeTab extends StatefulWidget {
  const _HomeTab();

  @override
  State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab> with WidgetsBindingObserver {
  ContinueItem? _continueItem;
  List<Course>? _myCourses;
  List<Announcement> _announcements = [];
  List<LiveSession> _lives = const [];
  int _unread = 0;
  List<Course> _trending = [];
  List<String> _fields = const [];
  Map<String, String> _fieldCovers = const {};
  final Map<String, List<Course>> _fieldCourses = {};
  bool _loaded = false;
  // Home content rotates: a new random pick on app open and pull-to-refresh,
  // but it stays put while switching tabs or coming back from another app.
  bool _dirty = true;
  int _epoch = 0;
  List<Course> _mentorPool = [];
  List<Course> _allCourses = [];
  void _reshuffleHome() {
    if (!mounted || _allCourses.isEmpty) return;
    final rnd = math.Random();
    final rest = _allCourses.skip(4).toList()..shuffle(rnd);
    setState(() {
      _trending = [..._allCourses.take(4), ...rest.take(26)];
      _mentorPool = [..._allCourses]..shuffle(rnd);
      _fieldCourses.clear();
    });
  }

  Future<void> _refresh() {
    _dirty = true;
    _epoch++;
    return _load();
  }

  String _name = '';
  String? _avatarUrl;

  @override
  void initState() {
    super.initState();
    _load();
    _homeReshuffle.addListener(_reshuffleHome);
    ImportJob.courseTick.addListener(_load);
    PushService.arrived.addListener(_load);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  @override
  void dispose() {
    _homeReshuffle.removeListener(_reshuffleHome);
    WidgetsBinding.instance.removeObserver(this);
    PushService.arrived.removeListener(_load);
    ImportJob.courseTick.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    RemoteUi.load().then((_) {
      if (mounted) setState(() {});
    });
    try {
      final results = await Future.wait([
        CoursesRepository.fetchContinueLearning(),
        CoursesRepository.fetchMyCourses(),
      ]);
      // Notifications tables may not exist yet on older backends; never
      // let them break the home tab.
      var unread = 0;
      var announcements = <Announcement>[];
      var lives = <LiveSession>[];
      try {
        unread = await NotificationsRepository.unreadCount();
        announcements = await NotificationsRepository.fetchActiveAnnouncements();
      } catch (_) {}
      try {
        lives = await LivesRepository.fetchUpcoming();
      } catch (_) {}
      var trending = _trending;
      var pool = _mentorPool;
      if (_trending.isEmpty || _dirty) {
        try {
          final all = await CoursesRepository.fetchCourses(limit: 400);
          final rnd = math.Random();
          final fresh = all.take(4).toList();
          final rest = all.skip(4).toList()..shuffle(rnd);
          trending = [...fresh, ...rest.take(26)];
          pool = [...all]..shuffle(rnd);
          _allCourses = all;
          CoursesScreen.cache = all;
          _dirty = false;
        } catch (_) {}
      }
      // Discover categories come from ALL courses (by how many each has),
      // not from the 30 newest ones, so one big import cannot hide the rest.
      var fieldList = <String>[];
      try {
        final fr = await Supabase.instance.client
            .from('courses')
            .select('field,cover_url,status')
            .inFilter('status', ['published', 'draft'])
            .eq('tenant_id', TenantContext.id)
            .limit(4000);
        final cnt = <String, int>{};
        final best = <String, String>{};
        final bestScore = <String, int>{};
        for (final m in fr as List) {
          final f = '${(m as Map)['field'] ?? ''}'.trim();
          if (f.isNotEmpty) cnt[f] = (cnt[f] ?? 0) + 1;
          final u = '${m['cover_url'] ?? ''}'.trim();
          if (f.isEmpty || !u.startsWith('http')) continue;
          // Prefer real wide covers (no letterbox bars): maxres/hq720 or own
          // uploads, published first; plain hqdefault has black bars.
          final low = u.toLowerCase();
          var sc = 1;
          if (low.contains('maxresdefault') || low.contains('hq720') || !low.contains('ytimg.com')) sc = 3;
          if (low.contains('/default.') || low.contains('mqdefault') || low.contains('sddefault')) sc = 0;
          if (m['status'] == 'published') sc += 1;
          if (sc > (bestScore[f] ?? -1)) {
            bestScore[f] = sc;
            best[f] = u;
          }
        }
        try {
          final cr = await Supabase.instance.client
              .from('tenant_settings')
              .select('setting_value')
              .eq('tenant_id', TenantContext.id)
              .eq('setting_key', 'category_images')
              .maybeSingle();
          final v = cr?['setting_value'];
          if (v is Map) {
            v.forEach((k, val) {
              if ('$val'.startsWith('http')) best['$k'] = '$val';
            });
          }
        } catch (_) {}
        _fieldCovers = best;
        final keys = cnt.keys.toList()
          ..sort((a, b) => cnt[b]!.compareTo(cnt[a]!));
        fieldList = keys.take(24).toList();
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
        _announcements = announcements;
        _lives = lives;
        _trending = trending;
        _mentorPool = pool;
        if (fieldList.isNotEmpty) _fields = fieldList;
        _fieldCourses.clear();
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
      : (_fieldCourses[_discoverField!] ??
          _trending.where((c) => c.field == _discoverField).toList());

  Future<void> _pickField(String? f) async {
    setState(() => _discoverField = f);
    if (f == null || _fieldCourses.containsKey(f)) return;
    try {
      final all = await CoursesRepository.fetchCourses(query: f);
      final list = all.where((c) => (c.field ?? '').trim() == f).take(30).toList();
      if (!mounted) return;
      setState(() => _fieldCourses[f] = list);
    } catch (_) {}
  }

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
            child: Icon(icon, color: Theme.of(context).colorScheme.onSurface),
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
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Container(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: (c.coverUrl != null && c.coverUrl!.isNotEmpty)
                    ? CachedImage(c.coverUrl!,
                        fit: BoxFit.contain,
                        width: double.infinity,
                        errorBuilder: (_, __, ___) => Container(
                            decoration: BoxDecoration(
                                gradient: LinearGradient(colors: [
                          pal.$2.withValues(alpha: .65),
                          pal.$2
                        ]))))
                    : Container(
                        decoration: BoxDecoration(
                            gradient: LinearGradient(colors: [
                        pal.$2.withValues(alpha: .65),
                        pal.$2
                      ]))),
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
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context).colorScheme.onSurface)),
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

  static const quickIds = [
    'courses', 'lives', 'exams', 'library', 'qbank', 'schedule', 'certs', 'support'
  ];

  List<Widget> _filterQuick(List<Widget> tiles) {
    final idx = [for (var i = 0; i < tiles.length; i++) i]
        .where((i) => RemoteUi.visible('quick.${quickIds[i]}'))
        .toList();
    idx.sort((a, b) => RemoteUi.order('quick.${quickIds[a]}', a)
        .compareTo(RemoteUi.order('quick.${quickIds[b]}', b)));
    return [for (final i in idx) tiles[i]];
  }

  Widget _quick(BuildContext context, IconData icon, String label,
      Color color, Widget page) {
    return Pressable(
      radius: 18,
      shadowColor: Theme.of(context).colorScheme.primary,
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => page))
          .then((_) => _load()),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon,
              color: Theme.of(context).colorScheme.primary, size: 24),
        ),
        const SizedBox(height: 6),
        Text(label,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface)),
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
    final tilesList = _filterQuick([
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
    ]);
    final homeParts = <String, List<Widget>>{
      'home.continue': [
            if (item != null && RemoteUi.visible('home.continue')) ...[
              FadeSlideIn(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.t('continue_learning').toUpperCase(),
                          style: TextStyle(
                              color: scheme.primary,
                              fontSize: 11,
                              letterSpacing: .8,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      Text(item.course.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(item.lesson.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: scheme.onSurfaceVariant, fontSize: 12.5)),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: _progressOf(item.course.id) / 100,
                              minHeight: 7,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text('${_progressOf(item.course.id)}%',
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                      ]),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () => Navigator.of(context)
                              .push(MaterialPageRoute(
                                  builder: (_) =>
                                      LessonScreen(lesson: item.lesson)))
                              .then((_) => _load()),
                          child: Text(s.t('resume_lesson')),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
            ],
      ],
      'home.banner': [
            if (_announcements.isNotEmpty && RemoteUi.visible('home.banner')) ...[
              _AnnouncementBanner(items: _announcements),
              const SizedBox(height: 16),
            ],
      ],
      'home.my_courses': [
            const SizedBox(height: 4),
            if (myCourses.isNotEmpty && RemoteUi.visible('home.my_courses')) ...[
            Row(children: [
              Expanded(
                child: Text(s.t('my_courses'),
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Theme.of(context).colorScheme.onSurface)),
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
      ],
      'home.lives': [
            if (_lives.isNotEmpty && RemoteUi.visible('home.lives')) ...[
              _UpcomingLives(lives: _lives),
              const SizedBox(height: 24),
            ],
      ],
      'home.plan': [
            if (RemoteUi.visible('home.plan'))
              HomePlanCard(
                  continueTitle: item?.lesson.title,
                  onContinue: item == null
                      ? null
                      : () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => LessonScreen(lesson: item.lesson)))),
      ],
      'home.books': [
            if (RemoteUi.visible('home.books')) HomeBooks(key: ValueKey(_epoch)),
      ],
      'home.new_courses': [
            if (RemoteUi.visible('home.new_courses')) const HomeNewCourses(),
      ],
      'home.exams': [
            if (RemoteUi.visible('home.exams')) const HomeSuggestedExams(),
      ],
      'home.quote': [
            if (RemoteUi.visible('home.quote')) const HomeQuote(),
      ],
      'home.discover': [
            if (_trending.isNotEmpty && RemoteUi.visible('home.discover')) ...[
            Row(children: [
              Expanded(
                child: Text(s.t('discover_label'),
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Theme.of(context).colorScheme.onSurface)),
              ),
            ]),
            const SizedBox(height: 10),
              CategoryChips(
                fields: _fields.isNotEmpty
                    ? _fields
                    : _trending
                        .map((c) => c.field)
                        .whereType<String>()
                        .where((x) => x.trim().isNotEmpty)
                        .toSet()
                        .toList(),
                covers: _fieldCovers,
                selected: _discoverField,
                onSelect: _pickField,
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 250,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _discoverList.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (_, i) =>
                      FeaturedCourseCard(course: _discoverList[i]),
                ),
              ),
              const SizedBox(height: 16),
              Text(s.t('top_mentors'),
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).colorScheme.onSurface)),
              const SizedBox(height: 10),
              TopMentors(courses: _mentorPool.isNotEmpty ? _mentorPool : _trending),
              const SizedBox(height: 20),
            ],
      ],
      'home.tiles': [
            Text(s.t('sections_label'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.onSurface)),
            const SizedBox(height: 12),
            // Quick dashboard grid (reference: round icon tiles).
            SizedBox(
              height: 86,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: tilesList.length,
                padding: const EdgeInsetsDirectional.only(end: 16),
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) => SizedBox(width: 68, child: tilesList[i]),
              ),
            ),
      ],
    };
    final homeKeys = homeParts.keys.toList();
    final homeIds = homeKeys.where(RemoteUi.visible).toList()
      ..sort((a, b) => RemoteUi.order(a, homeKeys.indexOf(a))
          .compareTo(RemoteUi.order(b, homeKeys.indexOf(b))));
    return Scaffold(
      drawer: AppDrawer(name: _name, avatarUrl: _avatarUrl),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 28),
          children: [
            SafeArea(
              bottom: false,
              child: Column(children: [
                Row(children: [
                  Builder(
                    builder: (ctx) => IconButton(
                      tooltip: s.t('tab_account'),
                      icon: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final w in const [22.0, 16.0, 22.0])
                            Container(
                              width: w,
                              height: 2.6,
                              margin: const EdgeInsets.symmetric(vertical: 2.4),
                              decoration: BoxDecoration(
                                color: scheme.onSurface,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                        ],
                      ),
                      onPressed: () => Scaffold.of(ctx).openDrawer(),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Builder(
                    builder: (ctx) => GestureDetector(
                      onTap: () => Scaffold.of(ctx).openDrawer(),
                      child: CircleAvatar(
                        radius: 21,
                        backgroundColor: scheme.primaryContainer,
                        backgroundImage: (_avatarUrl ?? '').isNotEmpty
                            ? NetworkImage(_avatarUrl!)
                            : null,
                        child: (_avatarUrl ?? '').isEmpty
                            ? Text(
                                _name.isNotEmpty
                                    ? _name.substring(0, 1).toUpperCase()
                                    : '?',
                                style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: scheme.onPrimaryContainer))
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            RemoteUi.brandName.isNotEmpty
                                ? RemoteUi.brandName
                                : s.t('app_name'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: scheme.onSurfaceVariant, fontSize: 12)),
                        Text(
                            '${s.t('welcome')}${_name.isNotEmpty ? ' ${_name.split(' ').first}' : ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 21, fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(
                            builder: (_) => const NotificationsScreen()))
                        .then((_) => _load()),
                    child: Badge(
                      label: Text('$_unread'),
                      isLabelVisible: _unread > 0,
                      child: const Icon(Icons.notifications_outlined,
                          size: 26),
                    ),
                  ),
                ]),
                const SizedBox(height: 14),
                InkWell(
                  borderRadius: BorderRadius.circular(28),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const GlobalSearchScreen())),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 13),
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                          color: scheme.onSurfaceVariant, width: 1.2),
                    ),
                    child: Row(children: [
                      Icon(Icons.search, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                            RemoteUi.welcomeText.isNotEmpty
                                ? RemoteUi.welcomeText
                                : s.t('home_search'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: scheme.onSurfaceVariant)),
                      ),
                    ]),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 16),
            const SizedBox(height: 14),
            if (!_loaded)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
            ...mergeHomeBlocks([for (final id in homeIds) homeParts[id]!]),
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

/// Home banner: announcement images full-bleed with rounded corners.
/// Title/body overlay only when the admin turned "show text" on (or when the
/// announcement has no image at all).
class _AnnouncementBanner extends StatefulWidget {
  const _AnnouncementBanner({required this.items});

  final List<Announcement> items;

  @override
  State<_AnnouncementBanner> createState() => _AnnouncementBannerState();
}

class _AnnouncementBannerState extends State<_AnnouncementBanner> {
  final _page = PageController();
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_page.hasClients || widget.items.length < 2) return;
      _page.animateToPage((_index + 1) % widget.items.length,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeInOut);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    return Column(children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: AspectRatio(
          aspectRatio: 16 / 8,
          child: PageView.builder(
            controller: _page,
            itemCount: items.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (_, i) {
              final a = items[i];
              final hasImg = a.images.isNotEmpty;
              final text = !hasImg;
              return Stack(fit: StackFit.expand, children: [
                if (hasImg)
                  ImageCarousel(
                      urls: a.images,
                      aspectRatio: 16 / 8,
                      radius: 0,
                      interval: Duration(seconds: a.slideSeconds))
                else
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                          colors: [Color(0xFFFFF3D6), Color(0xFFFFE2A8)]),
                    ),
                  ),
                if (text && (a.title.isNotEmpty || a.body.isNotEmpty))
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: hasImg
                            ? const LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Colors.transparent, Colors.black87])
                            : null,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (a.title.isNotEmpty)
                            Text(a.title,
                                style: TextStyle(
                                    color: hasImg
                                        ? Colors.white
                                        : const Color(0xFF5D4300),
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16)),
                          if (a.body.isNotEmpty)
                            Text(a.body,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: hasImg
                                        ? Colors.white70
                                        : const Color(0xFF8A6A1F),
                                    fontSize: 12.5)),
                        ],
                      ),
                    ),
                  ),
              ]);
            },
          ),
        ),
      ),
      if (items.length > 1)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < items.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == _index ? 18 : 7,
                height: 7,
                decoration: BoxDecoration(
                  color: i == _index
                      ? const Color(0xFFE8805A)
                      : const Color(0xFFB8C4DD),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
          ]),
        ),
    ]);
  }
}
