import '../../core/maintenance.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/l10n.dart';
import '../../core/pressable.dart';

class _Task {
  _Task(this.id, this.title, this.day, this.done);
  final String id;
  final String title;
  final String day; // yyyy-MM-dd
  bool done;

  Map<String, dynamic> toJson() =>
      {'id': id, 'title': title, 'day': day, 'done': done};

  factory _Task.fromJson(Map<String, dynamic> m) => _Task(
      m['id'] as String,
      m['title'] as String,
      m['day'] as String,
      m['done'] == true);
}

/// Study planner: personal daily tasks, saved on the device (free, no
/// server). Shows today's progress and a day streak.
class StudyPlannerScreen extends StatefulWidget {
  const StudyPlannerScreen({super.key});

  @override
  State<StudyPlannerScreen> createState() => _StudyPlannerScreenState();
}

class _StudyPlannerScreenState extends State<StudyPlannerScreen> {
  static const _key = 'study_planner_tasks_v1';
  List<_Task> _tasks = [];
  bool _loaded = false;
  final _fmt = DateFormat('yyyy-MM-dd');

  String get _today => _fmt.format(DateTime.now());

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key);
      if (raw != null) {
        _tasks = [
          for (final m in jsonDecode(raw) as List)
            _Task.fromJson(Map<String, dynamic>.from(m as Map))
        ];
      }
    } catch (_) {}
    if (mounted) setState(() => _loaded = true);
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key, jsonEncode([for (final t in _tasks) t.toJson()]));
    } catch (_) {}
  }

  int get _streak {
    var n = 0;
    var d = DateTime.now();
    for (var i = 0; i < 365; i++) {
      final key = _fmt.format(d);
      final day = _tasks.where((t) => t.day == key).toList();
      final ok = day.isNotEmpty && day.every((t) => t.done);
      if (ok) {
        n++;
      } else if (i > 0 || day.isNotEmpty) {
        break;
      }
      d = d.subtract(const Duration(days: 1));
    }
    return n;
  }

  Future<void> _add() async {
    final s = S.of(context);
    final c = TextEditingController();
    var day = DateTime.now();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(s.t('planner_add')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: c,
              autofocus: true,
              decoration: InputDecoration(labelText: s.t('planner_task_hint')),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final d = await showDatePicker(
                  context: ctx,
                  initialDate: day,
                  firstDate: DateTime.now().subtract(const Duration(days: 1)),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (d != null) setD(() => day = d);
              },
              icon: const Icon(Icons.event),
              label: Text(DateFormat.yMMMd().format(day)),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(s.t('cancel'))),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(s.t('save'))),
          ],
        ),
      ),
    );
    if (ok != true || c.text.trim().isEmpty) return;
    setState(() => _tasks.add(_Task(
        DateTime.now().microsecondsSinceEpoch.toString(),
        c.text.trim(),
        _fmt.format(day),
        false)));
    _save();
  }

  @override
  Widget build(BuildContext context) =>
      MaintenanceGate(pageKey: 'planner', child: Builder(builder: _mtBuild));

  Widget _mtBuild(BuildContext context) {
    final s = S.of(context);
    final today = _tasks.where((t) => t.day == _today).toList();
    final doneToday = today.where((t) => t.done).length;
    final pct = today.isEmpty ? 0.0 : doneToday / today.length;
    final others = _tasks.where((t) => t.day != _today).toList()
      ..sort((a, b) => a.day.compareTo(b.day));
    return Scaffold(
      appBar: AppBar(title: Text(s.t('planner_title'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: Text(s.t('planner_add')),
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 96),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Color(0xFFE8805A), Color(0xFFD96A43)]),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(children: [
                    SizedBox(
                      width: 78,
                      height: 78,
                      child: Stack(alignment: Alignment.center, children: [
                        SizedBox(
                          width: 78,
                          height: 78,
                          child: CircularProgressIndicator(
                            value: pct,
                            strokeWidth: 8,
                            strokeCap: StrokeCap.round,
                            backgroundColor: Colors.white24,
                            valueColor:
                                const AlwaysStoppedAnimation(Colors.white),
                          ),
                        ),
                        Text('${(pct * 100).round()}%',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 18)),
                      ]),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.t('planner_today'),
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 13)),
                          Text('$doneToday / ${today.length}',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          Row(children: [
                            const Icon(Icons.local_fire_department,
                                color: Color(0xFFFFB020), size: 20),
                            const SizedBox(width: 4),
                            Text('${s.t('planner_streak')}: $_streak',
                                style: const TextStyle(color: Colors.white)),
                          ]),
                        ],
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 18),
                if (_tasks.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(children: [
                      Icon(Icons.checklist_rounded,
                          size: 64,
                          color: Theme.of(context).colorScheme.primary),
                      const SizedBox(height: 8),
                      Text(s.t('planner_empty'), textAlign: TextAlign.center),
                    ]),
                  ),
                for (final t in today) _tile(t),
                if (others.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(s.t('planner_upcoming'),
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  for (final t in others) _tile(t, showDay: true),
                ],
              ],
            ),
    );
  }

  Widget _tile(_Task t, {bool showDay = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Dismissible(
        key: ValueKey(t.id),
        onDismissed: (_) {
          setState(() => _tasks.removeWhere((x) => x.id == t.id));
          _save();
        },
        background: Container(
          decoration: BoxDecoration(
              color: const Color(0xFFE53935),
              borderRadius: BorderRadius.circular(8)),
          alignment: AlignmentDirectional.centerEnd,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: const Icon(Icons.delete_outline, color: Colors.white),
        ),
        child: Pressable(
          radius: 16,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          onTap: () {
            setState(() => t.done = !t.done);
            _save();
          },
          child: ListTile(
            leading: Icon(
                t.done ? Icons.check_circle : Icons.radio_button_unchecked,
                color: t.done
                    ? const Color(0xFF16A34A)
                    : Theme.of(context).colorScheme.outline),
            title: Text(t.title,
                style: TextStyle(
                    decoration: t.done ? TextDecoration.lineThrough : null,
                    color: t.done ? Colors.grey : null,
                    fontWeight: FontWeight.w600)),
            subtitle: showDay ? Text(t.day) : null,
          ),
        ),
      ),
    );
  }
}
