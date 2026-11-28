import '../ai/ai_fab.dart';
import '../../core/in_app_player.dart';
import 'lesson_files.dart';
import 'lesson_exam_card.dart';
import 'lesson_assignment_card.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../admin/data/admin_repo.dart';
import 'package:url_launcher/url_launcher.dart';
import 'lesson_links.dart';

import '../../core/storage_urls.dart';
import 'package:video_player/video_player.dart';

import '../../core/l10n.dart';
import '../../core/remote_ui.dart';
import 'data/course_models.dart';
import 'data/courses_repo.dart';

/// One lesson. Video resumes from the saved position and reports progress
/// back to the server; other types open their content and mark complete.
class LessonScreen extends StatefulWidget {
  const LessonScreen({super.key, required this.lesson});

  final Lesson lesson;

  @override
  State<LessonScreen> createState() => _LessonScreenState();
}

class _LessonScreenState extends State<LessonScreen> with WidgetsBindingObserver {
  bool _completed = false;
  bool _saving = false;
  final Set<int> _seen = {};
  int _dur = 0;
  int _sinceSave = 0;
  Timer? _fallback;
  bool _noTracking = false;

  int get _pct => RemoteUi.limit('lesson_watch_percent', 90).round().clamp(1, 100);
  int get _required => (_dur * _pct / 100).ceil();
  bool get _isVideo => lesson.type == 'video';
  // Seconds inside the duration the SERVER uses (so the tick, the label and the lock agree).
  int get _have => _dur <= 0 ? 0 : _seen.where((x) => x < _dur).length;
  Future<String>? _urlFuture;
  bool _srvDur = false;
  bool _flushing = false;
  bool get _canComplete =>
      !_isVideo || (_dur > 0 && _have >= _required);
  int get _shownPct => _dur <= 0 ? 0 : (_have * 100 ~/ _dur).clamp(0, 100);

  // Real watch time: only seconds actually played count. Skipping ahead does
  // not credit the skipped part; pauses and replays add nothing. Progress is
  // sent to the server every 10 s (and kept there), so closing the app keeps it.
  int? _lastPos;
  DateTime? _lastAt;
  final Set<int> _pending = {};
  Timer? _flushTimer;
  bool _serverTracking = true;
  bool _admin = false;

  void _onTick(int pos, int dur) {
    if (dur > 0 && !_srvDur) _dur = dur;
    if (pos == _lastPos) return;
    final now = DateTime.now();
    var added = false;
    final lp = _lastPos;
    final la = _lastAt;
    if (lp != null && la != null) {
      final gapMs = now.difference(la).inMilliseconds;
      final step = pos - lp;
      // Played continuously: position moved forward no faster than 2.5x real time.
      if (step > 0 && gapMs > 0 && gapMs < 4000 && step <= (gapMs / 1000 * 2.5).ceil() + 1) {
        for (var p = lp + 1; p <= pos; p++) {
          if (_seen.add(p)) {
            _pending.add(p);
            added = true;
          }
        }
      }
    }
    if (_seen.add(pos)) {
      _pending.add(pos);
      added = true;
    }
    _lastPos = pos;
    _lastAt = now;
    if (added && mounted) {
      _sinceSave++;
      if (_sinceSave >= 5) {
        _sinceSave = 0;
        CoursesRepository.saveProgress(lesson.id, positionSeconds: pos).catchError((_) {});
      }
      setState(() {});
    }
  }

  String _rangesText(Iterable<int> secs) {
    final l = secs.toList()..sort();
    final parts = <String>[];
    var i = 0;
    while (i < l.length) {
      var j = i;
      while (j + 1 < l.length && l[j + 1] == l[j] + 1) {
        j++;
      }
      parts.add('[${l[i]},${l[j] + 1})');
      i = j + 1;
    }
    return '{${parts.join(',')}}';
  }

  /// Sends the newly watched seconds; the server decides completion.
  Future<void> _flushWatch() async {
    if (!_isVideo || !_serverTracking || _pending.isEmpty || _admin || _flushing) return;
    _flushing = true;
    try {
      // Small chunks (max 12 s each) so the server's anti-cheat speed check never rejects honest time.
      for (var i = 0; i < 40 && _pending.isNotEmpty; i++) {
        final l = _pending.toList()..sort();
        final sent = l.take(12).toSet();
        final r = await Supabase.instance.client.rpc('record_watch', params: {
          'p_lesson': lesson.id,
          'p_ranges': _rangesText(sent),
          'p_duration': _dur,
        });
        _pending.removeAll(sent);
        if (r is Map) {
          final d = (r['duration'] as num?)?.toInt() ?? 0;
          if (d > 0 && d != _dur) {
            _dur = d;
            _srvDur = true;
            if (mounted) setState(() {});
          } else if (d > 0) {
            _srvDur = true;
          }
          if (r['done'] == true && !_completed && mounted) {
            setState(() => _completed = true);
          }
        }
      }
    } catch (e) {
      final m = '$e';
      if (m.contains('record_watch') && (m.contains('PGRST202') || m.contains('Could not find'))) {
        _serverTracking = false; // SQL part40 not run yet: old client-side rule
      }
    } finally {
      _flushing = false;
    }
  }

