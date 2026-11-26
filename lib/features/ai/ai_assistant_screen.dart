import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/l10n.dart';

/// Study assistant chat. Calls the free `ai-assistant` edge function; shows a
/// clear message when it is not deployed or has no key yet.
class AiAssistantScreen extends StatefulWidget {
  const AiAssistantScreen({super.key});

  @override
  State<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends State<AiAssistantScreen> {
  final _c = TextEditingController();
  final _scroll = ScrollController();
  final List<({String role, String text})> _msgs = [];
  bool _busy = false;

  Future<void> _send() async {
    final s = S.of(context);
    final q = _c.text.trim();
    if (q.isEmpty || _busy) return;
    final lang = Localizations.localeOf(context).languageCode;
    setState(() {
      _msgs.add((role: 'user', text: q));
      _busy = true;
      _c.clear();
    });
    String reply;
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'ai-assistant',
        body: {
          'lang': lang,
          'messages': [for (final m in _msgs) {'role': m.role, 'text': m.text}],
        },
      ).timeout(const Duration(seconds: 40));
      final data = res.data;
      if (data is Map && (data['text'] ?? '').toString().isNotEmpty) {
        reply = data['text'].toString();
      } else {
        reply = s.t('ai_not_ready');
      }
    } catch (_) {
      reply = s.t('ai_not_ready');
    }
    if (!mounted) return;
    setState(() {
      _msgs.add((role: 'assistant', text: reply));
      _busy = false;
    });
    await Future.delayed(const Duration(milliseconds: 100));
    if (_scroll.hasClients) {
      _scroll.animateTo(_scroll.position.maxScrollExtent + 200,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('ai_title'))),
      body: Column(children: [
        Expanded(
          child: _msgs.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.auto_awesome,
                          size: 56, color: Color(0xFF2563EB)),
                      const SizedBox(height: 10),
                      Text(s.t('ai_intro'), textAlign: TextAlign.center),
                    ]),
                  ),
                )
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(16),
                  itemCount: _msgs.length,
                  itemBuilder: (_, i) {
                    final m = _msgs[i];
                    final mine = m.role == 'user';
                    return Align(
                      alignment: mine
                          ? AlignmentDirectional.centerEnd
                          : AlignmentDirectional.centerStart,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * .78),
                        decoration: BoxDecoration(
                          color: mine
                              ? const Color(0xFF2563EB)
                              : const Color(0xFFEFF3FB),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: SelectableText(m.text,
                            style: TextStyle(
                                color: mine ? Colors.white : Colors.black87)),
                      ),
                    );
                  },
                ),
        ),
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _c,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(hintText: s.t('ai_hint')),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _busy ? null : _send,
                icon: const Icon(Icons.send_rounded),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
