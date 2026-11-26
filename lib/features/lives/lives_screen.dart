import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/pressable.dart';
import 'package:intl/intl.dart';

import '../../core/in_app_player.dart';
import '../../core/l10n.dart';
import 'data/lives_repo.dart';
import 'live_room.dart';

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
  Map<String, int> _counts = {};
  Set<String> _mine = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await LivesRepository.fetchAll();
      if (mounted) setState(() => _all = r);
      final c = await LivesRepository.counts([for (final l in r) l.id]);
      final mine = await LivesRepository.myReservations();
      if (mounted) setState(() {
        _counts = c;
        _mine = mine;
      });
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
                final scheme = Theme.of(context).colorScheme;
                final lang = s.locale.languageCode;
                final day = DateFormat('d MMMM', lang).format(l.startsAt);
                final showHeader = i == 0 ||
                    DateFormat('yMd').format(items[i - 1].startsAt) !=
                        DateFormat('yMd').format(l.startsAt);
                final n = _counts[l.id] ?? 0;
                final reserved = _mine.contains(l.id);
                final cancelled = l.status == 'cancelled';
                final canEnter = l.canJoinNow;
                final time =
                    '${DateFormat('h:mm a', lang).format(l.startsAt)} - ${DateFormat('h:mm a', lang).format(l.endsAt)}';
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showHeader)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
                        child: Text(day,
                            style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600)),
                      ),
                    PressScale(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => Navigator.of(context)
                            .push(MaterialPageRoute(
                                builder: (_) => LiveDetailScreen(session: l)))
                            .then((_) => _load()),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: scheme.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: scheme.outlineVariant),
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.black.withValues(alpha: .06),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4)),
                            ],
                          ),
                          child: Row(children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: SizedBox(
                                width: 64,
                                height: 72,
                                child: (l.hostPhotoUrl ?? '').isNotEmpty
                                    ? Image.network(l.hostPhotoUrl!,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Container(
                                            color: scheme.primaryContainer,
                                            child: const Icon(Icons.person)))
                                    : Container(
                                        color: scheme.primaryContainer,
                                        child: Icon(
                                            l.recordingUrl != null &&
                                                    !l.isUpcoming
                                                ? Icons.play_circle_outline
                                                : Icons.person,
                                            size: 32)),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(l.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 4),
                                  Text(
                                      '$time  |  $n ${s.t('lv_attendees')}'
                                      '${cancelled ? '  |  ${s.t('status_cancelled')}' : ''}',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: scheme.onSurfaceVariant)),
                                ],
                              ),
                            ),
                            if (l.isUpcoming && !cancelled)
                              FilledButton(
                                style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFFE0A877),
                                    foregroundColor: Colors.white,
                                    minimumSize: const Size(64, 32),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14)),
                                onPressed: canEnter
                                    ? () {
                                        LivesRepository.reserve(l.id)
                                            .catchError((_) {});
                                        Navigator.of(context).push(
                                            MaterialPageRoute(
                                                builder: (_) =>
                                                    LiveRoomScreen(session: l)));
                                      }
                                    : reserved
                                        ? null
                                        : () async {
                                            try {
                                              await LivesRepository.reserve(l.id);
                                            } catch (_) {}
                                            _load();
                                          },
                                child: Text(canEnter
                                    ? s.t('lv_enter')
                                    : reserved
                                        ? s.t('lv_reserved')
                                        : s.t('lv_reserve')),
                              ),
                          ]),
                        ),
                      ),
                    ),
                  ],
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
                  ? () {
                      final uid = Supabase.instance.client.auth.currentUser?.id;
                      if (uid != null) {
                        Supabase.instance.client
                            .from('live_attendance')
                            .upsert({'live_id': l.id, 'user_id': uid},
                                onConflict: 'live_id,user_id')
                            .then((_) {}, onError: (_) {});
                      }
                      Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => LiveRoomScreen(session: l)));
                    }
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
