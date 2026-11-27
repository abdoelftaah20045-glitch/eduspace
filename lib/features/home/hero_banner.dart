import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/cached_avatar.dart';

/// One slide of the Home hero carousel.
class HeroSlide {
  const HeroSlide({required this.title, this.subtitle = '', this.image, this.cta = '', required this.onTap});
  final String title;
  final String subtitle;
  final String? image;
  final String cta;
  final VoidCallback onTap;
}

/// Auto-playing hero banner. Slides go forward to the end, then back
/// (ping-pong). Pauses while the user touches it. Shows dots.
class HeroBanner extends StatefulWidget {
  const HeroBanner({super.key, required this.slides});
  final List<HeroSlide> slides;

  @override
  State<HeroBanner> createState() => _HeroBannerState();
}

class _HeroBannerState extends State<HeroBanner> {
  final _page = PageController(viewportFraction: .92);
  Timer? _timer;
  int _index = 0;
  int _dir = 1;
  bool _touching = false;

  @override
  void initState() {
    super.initState();
    if (widget.slides.length > 1) {
      _timer = Timer.periodic(const Duration(seconds: 4), (_) {
        if (_touching || !mounted || !_page.hasClients) return;
        final n = widget.slides.length;
        if (_index + _dir >= n || _index + _dir < 0) _dir = -_dir;
        _page.animateToPage(_index + _dir,
            duration: const Duration(milliseconds: 550), curve: Curves.easeInOutCubic);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.slides.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(children: [
        SizedBox(
          height: 170,
          child: Listener(
            onPointerDown: (_) => _touching = true,
            onPointerUp: (_) => _touching = false,
            onPointerCancel: (_) => _touching = false,
            child: PageView.builder(
              controller: _page,
              itemCount: widget.slides.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (_, i) {
                final s = widget.slides[i];
                final img = s.image ?? '';
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: s.onTap,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Stack(fit: StackFit.expand, children: [
                        if (img.isNotEmpty)
                          CachedImage(img,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              errorBuilder: (_, __, ___) => Container(color: scheme.primaryContainer))
                        else
                          Container(
                              decoration: BoxDecoration(
                                  gradient: LinearGradient(colors: [
                            scheme.primary,
                            scheme.primary.withValues(alpha: .65)
                          ]))),
                        Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Color(0x00000000), Color(0xCC000000)]),
                          ),
                        ),
                        PositionedDirectional(
                          start: 16,
                          end: 16,
                          bottom: 14,
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(s.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800)),
                                if (s.subtitle.isNotEmpty)
                                  Text(s.subtitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
                                if (s.cta.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                                    decoration: BoxDecoration(
                                        color: scheme.primary,
                                        borderRadius: BorderRadius.circular(20)),
                                    child: Text(s.cta,
                                        style: TextStyle(
                                            color: scheme.onPrimary,
                                            fontWeight: FontWeight.w800,
                                            fontSize: 12.5)),
                                  ),
                                ],
                              ]),
                        ),
                      ]),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        if (widget.slides.length > 1) ...[
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < widget.slides.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == _index ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(
                    color: i == _index ? scheme.primary : scheme.outlineVariant,
                    borderRadius: BorderRadius.circular(3)),
              ),
          ]),
        ],
      ]),
    );
  }
}