  Future<void> _restoreWatch() async {
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null || !_isVideo) return;
      final r = await Supabase.instance.client
          .from('lesson_watch')
          .select('seen,duration')
          .eq('lesson_id', lesson.id)
          .eq('user_id', uid)
          .maybeSingle();
      if (r == null || !mounted) return;
      for (final m in RegExp(r'\[(\d+),(\d+)\)').allMatches('${r['seen']}')) {
        final a = int.parse(m.group(1)!);
        final b = int.parse(m.group(2)!);
        for (var x = a; x < b && x < 100000; x++) {
          _seen.add(x);
        }
      }
      final d = (r['duration'] as num?)?.toInt() ?? 0;
      if (d > 0) {
        _dur = d;
        _srvDur = true;
      }
      setState(() {});
    } catch (_) {}
  }

  /// Players that cannot report play time: count seconds on screen against
  /// the lesson duration (or 2 minutes when none is set).
  void _startFallback() {
    if (_noTracking || !_isVideo) return;
    _noTracking = true;
    _dur = (lesson.durationSeconds ?? 0) > 0 ? lesson.durationSeconds! : 120;
    var n = 0;
    _fallback = Timer.periodic(const Duration(seconds: 1), (_) => _onTick(n++, _dur));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _flushWatch();
  }

  Lesson get lesson => widget.lesson;

  bool get _locked => _isVideo && !_completed && !_admin;
  String get _lockedText =>
      'بيفتح بعد ما تخلّص الفيديو (مشاهدة فعلية $_pct%). وصلت: $_shownPct%.';

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _fallback?.cancel();
    _flushTimer?.cancel();
    _flushWatch();
    WidgetsBinding.instance.addPostFrameCallback((_) => aiFabHidden.value--);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _completed = lesson.completed;
    AdminRepository.isAdmin().then((v) {
      if (mounted) setState(() => _admin = v);
    }).catchError((_) {});
    _restoreWatch();
    _flushTimer = Timer.periodic(const Duration(seconds: 10), (_) => _flushWatch());
    WidgetsBinding.instance.addPostFrameCallback((_) => aiFabHidden.value++);
    _touchProgress();
  }

  /// Record that the student opened this lesson (drives "continue learning").
  void _touchProgress() {
    CoursesRepository.saveProgress(
      lesson.id,
      positionSeconds: lesson.positionSeconds,
    ).catchError((_) {});
  }

  Future<void> _markComplete() async {
    setState(() => _saving = true);
    try {
      await _flushWatch();
      if (_completed) return;
      await CoursesRepository.saveProgress(lesson.id,
          completed: true, watchedSeconds: _isVideo ? _seen.length : null);
      if (!mounted) return;
      setState(() => _completed = true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(_isVideo
                ? '${S.of(context).t('watch_required')} $_pct%'
                : S.of(context).t('generic_error'))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openExternal(String url) async {
    final resolved = await resolveStorageUrl(url);
    if (!mounted) return;
    // Everything opens inside the app (PDF/docs through the viewer page).
    var target = resolved;
    final low = resolved.toLowerCase();
    if (low.contains('.pdf') || low.contains('.doc') || low.contains('.ppt')) {
      target = 'https://docs.google.com/gview?embedded=1&url=${Uri.encodeComponent(resolved)}';
    }
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => InAppPlayerScreen(url: target, title: lesson.title)));
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(lesson.title,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
          child: _completed
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle,
                        color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(s.t('completed'),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ],
                )
              : SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed:
                        (_saving || !_canComplete) ? null : _markComplete,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check),
                    label: Text(_canComplete
                        ? s.t('mark_complete')
                        : '${s.t('watch_required')} $_pct% ($_shownPct%)'),
                  ),
                ),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          _buildBody(s),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(lesson.title,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800)),
                if (lesson.content.isNotEmpty && lesson.type != 'text') ...[
                  const SizedBox(height: 12),
                  LessonDescription(text: lesson.content),
                ],
                const SizedBox(height: 16),
                LessonFiles(lessonId: lesson.id),
                LessonExamCard(lessonId: lesson.id, locked: _locked, lockedText: _lockedText),
                LessonAssignmentCard(lessonId: lesson.id, locked: _locked, lockedText: _lockedText),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(S s) {
    switch (lesson.type) {
      case 'video':
        final url = lesson.mediaUrl;
        if (url == null || url.isEmpty) return Padding(padding: const EdgeInsets.all(16), child: Text(s.t('no_content')));
        _urlFuture ??= resolveStorageUrl(url);
        return FutureBuilder<String>(
          future: _urlFuture,
          builder: (context, snap) {
            final resolved = snap.data;
            if (resolved == null) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!isDirectVideoUrl(resolved)) {
              return AspectRatio(
                aspectRatio: 16 / 9,
                child: ClipRRect(
                  borderRadius: BorderRadius.zero,
                  child: InAppWebPlayer(
                      url: resolved,
                      onTick: _onTick,
                      onNoTracking: _startFallback),
                ),
              );
            }
            return _VideoLesson(
              key: ValueKey(lesson.id),
              url: resolved,
              startAtSeconds: lesson.positionSeconds,
              onTick: _onTick,
              onProgress: (seconds, done) {
                CoursesRepository.saveProgress(
                  lesson.id,
                  positionSeconds: seconds,
                ).catchError((_) {});
              },
            );
          },
        );
      case 'text':
        return Padding(
            padding: const EdgeInsets.fromLTRB(4, 16, 4, 0),
            child: Text(lesson.content.trim().isEmpty ? s.t('no_content') : lesson.content));
      case 'pdf':
      case 'document':
      case 'presentation':
      case 'audio':
      case 'link':
        final url = lesson.mediaUrl;
        if (url == null || url.isEmpty) return Padding(padding: const EdgeInsets.all(16), child: Text(s.t('no_content')));
        return Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 0),
          child: SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _openExternal(url),
            icon: const Icon(Icons.open_in_new),
            label: Text(s.t(lesson.type == 'link' ? 'open_link' : 'open_file')),
          ),
        ));
      default:
        // live, quiz, assignment: their stages come later.
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(s.t('lesson_type_coming')),
          ),
        );
    }
  }
}

