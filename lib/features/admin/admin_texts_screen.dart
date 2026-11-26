import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../core/remote_ui.dart';
import 'data/admin_tools_repo.dart';

const _langs = ['ar', 'en', 'fr', 'es', 'de'];
const _langNames = {
  'ar': 'العربية',
  'en': 'English',
  'fr': 'Français',
  'es': 'Español',
  'de': 'Deutsch',
};

/// Admin: edit ANY text in the app, in every language. Empty = default.
class AdminTextsScreen extends StatefulWidget {
  const AdminTextsScreen({super.key});

  @override
  State<AdminTextsScreen> createState() => _AdminTextsScreenState();
}

class _AdminTextsScreenState extends State<AdminTextsScreen> {
  final _q = TextEditingController();
  late List<String> _keys;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _keys = S.keys.toList()..sort();
    RemoteUi.load().then((_) {
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _persist() async {
    await AdminToolsRepository.saveSetting('ui_texts', {
      for (final e in RemoteUi.texts.entries) e.key: e.value,
    });
  }

  Future<void> _edit(String key) async {
    final s = S.of(context);
    final ctrls = {
      for (final l in _langs)
        l: TextEditingController(
            text: RemoteUi.texts[key]?[l] ?? S.defaultOf(key, l)),
    };
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(key, style: const TextStyle(fontSize: 14)),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final l in _langs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TextField(
                    controller: ctrls[l],
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(labelText: _langNames[l]),
                  ),
                ),
            ]),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'reset'),
              child: Text(s.t('reset_default'))),
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(s.t('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, 'save'),
              child: Text(s.t('save'))),
        ],
      ),
    );
    if (res == null) return;
    final next = {
      for (final e in RemoteUi.texts.entries) e.key: Map<String, String>.from(e.value),
    };
    if (res == 'reset') {
      next.remove(key);
    } else {
      final changed = <String, String>{};
      for (final l in _langs) {
        final v = ctrls[l]!.text.trim();
        if (v.isNotEmpty && v != S.defaultOf(key, l)) changed[l] = v;
      }
      if (changed.isEmpty) {
        next.remove(key);
      } else {
        next[key] = changed;
      }
    }
    try {
      RemoteUi.setTexts(next);
      await _persist();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(s.t('generic_error'))));
      }
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final q = _q.text.trim().toLowerCase();
    final shown = _keys.where((k) {
      if (q.isEmpty) return true;
      if (k.toLowerCase().contains(q)) return true;
      for (final l in _langs) {
        if (S.defaultOf(k, l).toLowerCase().contains(q)) return true;
      }
      return false;
    }).toList();
    return Scaffold(
      appBar: AppBar(title: Text(s.t('ui_texts'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  controller: _q,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: s.t('ui_texts_search'),
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: shown.length,
                  itemBuilder: (_, i) {
                    final k = shown[i];
                    final edited = RemoteUi.texts.containsKey(k);
                    return ListTile(
                      dense: true,
                      title: Text(
                          RemoteUi.text(k, lang) ?? S.defaultOf(k, lang),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      subtitle: Text(k, style: const TextStyle(fontSize: 11)),
                      trailing: edited
                          ? const Icon(Icons.edit, size: 18, color: Colors.orange)
                          : const Icon(Icons.chevron_right, size: 18),
                      onTap: () => _edit(k),
                    );
                  },
                ),
              ),
            ]),
    );
  }
}
