import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../core/remote_ui.dart';
import 'data/admin_tools_repo.dart';

/// One controllable element: id used by the app, label key for its name.
class _Item {
  const _Item(this.id, this.label);
  final String id;
  final String label;
}

const _courseItems = [
  _Item('courses.search', 'search_courses'),
  _Item('courses.categories', 'cat_all'),
  _Item('courses.filters', 'cat_in_progress'),
  _Item('courses.continue', 'continue_learning'),
];
const _certItems = [
  _Item('cert.logo', 'cert_logo'),
  _Item('cert.signature', 'cert_signature'),
  _Item('cert.qr', 'cert_qr'),
];
const _coursePage = [
  _Item('course.progress', 'cd_complete'),
  _Item('course.stats', 'level_label'),
  _Item('course.learn', 'cd_learn'),
  _Item('course.skills', 'cd_skills'),
  _Item('course.about', 'cd_about'),
  _Item('course.syllabus', 'cd_syllabus'),
  _Item('course.schedule', 'cd_weekly'),
  _Item('course.instructor', 'cd_instructor'),
  _Item('course.details', 'cd_details'),
  _Item('course.reviews', 'cd_reviews'),
];

const _home = [
  _Item('home.continue', 'continue_learning'),
  _Item('home.banner', 'ann_title'),
  _Item('home.my_courses', 'my_courses'),
  _Item('home.lives', 'lv_title'),
  _Item('home.discover', 'discover_label'),
  _Item('home.tiles', 'sections_label'),
];
const _quick = [
  _Item('quick.courses', 'my_courses'),
  _Item('quick.lives', 'lv_title'),
  _Item('quick.exams', 'tab_exams'),
  _Item('quick.library', 'library_label'),
  _Item('quick.qbank', 'qb_title'),
  _Item('quick.schedule', 'sch_title'),
  _Item('quick.certs', 'my_certificates'),
  _Item('quick.support', 'support'),
];
const _drawer = [
  _Item('drawer.qb_title', 'qb_title'),
  _Item('drawer.sch_title', 'sch_title'),
  _Item('drawer.planner_title', 'planner_title'),
  _Item('drawer.perf_title', 'perf_title'),
  _Item('drawer.ai_title', 'ai_title'),
  _Item('drawer.help_title', 'help_title'),
  _Item('drawer.lb_title', 'lb_title'),
  _Item('drawer.lv_title', 'lv_title'),
  _Item('drawer.ann_title', 'ann_title'),
  _Item('drawer.notifications', 'notifications'),
  _Item('drawer.dr_library', 'dr_library'),
  _Item('drawer.dr_favorites', 'dr_favorites'),
];

const _tabItems = [
  _Item('tab.my', 'my_courses'),
  _Item('tab.courses', 'tab_courses'),
  _Item('tab.exams', 'tab_exams'),
];
const _profileItems = [
  _Item('profile.edit', 'edit_profile'),
  _Item('profile.favorites', 'favorites'),
  _Item('profile.certs', 'my_certificates'),
  _Item('profile.library', 'library_label'),
  _Item('profile.downloads', 'dl_title'),
  _Item('profile.support', 'support'),
  _Item('profile.settings', 'settings'),
];

/// Admin: show/hide and reorder Home sections, Home tiles and menu items.
class AdminLayoutScreen extends StatefulWidget {
  const AdminLayoutScreen({super.key});

  @override
  State<AdminLayoutScreen> createState() => _AdminLayoutScreenState();
}

class _AdminLayoutScreenState extends State<AdminLayoutScreen> {
  bool _loading = true;
  bool _saving = false;
  final Map<String, bool> _vis = {};
  late List<_Item> _quickOrder;
  late List<_Item> _drawerOrder;
  late List<_Item> _cpOrder;
  late List<_Item> _homeOrder;
  late List<_Item> _tabOrder;

