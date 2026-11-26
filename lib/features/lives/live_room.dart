import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/in_app_player.dart';
import '../../core/l10n.dart';
import 'data/lives_repo.dart';

/// Live class: video on top, live chat below (Supabase Realtime).
class LiveRoomScreen extends StatefulWidget {
  const LiveRoomScreen({super.key, required this.session});

  final LiveSession session;

  @override
  State<LiveRoomScreen> createState() => _LiveRoomScreenState();
}

class _LiveRoomScreenState extends State<LiveRoomScreen> {
  final _msg = TextEditingController();
  final _scroll = ScrollController();
  StreamSubscription<List<Map<String, dynamic>>>? _sub;
  List<Map<String, dynamic>> _items = [];
  bool _chatOff = false;
  int _count = 0;

  SupabaseClient get _c => Supabase.instance.client;

  String get _url {
    final u = widget.session.joinUrl.trim();
    if (widget.session.platform == 'jitsi' && !u.startsWith('http')) {
      return 'https://meet.jit.si/$u';
    }
    return u;
  }

  @override
  void initState() {
    super.initState();
    LivesRepository.counts([widget.session.id]).then((m) {
      if (mounted) setState(() => _count = m[widget.session.id] ?? 0);
    });
    try {
      _sub = _c
          .from('live_chat')
          .stream(primaryKey: ['id'])
          .eq('live_id', widget.session.id)
          .order('created_at')
          .listen((rows) {
        if (!mounted) return;
        setState(() => _items = rows);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) {
            _scroll.jumpTo(_scroll.position.maxScrollExtent);
          }
        });
      }, onError: (_) {
        if (mounted) setState(() => _chatOff = true);
      });
    } catch (_) {
      _chatOff = true;
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _msg.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _msg.text.trim();
    final uid = _c.auth.currentUser?.id;
    if (text.isEmpty || uid == null) return;
    _msg.clear();
    try {
      await _c.from('live_chat').insert(
          {'live_id': widget.session.id, 'user_id': uid, 'body': text});
    } catch (_) {
      if (mounted) setState(() => _chatOff = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.session.title,
              maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: SafeArea(
        child: Column(children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(children: [
              Positioned.fill(child: InAppWebPlayer(url: _url)),
              PositionedDirectional(
                end: 8,
                bottom: 8,
                child: GestureDetector(
                  onTap: () => Navigator.of(context).maybePop(),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                        color: Color(0xFFE53935), shape: BoxShape.circle),
                    child: const Icon(Icons.call_end, color: Colors.white),
                  ),
                ),
              ),
              PositionedDirectional(
                start: 8,
                top: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(10)),
                  child: Text('$_count ${s.t('lv_online')}',
                      style:
                          const TextStyle(color: Colors.white, fontSize: 11)),
                ),
              ),
            ]),
          ),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: _chatOff
                  ? Center(child: Text(s.t('lv_chat_off')))
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(14),
                      itemCount: _items.length,
                      itemBuilder: (_, i) {
                        final m = _items[i];
                        final host = m['is_host'] == true;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                    color: host
                                        ? const Color(0xFFE9B98A)
                                        : scheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(4)),
                                child: Text(
                                    host ? s.t('lv_teacher') : '',
                                    style: const TextStyle(fontSize: 9)),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text.rich(TextSpan(children: [
                                  TextSpan(
                                      text: '${m['sender_name'] ?? ''}: ',
                                      style: TextStyle(
                                          color: host
                                              ? const Color(0xFFC98A52)
                                              : scheme.onSurfaceVariant,
                                          fontSize: 12)),
                                  TextSpan(
                                      text: '${m['body'] ?? ''}',
                                      style: const TextStyle(fontSize: 13)),
                                ])),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _msg,
                  enabled: !_chatOff,
                  maxLength: 500,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: s.t('lv_chat_hint'),
                    isDense: true,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20)),
                  ),
                ),
              ),
              IconButton(
                  onPressed: _chatOff ? null : _send,
                  icon: Icon(Icons.send_rounded, color: scheme.primary)),
            ]),
          ),
        ]),
      ),
    );
  }
}
