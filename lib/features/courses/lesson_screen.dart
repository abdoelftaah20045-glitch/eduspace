import '../../core/in_app_player.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/storage_urls.dart';
import 'package:video_player/video_player.dart';

import '../../core/l10n.dart';
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

  Lesson get lesson => widget.lesson;

  @override
  void initState() {
    super.initState();
    _completed = lesson.completed;
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
      await CoursesRepository.saveProgress(lesson.id, completed: true);
      if (!mounted) return;
      setState(() => _completed = true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.of(context).t('generic_error'))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openExternal(String url) async {
    final resolved = await resolveStorageUrl(url);
    final uri = Uri.tryParse(resolved);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
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
          const SizedBox(height: 24),
          if (!_completed)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saving ? null : _markComplete,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: Text(s.t('mark_complete')),
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
                  child: InAppWebPlayer(url: resolved),
                ),
              );
            }
            return _VideoLesson(
              key: ValueKey(lesson.id),
              url: resolved,
              startAtSeconds: lesson.positionSeconds,
              onProgress: (seconds, done) {
                CoursesRepository.saveProgress(
                  lesson.id,
                  positionSeconds: seconds,
                  completed: done ? true : null,
                ).catchError((_) {});
                if (done && mounted) setState(() => _completed = true);
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
  });

  final String url;
  final int startAtSeconds;
  final void Function(int seconds, bool done) onProgress;

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
    if (!_reportedDone && total > 0 && value.position.inSeconds >= total * 0.9) {
      _reportedDone = true;
      widget.onProgress(value.position.inSeconds, true);
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