class _VideoLesson extends StatefulWidget {
  const _VideoLesson({
    super.key,
    required this.url,
    required this.startAtSeconds,
    required this.onProgress,
    required this.onTick,
  });

  final String url;
  final int startAtSeconds;
  final void Function(int seconds, bool done) onProgress;
  final void Function(int position, int duration) onTick;

  @override
  State<_VideoLesson> createState() => _VideoLessonState();
}

class _VideoLessonState extends State<_VideoLesson> {
  late final VideoPlayerController _controller;
  bool _ready = false;
  bool _failed = false;
  Timer? _saveTimer;
  bool _reportedDone = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _init();
  }

  Future<void> _init() async {
    try {
      await _controller.initialize();
      if (widget.startAtSeconds > 0) {
        await _controller.seekTo(Duration(seconds: widget.startAtSeconds));
      }
      if (!mounted) return;
      setState(() => _ready = true);
      _controller.addListener(_onTick);
      _saveTimer = Timer.periodic(const Duration(seconds: 5), (_) => _save());
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  void _onTick() {
    if (!mounted) return;
    setState(() {});
    final value = _controller.value;
    final total = value.duration.inSeconds;
    if (value.isPlaying && total > 0) {
      widget.onTick(value.position.inSeconds, total);
    }
  }

  void _save() {
    if (!_ready) return;
    widget.onProgress(_controller.value.position.inSeconds, false);
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _save();
    _controller.removeListener(_onTick);
    _controller.dispose();
    super.dispose();
  }

  String _format(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hours = d.inHours;
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return Text(S.of(context).t('generic_error'));
    }
    if (!_ready) {
      return const AspectRatio(
        aspectRatio: 16 / 9,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final value = _controller.value;
    return Column(
      children: [
        AspectRatio(
          aspectRatio: _controller.value.aspectRatio,
          child: VideoPlayer(_controller),
        ),
        VideoProgressIndicator(_controller, allowScrubbing: true),
        Row(
          children: [
            IconButton(
              icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
              onPressed: () {
                setState(() {
                  value.isPlaying ? _controller.pause() : _controller.play();
                });
              },
            ),
            Text('${_format(value.position)} / ${_format(value.duration)}'),
          ],
        ),
      ],
    );
  }
}
