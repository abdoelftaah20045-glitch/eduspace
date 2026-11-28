import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/cached_avatar.dart';
import '../../core/l10n.dart';
import '../../core/remote_ui.dart';
import '../certificates/my_certificates_screen.dart';
import '../courses/course_details_screen.dart';
import '../courses/courses_screen.dart';
import '../courses/data/course_models.dart';
import '../courses/data/courses_repo.dart';
import '../exams/exams_screen.dart';
import '../library/library_screen.dart';
import '../lives/lives_screen.dart';
import '../qbank/question_bank_screen.dart';
import '../schedule/schedule_screen.dart';
import '../support/support_screen.dart';
import 'hero_banner.dart';

/// Where a block or tile can lead. Stored as text so admins can set it.
/// 'screen:courses' | 'screen:lives' | ... | 'course:<id>' | 'https://...'
const homeScreenLinks = <String, String>{
  'courses': 'الكورسات',
  'lives': 'اللايفات',
  'exams': 'الامتحانات',
  'library': 'المكتبة',
  'qbank': 'بنك الأسئلة',
  'schedule': 'الجدول',
  'certs': 'الشهادات',
  'support': 'الدعم',
};

Future<void> openHomeLink(BuildContext context, String? link) async {
  final l = (link ?? '').trim();
  if (l.isEmpty) return;
  Widget? page;
  if (l.startsWith('course:')) {
    page = CourseDetailsScreen(courseId: l.substring(7));
  } else if (l.startsWith('screen:')) {
    switch (l.substring(7)) {
      case 'courses':
        page = const CoursesScreen();
      case 'lives':
        page = const LivesScreen();
      case 'exams':
        page = const ExamsScreen();
      case 'library':
        page = const LibraryScreen();
      case 'qbank':
        page = const QuestionBankScreen();
      case 'schedule':
        page = const ScheduleScreen();
      case 'certs':
        page = const MyCertificatesScreen();
      case 'support':
        page = const SupportScreen();
    }
  } else if (l.startsWith('http')) {
    await launchUrl(Uri.parse(l), mode: LaunchMode.externalApplication);
    return;
  }
  if (page != null && context.mounted) {
    final p = page;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => p));
  }
}

/// Renders one admin-defined Home block (see AdminHomeBuilderScreen).
class HomeBlock extends StatefulWidget {
  const HomeBlock({super.key, required this.block});
  final Map<String, dynamic> block;

  @override
  State<HomeBlock> createState() => _HomeBlockState();
}

List<Course>? _allCourses;
DateTime? _allCoursesAt;

class _HomeBlockState extends State<HomeBlock> {
  List<Course>? _courses = _allCourses;

  String get _type => '${widget.block['type'] ?? ''}';

  @override
  void initState() {
    super.initState();
    if (_type == 'courses' || _type == 'categories' || _type == 'numbered' || _type == 'chips' || _type == 'hero') _fetch();
  }

  Future<void> _fetch() async {
    final fresh = _allCoursesAt != null &&
        DateTime.now().difference(_allCoursesAt!).inSeconds < 60;
    if (fresh && _allCourses != null) return;
    try {
      final rows = await CoursesRepository.fetchCourses();
      _allCourses = rows.where((c) => c.status == 'published').toList();
      _allCoursesAt = DateTime.now();
      if (mounted) setState(() => _courses = _allCourses);
    } catch (_) {
      if (mounted && _courses == null) setState(() => _courses = const []);
    }
  }

