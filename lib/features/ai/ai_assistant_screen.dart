import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/l10n.dart';

/// One chat message. Kept in memory so the conversation survives closing and
/// reopening the floating assistant during a session.
class AiMsg {
  AiMsg(this.role, this.text);
  final String role; // user | assistant
  final String text;
}

final List<AiMsg> _history = [];

/// Full-screen version (side menu entry). Same panel as the floating sheet.
class AiAssistantScreen extends StatelessWidget {
  const AiAssistantScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('ai_title'))),
      body: const AiChatPanel(),
    );
  }
}

/// Bottom-sheet wrapper used by the floating button.
class AiChatSheet extends StatelessWidget {
  const AiChatSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final h = MediaQuery.of(context).size.height;
    return Container(
      height: h * .86,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
                colors: [Color(0xFF2563EB), Color(0xFF7C3AED)]),
          ),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.auto_awesome, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.t('ai_title'),
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 17)),
                  Text(s.t('ai_sub'),
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
            ),
          ]),
        ),
        const Expanded(child: AiChatPanel()),
      ]),
    );
  }
}

class AiChatPanel extends StatefulWidget {
  const AiChatPanel({super.key});

  @override
  State<AiChatPanel> createState() => _AiChatPanelState();
}

class _AiChatPanelState extends State<AiChatPanel> {
  final _c = TextEditingController();
  final _scroll = ScrollController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _toEnd());
  }

  void _toEnd() {
    if (_scroll.hasClients) {
      _scroll.animateTo(_scroll.position.maxScrollExtent + 300,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  Future<void> _send([String? preset]) async {
    final s = S.of(context);
    final q = (preset ?? _c.text).trim();
    if (q.isEmpty || _busy) return;
    final lang = Localizations.localeOf(context).languageCode;
    setState(() {
      _history.add(AiMsg('user', q));
      _busy = true;
      _c.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _toEnd());
    String reply;
    try {
      final user = Supabase.instance.client.auth.currentUser;
      final res = await Supabase.instance.client.functions.invoke(
        'ai-assistant',
        body: {
          'lang': lang,
          'name': user?.userMetadata?['full_name'],
          'messages': [for (final m in _history) {'role': m.role, 'text': m.text}],
        },
      ).timeout(const Duration(seconds: 45));
      final data = res.data;
      if (data is Map && (data['text'] ?? '').toString().isNotEmpty) {
        reply = data['text'].toString();
      } else if (data is Map && data['error'] == 'no_key') {
        reply = 'مفتاح Gemini (GEMINI_API_KEY) مش متسجل في Supabase Secrets، أو اتسجل بعد نشر الدالة. احفظه تاني وأعد نشر الدالة (Deploy).';
      } else if (data is Map && data['error'] == 'gemini') {
        reply = 'المفتاح موجود لكن Gemini رفض الطلب: ${data['detail']}';
      } else if (data is Map && data['error'] != null) {
        reply = 'خطأ في الدالة: ${data['error']}';
      } else {
        reply = s.t('ai_not_ready');
      }
    } on FunctionException catch (e) {
      reply = e.status == 404
          ? 'الدالة ai-assistant مش موجودة في Supabase. اتأكد إن اسمها بالظبط ai-assistant وإنها اتعملها Deploy.'
          : 'الدالة رجّعت خطأ (${e.status}): ${e.details ?? ''}';
    } catch (e) {
      reply = 'تعذر الوصول للمساعد: $e';
    }
    if (!mounted) return;
    setState(() {
      _history.add(AiMsg('assistant', reply));
      _busy = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _toEnd());
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final chips = [
      s.t('ai_chip1'),
      s.t('ai_chip2'),
      s.t('ai_chip3'),
      s.t('ai_chip4'),
    ];
    return Material(
      color: const Color(0xFFF5F8FF),
      child: Column(children: [
        Expanded(
          child: _history.isEmpty
              ? ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    const SizedBox(height: 16),
                    Center(
                      child: Container(
                        width: 84,
                        height: 84,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(colors: [
                            Color(0xFF2563EB),
                            Color(0xFF7C3AED)
                          ]),
                        ),
                        child: const Icon(Icons.auto_awesome,
                            color: Colors.white, size: 42),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(s.t('ai_intro'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: Theme.of(context).colorScheme.onSurface)),
                    const SizedBox(height: 18),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final c in chips)
                          ActionChip(
                            label: Text(c),
                            backgroundColor: Colors.white,
                            side: const BorderSide(color: Color(0xFFD5E0F7)),
                            onPressed: () => _send(c),
                          ),
                      ],
                    ),
                  ],
                )
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(16),
                  itemCount: _history.length + (_busy ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (i == _history.length) return const _Typing();
                    final m = _history[i];
                    final mine = m.role == 'user';
                    return Align(
                      alignment: mine
                          ? AlignmentDirectional.centerEnd
                          : AlignmentDirectional.centerStart,
                      child: GestureDetector(
                        onLongPress: () {
                          Clipboard.setData(ClipboardData(text: m.text));
                          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                              SnackBar(content: Text(s.t('ai_copied'))));
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          constraints: BoxConstraints(
                              maxWidth:
                                  MediaQuery.of(context).size.width * .8),
                          decoration: BoxDecoration(
                            gradient: mine
                                ? const LinearGradient(colors: [
                                    Color(0xFF2563EB),
                                    Color(0xFF4F46E5)
                                  ])
                                : null,
                            color: mine ? null : Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: const [
                              BoxShadow(
                                  color: Color(0x142563EB),
                                  blurRadius: 10,
                                  offset: Offset(0, 4)),
                            ],
                          ),
                          child: SelectableText(m.text,
                              style: TextStyle(
                                  height: 1.45,
                                  color: mine
                                      ? Colors.white
                                      : Theme.of(context).colorScheme.onSurface)),
                        ),
                      ),
                    );
                  },
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                12, 6, 12, 8 + MediaQuery.of(context).viewInsets.bottom),
            child: Row(children: [
              if (_history.isNotEmpty)
                IconButton(
                  tooltip: s.t('ai_clear'),
                  onPressed: () => setState(_history.clear),
                  icon: const Icon(Icons.delete_sweep_outlined),
                ),
              Expanded(
                child: TextField(
                  controller: _c,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(
                    hintText: s.t('ai_hint'),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                      colors: [Color(0xFF2563EB), Color(0xFF7C3AED)]),
                ),
                child: IconButton(
                  onPressed: _busy ? null : _send,
                  icon: const Icon(Icons.send_rounded, color: Colors.white),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _Typing extends StatefulWidget {
  const _Typing();

  @override
  State<_Typing> createState() => _TypingState();
}

class _TypingState extends State<_Typing> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat();

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: AnimatedBuilder(
          animation: _a,
          builder: (_, __) => Row(mainAxisSize: MainAxisSize.min, children: [
            for (var i = 0; i < 3; i++)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 2.5),
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF2563EB).withValues(
                      alpha: .25 +
                          .75 *
                              (((_a.value * 3 - i) % 3).clamp(0.0, 1.0) < .5
                                  ? 1
                                  : 0)),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
