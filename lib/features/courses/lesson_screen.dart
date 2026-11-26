import '../ai/ai_fab.dart';
import '../../core/in_app_player.dart';
import 'lesson_files.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

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

class _LessonScreenState extends State<LessonScreen> {
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
  bool get _canComplete =>
      !_isVideo || (_dur > 0 && _seen.length >= _required);
  int get _shownPct => _dur <= 0 ? 0 : (_seen.length * 100 ~/ _dur).clamp(0, 100);

  void _onTick(int pos, int dur) {
    if (dur > 0) _dur = dur;
    if (_seen.add(pos) && mounted) {
      _sinceSave++;
      if (_sinceSave >= 5) {
        _sinceSave = 0;
        CoursesRepository.saveProgress(lesson.id,
                positionSeconds: pos, watchedSeconds: _seen.length)
            .catchError((_) {});
      }
      setState(() {});
    }
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

  Lesson get lesson => widget.lesson;

  @override
  void dispose() {
    _fallback?.cancel();
    WidgetsBinding.instance.addPostFrameCallback((_) => aiFabHidden.value--);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _completed = lesson.completed;
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
      appBar: AppBar(title: Text(lesson.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildBody(s),
          if (lesson.content.isNotEmpty && lesson.type != 'text') ...[
            const SizedBox(height: 16),
            Text(lesson.content),
          ],
          const SizedBox(height: 16),
          LessonFiles(lessonId: lesson.id),
          const SizedBox(height: 24),
          if (!_completed)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: (_saving || !_canComplete) ? null : _markComplete,
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
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(s.t('completed')),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildBody(S s) {
    switch (lesson.type) {
      case 'video':
        final url = lesson.mediaUrl;
        if (url == null || url.isEmpty) return Text(s.t('no_content'));
        return FutureBuilder<String>(
          future: resolveStorageUrl(url),
          builder: (context, snap) {
            final resolved = snap.data;
            if (resolved == null) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!isDirectVideoUrl(resolved)) {
              return AspectRatio(
                aspectRatio: 16 / 9,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
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
        return Text(lesson.content);
      case 'pdf':
      case 'document':
      case 'presentation':
      case 'audio':
      case 'link':
        final url = lesson.mediaUrl;
        if (url == null || url.isEmpty) return Text(s.t('no_content'));
        return SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _openExternal(url),
            icon: const Icon(Icons.open_in_new),
            label: Text(s.t(lesson.type == 'link' ? 'open_link' : 'open_file')),
          ),
        );
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