  Widget _title(BuildContext context, String t) {
    if (t.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(t,
          style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.onSurface)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.block;
    final title = '${b['title'] ?? ''}';
    switch (_type) {
      case 'hero':
        return _hero(context);
      case 'banner':
        return _banner(context, b);
      case 'tiles':
        return _tiles(context, b, title);
      case 'courses':
        return _coursesBlock(context, b, title);
      case 'categories':
        return _categories(context, b, title);
      case 'chips':
        return _chips(context);
      case 'numbered':
        return _numbered(context, b, title);
      case 'text':
        return Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _title(context, title),
            if ('${b['body'] ?? ''}'.isNotEmpty) Text('${b['body']}'),
          ]),
        );
    }
    return const SizedBox.shrink();
  }

  Widget _hero(BuildContext context) {
    final source = RemoteUi.homeBlocksSet ? RemoteUi.homeBlocks : defaultHomeBlocks;
    final slides = <HeroSlide>[];
    for (final x in source) {
      if (x['type'] == 'banner' && x['enabled'] != false && '${x['image'] ?? ''}'.isNotEmpty) {
        slides.add(HeroSlide(
            title: '${x['title'] ?? ''}',
            image: '${x['image']}',
            onTap: () => openHomeLink(context, '${x['link'] ?? ''}')));
      }
    }
    final cs = [...(_courses ?? const <Course>[])]
      ..sort((a, c) => (c.ratingAvg ?? 0).compareTo(a.ratingAvg ?? 0));
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    for (final c in cs.take(5)) {
      if ((c.coverUrl ?? '').isEmpty) continue;
      slides.add(HeroSlide(
          title: c.title,
          subtitle: c.instructorName ?? '',
          image: c.coverUrl,
          cta: ar ? 'ابدأ الآن' : 'Start now',
          onTap: () => openHomeLink(context, 'course:${c.id}')));
    }
    if (slides.isEmpty) return const SizedBox.shrink();
    return HeroBanner(slides: slides);
  }

  Widget _banner(BuildContext context, Map<String, dynamic> b) {
    final img = '${b['image'] ?? ''}';
    final t = '${b['title'] ?? ''}';
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => openHomeLink(context, '${b['link'] ?? ''}'),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: AspectRatio(
            aspectRatio: 16 / 7,
            child: Stack(fit: StackFit.expand, children: [
              if (img.isNotEmpty)
                CachedImage(img,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    errorBuilder: (_, __, ___) =>
                        Container(color: scheme.primaryContainer))
              else
                Container(
                    decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [
                  scheme.primary,
                  scheme.primary.withValues(alpha: .6)
                ]))),
              if (t.isNotEmpty)
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: 12,
                  child: Text(t,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          shadows: [Shadow(blurRadius: 6, color: Colors.black87)])),
                ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _tiles(BuildContext context, Map<String, dynamic> b, String title) {
    final items = [
      for (final e in (b['items'] as List? ?? const []))
        if (e is Map) Map<String, dynamic>.from(e),
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _title(context, title),
        Wrap(
          spacing: 10,
          runSpacing: 12,
          children: [
            for (final it in items)
              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => openHomeLink(context, '${it['link'] ?? ''}'),
                child: SizedBox(
                  width: 76,
                  child: Column(children: [
                    Container(
                      width: 52,
                      height: 52,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: _tileIcon('${it['icon'] ?? ''}'),
                    ),
                    const SizedBox(height: 6),
                    Text('${it['label'] ?? ''}',
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.5)),
                  ]),
                ),
              ),
          ],
        ),
      ]),
    );
  }

  Widget _tileIcon(String v) {
    if (v.startsWith('http')) {
      return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: CachedImage(v,
              width: 34,
              height: 34,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox.shrink()));
    }
    return Text(v.isEmpty ? '⭐' : v, style: const TextStyle(fontSize: 26));
  }

  List<Course> _pick(Map<String, dynamic> b) {
    var list = List<Course>.of(_courses ?? const []);
    final src = '${b['source'] ?? 'latest'}';
    if (src == 'free') {
      list = list.where((c) => c.price <= 0).toList();
    } else if (src == 'category') {
      final cat = '${b['category'] ?? ''}'.trim();
      list = list.where((c) => (c.field ?? '').trim() == cat).toList();
    } else if (src == 'rated') {
      list.sort((a, c) => (c.ratingAvg ?? 0).compareTo(a.ratingAvg ?? 0));
    }
    final n = (b['rows'] is num) ? (b['rows'] as num).toInt() : 6;
    return list.take(n.clamp(1, 30)).toList();
  }

  Widget _coursesBlock(
      BuildContext context, Map<String, dynamic> b, String title) {
    if (_courses == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _title(context, title),
          SizedBox(
            height: 150,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (var i = 0; i < 3; i++) _skeleton(context),
            ]),
          ),
        ]),
      );
    }
    final list = _pick(b);
    if (list.isEmpty) return const SizedBox.shrink();
    final style = '${b['style'] ?? 'row'}';
    Widget body;
    if (style == 'grid') {
      body = GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.82,
        children: [for (final c in list) _card(context, c)],
      );
    } else if (style == 'list') {
      body = Column(children: [
        for (final c in list)
          Card(
            child: ListTile(
              leading: SizedBox(
                width: 64,
                child: _cover(context, c),
              ),
              title: Text(c.title, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text(c.price <= 0
                  ? S.of(context).t('free')
                  : '${c.price.toStringAsFixed(0)} ${c.currency}'),
              onTap: () => openHomeLink(context, 'course:${c.id}'),
            ),
          ),
      ]);
    } else {
      body = SizedBox(
        height: 206,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (_, i) => SizedBox(width: 190, child: _card(context, list[i])),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _title(context, title),
        body,
      ]),
    );
  }

  Widget _skeleton(BuildContext context) => Container(
        width: 190,
        margin: const EdgeInsetsDirectional.only(end: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
      );

  Widget _cover(BuildContext context, Course c) {
    final scheme = Theme.of(context).colorScheme;
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        color: scheme.surfaceContainerHighest,
        child: (c.coverUrl ?? '').isNotEmpty
            ? CachedImage(c.coverUrl!,
                fit: BoxFit.cover,
                width: double.infinity,
                errorBuilder: (_, __, ___) => const SizedBox.shrink())
            : null,
      ),
    );
  }

  Widget _card(BuildContext context, Course c) {
    final scheme = Theme.of(context).colorScheme;
    final s = S.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => openHomeLink(context, 'course:${c.id}'),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _cover(context, c),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
              const SizedBox(height: 2),
              Text(
                  c.price <= 0
                      ? s.t('free')
                      : '${c.price.toStringAsFixed(0)} ${c.currency}',
                  style: TextStyle(color: scheme.primary, fontSize: 12)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _categories(
      BuildContext context, Map<String, dynamic> b, String title) {
    final counts = <String, int>{};
    for (final c in _courses ?? const <Course>[]) {
      final f = (c.field ?? '').trim();
      if (f.isNotEmpty) counts[f] = (counts[f] ?? 0) + 1;
    }
    if (counts.isEmpty) return const SizedBox.shrink();
    final names = counts.keys.toList()
      ..sort((a, c) => counts[c]!.compareTo(counts[a]!));
    final n = (b['rows'] is num) ? (b['rows'] as num).toInt() : 8;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _title(context, title),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final name in names.take(n.clamp(1, 40)))
            ActionChip(
              backgroundColor: scheme.primaryContainer,
              side: BorderSide.none,
              labelStyle: TextStyle(
                  color: scheme.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                  fontSize: 13),
              label: Text('$name  \u00b7  ${counts[name]}'),
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CoursesScreen())),
            ),
        ]),
      ]),
    );
  }

  Widget _chips(BuildContext context) {
    final counts = <String, int>{};
    for (final c in _courses ?? const <Course>[]) {
      final f = (c.field ?? '').trim();
      if (f.isNotEmpty) counts[f] = (counts[f] ?? 0) + 1;
    }
    if (counts.isEmpty) return const SizedBox.shrink();
    final names = counts.keys.toList()
      ..sort((a, c) => counts[c]!.compareTo(counts[a]!));
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: SizedBox(
        height: 40,
        child: ListView(scrollDirection: Axis.horizontal, children: [
          for (final n in names.take(14))
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: ActionChip(
                label: Text(n),
                onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const CoursesScreen())),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _numbered(BuildContext context, Map<String, dynamic> b, String title) {
    final list = _pick({...b, 'rows': b['rows'] ?? 10});
    if (list.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _title(context, title),
        SizedBox(
          height: 190,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: list.length,
            padding: const EdgeInsetsDirectional.only(end: 16),
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) => SizedBox(
              width: 160,
              child: _card(context, list[i]),
            ),
          ),
        ),
      ]),
    );
  }
}

