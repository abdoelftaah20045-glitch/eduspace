import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/l10n.dart';
import 'data/notifications_repo.dart';

/// In-app notifications: search, All/Unread filter, mark-all-read, grouped
/// by Today / Yesterday / date (per the user's design reference).
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _search = TextEditingController();
  List<AppNotification>? _items;
  bool _unreadOnly = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final items = await NotificationsRepository.fetchMine();
      if (mounted) setState(() => _items = items);
    } catch (_) {
      if (mounted) setState(() => _items = const []);
    }
  }

  List<AppNotification> get _filtered {
    final items = _items ?? const <AppNotification>[];
    final q = _search.text.trim();
    return items.where((n) {
      if (_unreadOnly && n.isRead) return false;
      if (q.isNotEmpty && !n.title.contains(q) && !n.body.contains(q)) {
        return false;
      }
      return true;
    }).toList();
  }

  (Color, IconData) _styleFor(String type) => switch (type) {
        'exam' => (const Color(0xFF7C4DFF), Icons.quiz_outlined),
        'assignment' => (const Color(0xFFFF9800), Icons.assignment_outlined),
        'certificate' => (const Color(0xFFC9A227), Icons.workspace_premium),
        'course' => (const Color(0xFF26A69A), Icons.menu_book_outlined),
        'live' => (const Color(0xFFEF5350), Icons.video_camera_front_outlined),
        _ => (const Color(0xFF42A5F5), Icons.notifications_outlined),
      };

  /// Builds rows with Today / Yesterday / date group headers.
  List<Widget> _grouped(S s, ThemeData theme) {
    final items = _filtered;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final rows = <Widget>[];
    String? lastHeader;
    for (final n in items) {
      final day = DateTime(n.createdAt.year, n.createdAt.month, n.createdAt.day);
      final header = day == today
          ? s.t('today')
          : day == yesterday
              ? s.t('yesterday')
              : DateFormat('EEEE, d MMMM y', s.locale.languageCode)
                  .format(n.createdAt);
      if (header != lastHeader) {
        lastHeader = header;
        rows.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(header,
              style: theme.textTheme.labelLarge
                  ?.copyWith(color: theme.colorScheme.primary)),
        ));
      }
      rows.add(_tile(n, s, theme));
    }
    return rows;
  }

  Widget _tile(AppNotification n, S s, ThemeData theme) {
    final (color, icon) = _styleFor(n.type);
    return Material(
      color: n.isRead
          ? null
          : theme.colorScheme.primary.withValues(alpha: .05),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor:
              n.isRead ? Colors.grey.withValues(alpha: .18) : color.withValues(alpha: .16),
          child: Icon(icon,
              color: n.isRead ? Colors.grey : color, size: 20),
        ),
        title: Text(
          n.title,
          style: TextStyle(
              fontWeight: n.isRead ? FontWeight.normal : FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (n.body.isNotEmpty)
              Text(n.body, maxLines: 2, overflow: TextOverflow.ellipsis),
            Text(
              DateFormat('h:mm a', s.locale.languageCode).format(n.createdAt),
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        trailing: n.isRead
            ? null
            : Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    shape: BoxShape.circle),
              ),
        onTap: n.isRead
            ? null
            : () async {
                await NotificationsRepository.markRead(n.id);
                await _load();
              },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final hasUnread = (_items ?? []).any((n) => !n.isRead);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('notifications')),
        actions: [
          if (hasUnread)
            TextButton(
              onPressed: () async {
                await NotificationsRepository.markAllRead();
                await _load();
              },
              child: Text(s.t('mark_all_read')),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(104),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: s.t('search_label'),
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    ChoiceChip(
                      label: Text(s.t('filter_all')),
                      selected: !_unreadOnly,
                      onSelected: (_) =>
                          setState(() => _unreadOnly = false),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: Text(s.t('unread_label')),
                      selected: _unreadOnly,
                      onSelected: (_) => setState(() => _unreadOnly = true),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _items == null
            ? const Center(child: CircularProgressIndicator())
            : _filtered.isEmpty
                ? ListView(
                    children: [
                      const SizedBox(height: 100),
                      const Icon(Icons.notifications_none,
                          size: 56, color: Colors.grey),
                      const SizedBox(height: 12),
                      Center(
                        child: Text(s.t('no_notifications'),
                            style: const TextStyle(color: Colors.grey)),
                      ),
                    ],
                  )
                : ListView(children: _grouped(s, theme)),
      ),
    );
  }
}
