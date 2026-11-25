import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/l10n.dart';
import 'data/notifications_repo.dart';

/// In-app notifications list. Tapping an unread item marks it read.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<AppNotification>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await NotificationsRepository.fetchMine();
      if (mounted) setState(() => _items = items);
    } catch (_) {
      if (mounted) setState(() => _items = const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('notifications')),
        actions: [
          if ((_items ?? []).any((n) => !n.isRead))
            IconButton(
              tooltip: s.t('mark_all_read'),
              icon: const Icon(Icons.done_all),
              onPressed: () async {
                await NotificationsRepository.markAllRead();
                await _load();
              },
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _items == null
            ? const Center(child: CircularProgressIndicator())
            : _items!.isEmpty
                ? ListView(
                    children: [
                      const SizedBox(height: 120),
                      const Icon(Icons.notifications_none,
                          size: 56, color: Colors.grey),
                      const SizedBox(height: 12),
                      Center(
                        child: Text(s.t('no_notifications'),
                            style: const TextStyle(color: Colors.grey)),
                      ),
                    ],
                  )
                : ListView.separated(
                    itemCount: _items!.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final n = _items![i];
                      return ListTile(
                        tileColor: n.isRead
                            ? null
                            : theme.colorScheme.primary.withValues(alpha: .06),
                        leading: CircleAvatar(
                          backgroundColor: n.isRead
                              ? Colors.grey.withValues(alpha: .2)
                              : theme.colorScheme.primary,
                          child: Icon(
                            n.isRead
                                ? Icons.notifications_none
                                : Icons.notifications_active,
                            color: n.isRead ? Colors.grey : Colors.white,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          n.title,
                          style: TextStyle(
                            fontWeight:
                                n.isRead ? FontWeight.normal : FontWeight.bold,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (n.body.isNotEmpty) Text(n.body),
                            Text(
                              DateFormat(
                                      'd MMM y, h:mm a', s.locale.languageCode)
                                  .format(n.createdAt),
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        ),
                        onTap: n.isRead
                            ? null
                            : () async {
                                await NotificationsRepository.markRead(n.id);
                                await _load();
                              },
                      );
                    },
                  ),
      ),
    );
  }
}
