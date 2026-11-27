import '../../core/admin_search.dart';
import '../../core/search_norm.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/l10n.dart';
import '../support/data/support_repo.dart';
import '../support/ticket_screen.dart';

/// Admin: all support tickets, newest activity first.
class AdminSupportScreen extends StatefulWidget {
  const AdminSupportScreen({super.key});

  @override
  State<AdminSupportScreen> createState() => _AdminSupportScreenState();
}

class _AdminSupportScreenState extends State<AdminSupportScreen> {
  List<SupportTicket>? _tickets;
  String _q = '';
  List<SupportTicket> get _shown => (_tickets ?? const <SupportTicket>[])
      .where((t) => matchesSearch(_q, [t.subject, t.studentName]))
      .toList();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final tickets = await SupportRepository.fetchTickets(admin: true);
      if (mounted) setState(() => _tickets = tickets);
    } catch (_) {
      if (mounted) setState(() => _tickets = const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final tickets = _tickets;
    return Scaffold(
      appBar: AppBar(title: Text(s.t('support'))),
      body: Column(children: [
        AdminSearchField(onChanged: (v) => setState(() => _q = v)),
        Expanded(child: RefreshIndicator(
        onRefresh: _load,
        child: tickets == null
            ? const Center(child: CircularProgressIndicator())
            : _shown.isEmpty
                ? ListView(
                    padding: const EdgeInsets.all(32),
                    children: [
                      const SizedBox(height: 80),
                      Center(child: Text(s.t('no_tickets'))),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _shown.length,
                    itemBuilder: (context, i) {
                      final t = _shown[i];
                      return Card(
                        clipBehavior: Clip.antiAlias,
                        child: ListTile(
                          leading: Icon(
                            t.status == 'new'
                                ? Icons.mark_email_unread_outlined
                                : Icons.support_agent,
                          ),
                          title: Text(t.subject,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                            '${t.studentName ?? ''} · ${s.t('status_${t.status}')} · '
                            '${DateFormat('d MMM y', s.locale.languageCode).format(t.createdAt)}',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.of(context)
                                .push(MaterialPageRoute(
                                    builder: (_) =>
                                        TicketScreen(ticket: t, asAdmin: true)))
                                .then((_) => _load());
                          },
                        ),
                      );
                    },
                  ),
      )),
      ]),
    );
  }
}
