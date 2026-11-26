import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../core/l10n.dart';
import '../../core/remote_ui.dart';
import 'data/admin_tools_repo.dart';

/// Admin: custom events that show in every student's schedule.
class AdminEventsScreen extends StatefulWidget {
  const AdminEventsScreen({super.key});

  @override
  State<AdminEventsScreen> createState() => _AdminEventsScreenState();
}

class _AdminEventsScreenState extends State<AdminEventsScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    RemoteUi.load().then((_) {
      _items = [for (final e in RemoteUi.events) Map<String, dynamic>.from(e)];
      if (mounted) setState(() => _loading = false);
    });
  }

  Future<void> _persist() async {
    final s = S.of(context);
    RemoteUi.events = _items;
    RemoteUi.version.value++;
    try {
      await AdminToolsRepository.saveSetting('ui_events', {'items': _items});
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(s.t('generic_error'))));
      }
    }
  }

  Future<void> _edit(int? index) async {
    final s = S.of(context);
    final cur = index == null ? <String, dynamic>{} : _items[index];
    final title = TextEditingController(text: (cur['title'] ?? '').toString());
    DateTime at = DateTime.tryParse((cur['at'] ?? '').toString())?.toLocal() ??
        DateTime.now().add(const Duration(days: 1));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(s.t('ev_title')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: title,
                decoration: InputDecoration(labelText: s.t('ev_name'))),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.event),
              label: Text(DateFormat('yyyy-MM-dd  HH:mm').format(at)),
              onPressed: () async {
                final d = await showDatePicker(
                    context: ctx,
                    initialDate: at,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100));
                if (d == null || !ctx.mounted) return;
                final t = await showTimePicker(
                    context: ctx, initialTime: TimeOfDay.fromDateTime(at));
                if (t == null) return;
                setD(() => at = DateTime(d.year, d.month, d.day, t.hour, t.minute));
              },
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
    if (ok != true || title.text.trim().isEmpty) return;
    final item = {'title': title.text.trim(), 'at': at.toUtc().toIso8601String()};
    setState(() {
      if (index == null) {
        _items.add(item);
      } else {
        _items[index] = item;
      }
    });
    await _persist();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('ui_events'))),
      floatingActionButton: FloatingActionButton(
          onPressed: () => _edit(null), child: const Icon(Icons.add)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(child: Text(s.t('mod_empty')))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _items.length,
                  itemBuilder: (_, i) {
                    final e = _items[i];
                    final d = DateTime.tryParse((e['at'] ?? '').toString())?.toLocal();
                    return Card(
                      child: ListTile(
                        title: Text((e['title'] ?? '').toString()),
                        subtitle: Text(d == null
                            ? ''
                            : DateFormat('yyyy-MM-dd  HH:mm').format(d)),
                        onTap: () => _edit(i),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.redAccent),
                          onPressed: () async {
                            setState(() => _items.removeAt(i));
                            await _persist();
                          },
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
