import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/in_app_player.dart';
import '../../core/l10n.dart';
import 'data/lives_repo.dart';

/// Student: live sessions list (upcoming / past) and session detail with
/// countdown, in-app join and recording playback (screens 43-45).
class LivesScreen extends StatefulWidget {
  const LivesScreen({super.key});

  @override
  State<LivesScreen> createState() => _LivesScreenState();
}

class _LivesScreenState extends State<LivesScreen> {
  List<LiveSession>? _all;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await LivesRepository.fetchAll();
      if (mounted) setState(() => _all = r);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final all = _all;
    final upcoming = all == null
        ? <LiveSession>[]
        : (all.where((l) => l.isUpcoming).toList()
          ..sort((a, b) => a.startsAt.compareTo(b.startsAt)));
    final past = all == null
        ? <LiveSession>[]
        : all.where((l) => !l.isUpcoming).toList();
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(s.t('lv_title')),
          bottom: TabBar(tabs: [
            Tab(text: s.t('lv_upcoming')),
            Tab(text: s.t('lv_past')),
          ]),
        ),
        body: all == null
            ? Center(
                child: _failed
                    ? Text(s.t('generic_error'))
                    : const CircularProgressIndicator())
            : TabBarView(children: [
                _list(s, upcoming),
                _list(s, past),
              ]),
      ),
    );
  }

  Widget _list(S s, List<LiveSession> items) {
    return RefreshIndicator(
      onRefresh: _load,
      child: items.isEmpty
          ? ListView(children: [
              const SizedBox(height: 120),
              Center(child: Text(s.t('no_lives'))),
            ])
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              itemBuilder: (context, i) {
                final l = items[i];
                final fmt = DateFormat('EEE d MMM, h:mm a', s.locale.languageCode);
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: l.status == 'cancelled'
                          ? Colors.grey.shade300
                          : Theme.of(context).colorScheme.primaryContainer,
                      child: Icon(l.recordingUrl != null && !l.isUpcoming
                          ? Icons.play_circle_outline
                          : Icons.videocam_outlined),
                    ),
                    title: Text(l.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                        '${fmt.format(l.startsAt)} · ${l.durationMinutes} ${s.t('minutes_unit')}'
                        '${l.status == 'cancelled' ? ' · ${s.t('status_cancelled')}' : ''}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(
                            builder: (_) => LiveDetailScreen(session: l)))
                        .then((_) => _load()),
                  ),
                );
              },
            ),
    );
  }
}

class LiveDetailScreen extends StatefulWidget {
  const LiveDetailScreen({super.key, required this.session});

  final LiveSession session;

  @override
  State<LiveDetailScreen> createState() => _LiveDetailScreenState();
}

class _LiveDetailScreenState extends State<LiveDetailScreen> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  String _countdown(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final days = d.inDays;
    final h = d.inHours % 24, m = d.inMinutes % 60, sec = d.inSeconds % 60;
    return '${days > 0 ? '$days:' : ''}${two(h)}:${two(m)}:${two(sec)}';
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final l = widget.session;
    final theme = Theme.of(context);
    final fmt = DateFormat('EEEE d MMMM yyyy, h:mm a', s.locale.languageCode);
    final untilStart = l.startsAt.difference(DateTime.now());
    final cancelled = l.status == 'cancelled';
    final ended = DateTime.now().isAfter(l.endsAt);
    return Scaffold(
      appBar: AppBar(title: Text(l.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                Text(
                  cancelled
                      ? s.t('status_cancelled')
                      : ended
                          ? s.t('lv_ended')
                          : l.canJoinNow
                              ? s.t('lv_live_now')
                              : s.t('lv_starts_in'),
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 8),
                if (!cancelled && !ended && !l.canJoinNow)
                  Text(
                    _countdown(untilStart.isNegative ? Duration.zero : untilStart),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.bold),
                  )
                else
                  const Icon(Icons.videocam, color: Colors.white, size: 40),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.event),
            title: Text(fmt.format(l.startsAt)),
            subtitle: Text('${l.durationMinutes} ${s.t('minutes_unit')} · ${DateTime.now().timeZoneName}'),
          ),
          if (l.hostName != null && l.hostName!.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(l.hostName!),
              subtitle: Text(s.t('lv_host')),
            ),
          if (l.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(l.description),
            ),
          const SizedBox(height: 12),
          if (!cancelled && !ended)
            FilledButton.icon(
              onPressed: l.canJoinNow
                  ? () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) =>
                          InAppPlayerScreen(url: l.joinUrl, title: l.title)))
                  : null,
              icon: const Icon(Icons.play_arrow),
              label: Text(s.t('join_live')),
            ),
          if (l.recordingUrl != null && l.recordingUrl!.isNotEmpty) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => InAppPlayerScreen(
                      url: l.recordingUrl!, title: l.title))),
              icon: const Icon(Icons.play_circle_outline),
              label: Text(s.t('lv_watch')),
            ),
          ] else if (ended && !cancelled)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(s.t('lv_no_recording'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall),
            ),
        ],
      ),
    );
  }
}
