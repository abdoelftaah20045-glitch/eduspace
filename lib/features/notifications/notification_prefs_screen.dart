import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import 'data/notifications_repo.dart';

/// Per-category notification preferences (doc section 18).
class NotificationPrefsScreen extends StatefulWidget {
  const NotificationPrefsScreen({super.key});

  @override
  State<NotificationPrefsScreen> createState() =>
      _NotificationPrefsScreenState();
}

class _NotificationPrefsScreenState extends State<NotificationPrefsScreen> {
  Map<String, bool>? _prefs;
  bool _saving = false;

  static const _categories = [
    'announcements',
    'courses',
    'exams',
    'certificates',
    'general',
  ];

  @override
  void initState() {
    super.initState();
    NotificationsRepository.fetchPrefs().then((p) {
      if (mounted) setState(() => _prefs = p);
    });
  }

  Future<void> _save() async {
    final s = S.of(context);
    final prefs = _prefs;
    if (prefs == null) return;
    setState(() => _saving = true);
    try {
      await NotificationsRepository.savePrefs(prefs);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.t('prefs_saved_note'))));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.t('generic_error'))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final prefs = _prefs;
    return Scaffold(
      appBar: AppBar(title: Text(s.t('notification_prefs'))),
      body: prefs == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                ..._categories.map((c) => SwitchListTile(
                      title: Text(s.t('pref_$c')),
                      value: prefs[c] ?? true,
                      onChanged: (v) => setState(() => prefs[c] = v),
                    )),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(s.t('save')),
                  ),
                ),
              ],
            ),
    );
  }
}
