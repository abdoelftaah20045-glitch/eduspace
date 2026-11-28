import '../../core/maintenance.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/l10n.dart';
import 'data/support_repo.dart';
import 'ticket_screen.dart';

/// Student: my support tickets + create a new one.
class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  List<SupportTicket>? _tickets;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final tickets = await SupportRepository.fetchTickets();
      if (mounted) setState(() => _tickets = tickets);
    } catch (_) {
      if (mounted) setState(() => _tickets = const []);
    }
  }

  Future<void> _create() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => const _NewTicketDialog(),
    );
    if (created == true) await _load();
  }

  @override
  Widget build(BuildContext context) =>
      MaintenanceGate(pageKey: 'support', child: Builder(builder: _mtBuild));

  Widget _mtBuild(BuildContext context) {
    final s = S.of(context);
    final tickets = _tickets;
    return Scaffold(
      appBar: AppBar(title: Text(s.t('support'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: Text(s.t('new_ticket')),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: tickets == null
            ? const Center(child: CircularProgressIndicator())
            : tickets.isEmpty
                ? ListView(
                    padding: const EdgeInsets.all(32),
                    children: [
                      const SizedBox(height: 80),
                      const Icon(Icons.support_agent,
                          size: 56, color: Colors.grey),
                      const SizedBox(height: 12),
                      Center(
                        child: Text(s.t('no_tickets'),
                            style: const TextStyle(color: Colors.grey)),
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(4, 16, 4, 96),
                    itemCount: tickets.length,
                    itemBuilder: (context, i) {
                      final t = tickets[i];
                      return Card(
                        clipBehavior: Clip.antiAlias,
                        child: ListTile(
                          leading: const Icon(Icons.support_agent),
                          title: Text(t.subject,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                            '${s.t('status_${t.status}')} · '
                            '${DateFormat('d MMM y', s.locale.languageCode).format(t.createdAt)}',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.of(context)
                                .push(MaterialPageRoute(
                                    builder: (_) => TicketScreen(
                                        ticket: t, asAdmin: false)))
                                .then((_) => _load());
                          },
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}

class _NewTicketDialog extends StatefulWidget {
  const _NewTicketDialog();

  @override
  State<_NewTicketDialog> createState() => _NewTicketDialogState();
}

class _NewTicketDialogState extends State<_NewTicketDialog> {
  final _subject = TextEditingController();
  final _body = TextEditingController();
  String _category = 'general';
  bool _busy = false;

  @override
  void dispose() {
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return AlertDialog(
      title: Text(s.t('new_ticket')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _subject,
              decoration:
                  InputDecoration(labelText: s.t('ticket_subject')),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: InputDecoration(labelText: s.t('category_label')),
              items: ['general', 'payment', 'technical', 'content']
                  .map((c) => DropdownMenuItem(
                      value: c, child: Text(s.t('category_$c'))))
                  .toList(),
              onChanged: (v) => setState(() => _category = v ?? 'general'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _body,
              maxLines: 4,
              decoration:
                  InputDecoration(labelText: s.t('ticket_message')),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(s.t('cancel')),
        ),
        FilledButton(
          onPressed: _busy
              ? null
              : () async {
                  if (_subject.text.trim().isEmpty ||
                      _body.text.trim().isEmpty) {
                    return;
                  }
                  setState(() => _busy = true);
                  try {
                    await SupportRepository.createTicket(
                        _subject.text.trim(), _body.text.trim(), _category);
                    if (!mounted) return;
                    Navigator.of(context).pop(true);
                  } catch (_) {
                    if (mounted) {
                      setState(() => _busy = false);
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(s.t('generic_error'))));
                    }
                  }
                },
          child: Text(s.t('send')),
        ),
      ],
    );
  }
}
