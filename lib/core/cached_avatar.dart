import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Picture loader with a memory + disk cache, so a picture that was
/// loaded once appears instantly (also after restarting the app) and
/// big source pictures are requested in a small size.
class ImgCache {
  ImgCache._();
  static final Map<String, Uint8List> _mem = {};
  static final Map<String, Future<Uint8List?>> _busy = {};
  static Directory? _dir;

  /// Asks the picture host for a small version where it supports it.
  static String small(String url, {int px = 160}) {
    final u = url.trim();
    if ((u.contains('ggpht.com') || u.contains('googleusercontent.com')) &&
        RegExp(r'=s\d+').hasMatch(u)) {
      return u.replaceFirst(RegExp(r'=s\d+(-c)?'), '=s$px-c');
    }
    return u;
  }

  static Uint8List? peek(String url) => _mem[url];

  static Future<Uint8List?> get(String url) {
    final hit = _mem[url];
    if (hit != null) return Future.value(hit);
    return _busy[url] ??= _fetch(url).whenComplete(() => _busy.remove(url));
  }

  static Future<Uint8List?> _fetch(String url) async {
    File? f;
    try {
      _dir ??= Directory('${(await getTemporaryDirectory()).path}/img_cache');
      if (!_dir!.existsSync()) _dir!.createSync(recursive: true);
      f = File('${_dir!.path}/${url.hashCode.toRadixString(16)}_${url.length}');
      if (f.existsSync() && f.lengthSync() > 0) {
        final b = await f.readAsBytes();
        _mem[url] = b;
        return b;
      }
    } catch (_) {}
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final r = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 15));
        if (r.statusCode == 200 && r.bodyBytes.isNotEmpty) {
          _mem[url] = r.bodyBytes;
          try {
            await f?.writeAsBytes(r.bodyBytes);
          } catch (_) {}
          return r.bodyBytes;
        }
      } catch (_) {}
    }
    return null;
  }
}

/// Round picture (teacher / profile) from the cache; shows [fallback]
/// while loading or when the picture cannot be loaded.
class CachedAvatar extends StatelessWidget {
  const CachedAvatar({
    super.key,
    required this.url,
    required this.radius,
    required this.fallback,
    this.backgroundColor,
  });
  final String? url;
  final double radius;
  final Widget fallback;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final raw = (url ?? '').trim();
    if (raw.isEmpty) {
      return CircleAvatar(
          radius: radius, backgroundColor: backgroundColor, child: fallback);
    }
    final u = ImgCache.small(raw, px: (radius * 6).round().clamp(96, 400));
    return FutureBuilder<Uint8List?>(
      future: ImgCache.get(u),
      initialData: ImgCache.peek(u),
      builder: (_, snap) {
        final b = snap.data;
        return CircleAvatar(
          radius: radius,
          backgroundColor: backgroundColor,
          backgroundImage: b == null ? null : MemoryImage(b),
          child: b == null ? fallback : null,
        );
      },
    );
  }
}

/// Drop-in for Image.network with the disk/memory cache above.
class CachedImage extends StatelessWidget {
  const CachedImage(this.url,
      {super.key, this.fit, this.width, this.height, this.errorBuilder});
  final String url;
  final BoxFit? fit;
  final double? width;
  final double? height;
  final ImageErrorWidgetBuilder? errorBuilder;

  @override
  Widget build(BuildContext context) {
    final u = url.trim();
    final scheme = Theme.of(context).colorScheme;
    Widget holder([Widget? child]) => Container(
        width: width,
        height: height,
        color: scheme.surfaceContainerHighest.withValues(alpha: .5),
        child: child);
    if (u.isEmpty) return holder();
    return FutureBuilder<Uint8List?>(
      future: ImgCache.get(u),
      initialData: ImgCache.peek(u),
      builder: (ctx, snap) {
        final b = snap.data;
        if (b != null) {
          return Image.memory(b,
              fit: fit,
              width: width,
              height: height,
              gaplessPlayback: true,
              errorBuilder: errorBuilder);
        }
        if (snap.connectionState == ConnectionState.done) {
          return errorBuilder != null
              ? errorBuilder!(ctx, 'load failed', null)
              : holder(const Icon(Icons.broken_image_outlined));
        }
        return holder();
      },
    );
  }
}