  @override
  void initState() {
    super.initState();
    _quickOrder = [..._quick];
    _drawerOrder = [..._drawer];
    _cpOrder = [..._coursePage];
    _homeOrder = [..._home];
    _tabOrder = [..._tabItems];
    RemoteUi.load().then((_) {
      for (final it in [..._home, ..._quick, ..._drawer, ..._courseItems, ..._certItems, ..._coursePage, ..._tabItems, ..._profileItems]) {
        _vis[it.id] = RemoteUi.visible(it.id);
      }
      int ord(_Item a, List<_Item> base) =>
          RemoteUi.order(a.id, base.indexOf(a));
      _quickOrder.sort((a, b) => ord(a, _quick).compareTo(ord(b, _quick)));
      _drawerOrder.sort((a, b) => ord(a, _drawer).compareTo(ord(b, _drawer)));
      _homeOrder.sort((a, b) => ord(a, _home).compareTo(ord(b, _home)));
      _tabOrder.sort((a, b) => ord(a, _tabItems).compareTo(ord(b, _tabItems)));
      _cpOrder.sort((a, b) => ord(a, _coursePage).compareTo(ord(b, _coursePage)));
      if (mounted) setState(() => _loading = false);
    });
  }

  Future<void> _save() async {
    final s = S.of(context);
    setState(() => _saving = true);
    final out = <String, Map<String, dynamic>>{};
    for (var i = 0; i < _homeOrder.length; i++) {
      final it = _homeOrder[i];
      out[it.id] = {'visible': _vis[it.id] ?? true, 'order': i};
    }
    for (var i = 0; i < _quickOrder.length; i++) {
      final it = _quickOrder[i];
      out[it.id] = {'visible': _vis[it.id] ?? true, 'order': i};
    }
    for (final it in [..._courseItems, ..._certItems, ..._profileItems]) {
      out[it.id] = {'visible': _vis[it.id] ?? true};
    }
    for (var i = 0; i < _tabOrder.length; i++) {
      final it = _tabOrder[i];
      out[it.id] = {'visible': _vis[it.id] ?? true, 'order': i};
    }
    for (var i = 0; i < _cpOrder.length; i++) {
      final it = _cpOrder[i];
      out[it.id] = {'visible': _vis[it.id] ?? true, 'order': i};
    }
    for (var i = 0; i < _drawerOrder.length; i++) {
      final it = _drawerOrder[i];
      out[it.id] = {'visible': _vis[it.id] ?? true, 'order': i};
    }
    try {
      RemoteUi.setLayout(out);
      await AdminToolsRepository.saveSetting('ui_layout', out);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(s.t('saved'))));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(s.t('generic_error'))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _title(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
        child: Text(t,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      );

  Widget _switch(S s, _Item it) => SwitchListTile(
        dense: true,
        value: _vis[it.id] ?? true,
        title: Text(s.t(it.label)),
        onChanged: (v) => setState(() => _vis[it.id] = v),
      );

  Widget _reorder(S s, List<_Item> list) => ReorderableListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        onReorder: (a, b) => setState(() {
          if (b > a) b -= 1;
          list.insert(b, list.removeAt(a));
        }),
        children: [
          for (final it in list)
            SwitchListTile(
              key: ValueKey(it.id),
              dense: true,
              secondary: const Icon(Icons.drag_handle),
              value: _vis[it.id] ?? true,
              title: Text(s.t(it.label)),
              onChanged: (v) => setState(() => _vis[it.id] = v),
            ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('ui_layout'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 90),
              children: [
                _title('الشريط السفلي (الرئيسية والحساب ثابتين)'),
                _reorder(s, _tabOrder),
                _title(s.t('tab_account')),
                for (final it in _profileItems) _switch(s, it),
                _title(s.t('ui_layout_home')),
                _reorder(s, _homeOrder),
                _title(s.t('tab_courses')),
                for (final it in _courseItems) _switch(s, it),
                _title(s.t('cd_about')),
                _reorder(s, _cpOrder),
                _title(s.t('ui_layout_tiles')),
                _reorder(s, _quickOrder),
                _title(s.t('my_certificates')),
                for (final it in _certItems) _switch(s, it),
                _title(s.t('ui_layout_menu')),
                _reorder(s, _drawerOrder),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saving ? null : _save,
        icon: const Icon(Icons.save),
        label: Text(s.t('save')),
      ),
    );
  }
}
