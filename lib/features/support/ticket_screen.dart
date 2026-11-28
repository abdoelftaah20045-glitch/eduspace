import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/l10n.dart';
import 'data/support_repo.dart';
import 'ticket_student_card.dart';

/// One ticket thread with a reply box. Used by students and admins.
class TicketScreen extends StatefulWidget {
  const TicketScreen({super.key, required this.ticket, required this.asAdmin});

  final SupportTicket ticket;
  final bool asAdmin;

  @override
  State<TicketScreen> createState() => _TicketScreenState();
}

class _TicketScreenState extends State<TicketScreen> {
  final _reply = TextEditingController();
  List<SupportMessage>? _messages;
  late String _status = widget.ticket.status;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final messages =
          await SupportRepository.fetchMessages(widget.ticket.id);
      if (mounted) setState(() => _messages = messages);
    } catch (_) {
      if (mounted) setState(() => _messages = const []);
    }
  }

  Future<void> _send() async {
    final s = S.of(context);
    if (_reply.text.trim().isEmpty) return;
    setState(() => _sending = true);
    try {
      await SupportRepository.reply(
          ticket: widget.ticket, body: _reply.text.trim(),
          asAdmin: widget.asAdmin);
      _reply.clear();
      await _load();
      if (mounted) {
        setState(() => _status = widget.asAdmin ? 'waiting_user' : 'new');
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(s.t('generic_error'))));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _setStatus(String status) async {
    await SupportRepository.setStatus(widget.ticket.id, status);
    if (mounted) setState(() => _status = status);
  }

  /// Messages plus, for the student only, an automatic acknowledgement
  /// while no admin has replied yet. Text editable in admin Texts
  /// (key support_auto_reply). Display only, nothing is stored.
  List<SupportMessage> _shown() {
    final list = _messages ?? const <SupportMessage>[];
    if (widget.asAdmin || list.isEmpty || list.any((m) => m.isAdmin)) {
      return list;
    }
    final text = S.of(context).t('support_auto_reply').trim();
    if (text.isEmpty) return list;
    return [
      list.first,
      SupportMessage(
          id: 'auto',
          senderId: 'system',
          body: text,
          isAdmin: true,
          createdAt: list.first.createdAt.add(const Duration(seconds: 1))),
      ...list.skip(1),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.ticket.subject,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (widget.asAdmin)
            PopupMenuButton<String>(
              onSelected: _setStatus,
              itemBuilder: (_) => [
                'new',
                'in_progress',
                'waiting_user',
                'resolved',
                'closed'
              ]
                  .map((st) => PopupMenuItem(
                      value: st, child: Text(s.t('status_$st'))))
                  .toList(),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                child: Text(s.t('status_$_status'),
                    style: const TextStyle(fontSize: 13)),
              ),
            )
          else
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Text(s.t('status_$_status'),
                  style: const TextStyle(fontSize: 13)),
            ),
        ],
      ),
      body: Column(
        children: [
          if (widget.asAdmin) TicketStudentCard(userId: widget.ticket.userId),
          Expanded(
            child: _messages == null
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 16),
                    itemCount: _shown().length,
                    itemBuilder: (context, i) {
                      final m = _shown()[i];
                      final mine = !m.isAdmin && !widget.asAdmin ||
                          m.isAdmin && widget.asAdmin;
                      return Align(
                        alignment: mine
                            ? AlignmentDirectional.centerEnd
                            : AlignmentDirectional.centerStart,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          constraints: BoxConstraints(
                              maxWidth:
                                  MediaQuery.of(context).size.width * 0.8),
                          decoration: BoxDecoration(
                            color: mine
                                ? theme.colorScheme.primary
                                    .withValues(alpha: .12)
                                : theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (m.isAdmin)
                                Text(s.t('support_team'),
                                    style: theme.textTheme.labelSmall),
                              Text(m.body),
                              Text(
                                DateFormat('d MMM, h:mm a',
                                        s.locale.languageCode)
                                    .format(m.createdAt),
                                style: theme.textTheme.labelSmall,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _reply,
                      decoration:
                          InputDecoration(hintText: s.t('reply_label')),
                      minLines: 1,
                      maxLines: 4,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