/// Puts the admin's custom blocks between the built-in Home sections.
/// A block's `at` is the number of built-in sections before it (0 = top).
List<Widget> mergeHomeBlocks(List<List<Widget>> sections) {
  final source = RemoteUi.homeBlocksSet ? RemoteUi.homeBlocks : defaultHomeBlocks;
  final hasHero = true; // the hero carousel is always on top, banners feed into it
  final blocks = [
    if (!source.any((b) => b['type'] == 'hero'))
      <String, dynamic>{'id': 'auto_hero', 'type': 'hero', 'at': 0},
    for (final b in source)
      if (b['enabled'] != false &&
          b['type'] != 'categories' &&
          !(hasHero && b['type'] == 'banner'))
        b,
  ];
  int at(Map<String, dynamic> b) =>
      (b['at'] is num) ? (b['at'] as num).toInt() : 999;
  final out = <Widget>[];
  for (var i = 0; i <= sections.length; i++) {
    for (final b in blocks.where((b) => at(b).clamp(0, sections.length) == i)) {
      out.add(HomeBlock(key: ValueKey('hb_${b['id']}_${b.hashCode}'), block: b));
    }
    if (i < sections.length) out.addAll(sections[i]);
  }
  return out;
}

/// Fuller Home out of the box, until the admin saves his own layout.
const List<Map<String, dynamic>> defaultHomeBlocks = [
  {'id': 'd_hero', 'type': 'hero', 'at': 0},
  {'id': 'd_chips', 'type': 'chips', 'at': 0},
  {'id': 'd_best', 'type': 'numbered', 'title': 'الأفضل اليوم', 'at': 5, 'rows': 10, 'source': 'rated'},
  {'id': 'd_new', 'type': 'courses', 'title': 'أحدث الكورسات', 'at': 6, 'rows': 8, 'style': 'row', 'source': 'latest'},
  {'id': 'd_free', 'type': 'courses', 'title': 'كورسات مجانية', 'at': 7, 'rows': 8, 'style': 'row', 'source': 'free'},
];
