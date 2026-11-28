import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'book_files.dart';
import 'library_screen.dart';
import 'book_links.dart';
import 'data/library_repo.dart';

bool _ar(BuildContext c) => Localizations.localeOf(c).languageCode == 'ar';

/// A book cover: remote cover when it loads, otherwise a generated spine card.
class BookCover extends StatelessWidget {
  const BookCover({super.key, required this.item});
  final LibraryItem item;

  @override
  Widget build(BuildContext context) {
    final color = Color(BookLinks.spineColor(item.title));
    final link = BookLinks.resolve(item.fileUrl, coverOverride: item.coverUrl);
    final fallback = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, Color.lerp(color, Colors.black, 0.35)!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.menu_book_rounded, color: Colors.white70, size: 22),
          const SizedBox(height: 8),
          Expanded(
            child: Text(
              item.title,
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  height: 1.25),
            ),
          ),
          if (item.author.isNotEmpty)
            Text(item.author,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      ),
    );
    final cover = link.coverUrl;
    return ClipRRect(
      borderRadius: const BorderRadius.horizontal(
          left: Radius.circular(3), right: Radius.circular(8)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (cover == null)
            fallback
          else
            Image.network(
              cover,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => fallback,
              loadingBuilder: (c, child, p) => p == null ? child : fallback,
            ),
          // spine shadow on the binding edge
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 10,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
                  Colors.black.withOpacity(0.35),
                  Colors.transparent,
                ]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class BooksShelfScreen extends StatefulWidget {
  const BooksShelfScreen({super.key});

  @override
  State<BooksShelfScreen> createState() => _BooksShelfScreenState();
}

String _langOf(LibraryItem b) {
  final l = b.language.toLowerCase();
  if (l.startsWith('ar')) return 'ar';
  if (l.startsWith('en')) return 'en';
  if (l.isNotEmpty) return l;
  return RegExp(r'[\u0600-\u06FF]').hasMatch(b.title) ? 'ar' : 'en';
}

class _BooksShelfScreenState extends State<BooksShelfScreen> {
  final _search = TextEditingController();
  final _banner = PageController(viewportFraction: 0.92);
  List<LibraryItem>? _books;
  List<String> _featured = const [];
  Map<String, int> _recent = {};
  String? _cat;
  String? _lang;
  String? _src;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    _banner.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final all = await LibraryRepository.fetchItems(limit: 500);
      final feat = await LibraryRepository.fetchFeatured();
      final sp = await SharedPreferences.getInstance();
      final rec = <String, int>{};
      for (final e in sp.getStringList('books_recent') ?? const <String>[]) {
        final p = e.split('|');
        if (p.length == 2) rec[p[0]] = int.tryParse(p[1]) ?? 0;
      }
      if (mounted) {
        setState(() {
          _books = all.where((b) => b.kind == 'book').toList();
          _featured = feat;
          _recent = rec;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _books = const []);
    }
  }

  Future<void> _open(LibraryItem b) async {
    final sp = await SharedPreferences.getInstance();
    _recent[b.id] = DateTime.now().millisecondsSinceEpoch;
    await sp.setStringList('books_recent',
        _recent.entries.map((e) => '${e.key}|${e.value}').toList());
    LibraryRepository.bumpDownloads(b.id);
    if (!mounted) return;
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => BookReaderScreen(item: b)));
    if (mounted) setState(() {});
  }

  Widget _chips(List<(String?, String)> opts, String? cur, void Function(String?) set) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        children: [
          for (final o in opts)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                label: Text(o.$2),
                selected: cur == o.$1,
                onSelected: (_) => setState(() => set(o.$1)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _title(String t, {VoidCallback? onMore, String? more}) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Row(children: [
          Expanded(
              child: Text(t,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 16))),
          if (onMore != null)
            TextButton(onPressed: onMore, child: Text(more ?? '')),
        ]),
      );

  Widget _row(List<LibraryItem> items) => SizedBox(
        height: 196,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            for (final b in items)
              Padding(
                padding: const EdgeInsets.all(4),
                child: SizedBox(
                    width: 112,
                    child: _BookTile(book: b, onTap: () => _open(b))),
              ),
          ],
        ),
      );

  Widget _featuredBanner(List<LibraryItem> feat) {
    return SizedBox(
      height: 168,
      child: PageView.builder(
        controller: _banner,
        itemCount: feat.length,
        itemBuilder: (c, i) {
          final b = feat[i];
          final color = Color(BookLinks.spineColor(b.title));
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: InkWell(
              onTap: () => _open(b),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    colors: [color, Color.lerp(color, Colors.black, 0.45)!],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  SizedBox(
                      width: 92,
                      height: 140,
                      child: DecoratedBox(
                        decoration: BoxDecoration(boxShadow: [
                          BoxShadow(
                              color: Colors.black.withOpacity(0.4),
                              blurRadius: 10,
                              offset: const Offset(2, 4)),
                        ]),
                        child: BookCover(item: b),
                      )),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(b.title,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                                height: 1.25)),
                        const SizedBox(height: 6),
                        if (b.author.isNotEmpty)
                          Text(b.author,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 12)),
                        if (b.category.isNotEmpty)
                          Text(b.category,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 11)),
                      ],
                    ),
                  ),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ar = _ar(context);
    final books = _books;
    final q = _search.text.trim().toLowerCase();
    final all = books ?? const <LibraryItem>[];
    final cats = <String>{
      for (final b in all)
        if (b.category.isNotEmpty) b.category
    }.toList()
      ..sort();
    final srcs = <String>{
      for (final b in all)
        if (b.source.isNotEmpty) b.source
    }.toList()
      ..sort();
    final langs = <String>{for (final b in all) _langOf(b)}.toList()..sort();
    final filtering =
        q.isNotEmpty || _cat != null || _lang != null || _src != null;
    final shown = all.where((b) {
      if (_cat != null && b.category != _cat) return false;
      if (_lang != null && _langOf(b) != _lang) return false;
      if (_src != null && b.source != _src) return false;
      if (q.isEmpty) return true;
      return b.title.toLowerCase().contains(q) ||
          b.author.toLowerCase().contains(q) ||
          b.category.toLowerCase().contains(q);
    }).toList();
    final recent = all.where((b) => _recent.containsKey(b.id)).toList()
      ..sort((a, b) => _recent[b.id]!.compareTo(_recent[a.id]!));
    final feat = [
      for (final id in _featured)
        for (final b in all)
          if (b.id == id) b
    ];
    String langName(String l) =>
        l == 'ar' ? (ar ? 'العربية' : 'Arabic') : (l == 'en' ? (ar ? 'الإنجليزية' : 'English') : l);
    return Scaffold(
      appBar: AppBar(
        title: Text(ar ? 'المكتبة' : 'Library'),
        actions: [
          IconButton(
            tooltip: ar ? 'الملفات والمرفقات' : 'Files',
            icon: const Icon(Icons.folder_open),
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const LibraryScreen())),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: ar ? 'ابحث باسم الكتاب أو المؤلف أو المجال' : 'Search books, authors, fields',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
              ),
            ),
          ),
        ),
      ),
      body: books == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: CustomScrollView(
                slivers: [
                  if (langs.length > 1)
                    SliverToBoxAdapter(
                      child: _chips([
                        (null, ar ? 'كل اللغات' : 'All languages'),
                        for (final l in langs) (l, langName(l)),
                      ], _lang, (v) => _lang = v),
                    ),
                  if (cats.length > 1)
                    SliverToBoxAdapter(
                      child: _chips([
                        (null, ar ? 'كل المجالات' : 'All fields'),
                        for (final c in cats) (c, c),
                      ], _cat, (v) => _cat = v),
                    ),
                  if (srcs.length > 1)
                    SliverToBoxAdapter(
                      child: _chips([
                        (null, ar ? 'كل المصادر' : 'All sources'),
                        for (final s2 in srcs) (s2, s2),
                      ], _src, (v) => _src = v),
                    ),
                  if (!filtering) ...[
                    if (feat.isNotEmpty)
                      SliverToBoxAdapter(child: _featuredBanner(feat)),
                    if (recent.isNotEmpty) ...[
                      SliverToBoxAdapter(
                          child: _title(ar ? 'تابع القراءة' : 'Continue reading')),
                      SliverToBoxAdapter(child: _row(recent.take(10).toList())),
                    ],
                    SliverToBoxAdapter(
                        child: _title(ar ? 'أحدث الكتب' : 'New books')),
                    SliverToBoxAdapter(child: _row(all.take(12).toList())),
                    for (final c in cats)
                      ...[
                        SliverToBoxAdapter(
                          child: _title(c,
                              onMore: () => setState(() => _cat = c),
                              more: ar ? 'عرض الكل' : 'See all'),
                        ),
                        SliverToBoxAdapter(
                          child: _row(all
                              .where((b) => b.category == c)
                              .take(12)
                              .toList()),
                        ),
                      ],
                    if (all.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                            child: Text(ar ? 'لا توجد كتب بعد' : 'No books yet')),
                      ),
                  ] else if (shown.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                          child: Text(ar ? 'لا توجد نتائج' : 'No results')),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.all(14),
                      sliver: SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 150,
                          childAspectRatio: 0.52,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 16,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (c, i) => _BookTile(
                              book: shown[i], onTap: () => _open(shown[i])),
                          childCount: shown.length,
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _BookTile extends StatelessWidget {
  const _BookTile({required this.book, required this.onTap});
  final LibraryItem book;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.28),
                      blurRadius: 8,
                      offset: const Offset(2, 4)),
                ],
              ),
              child: BookCover(item: book),
            ),
          ),
          const SizedBox(height: 6),
          Text(book.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
          if (book.author.isNotEmpty)
            Text(book.author,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    );
  }
}

class BookReaderScreen extends StatefulWidget {
  const BookReaderScreen({super.key, required this.item});
  final LibraryItem item;

  @override
  State<BookReaderScreen> createState() => _BookReaderScreenState();
}

class _BookReaderScreenState extends State<BookReaderScreen> {
  // PDF mode
  Uint8List? _bytes;
  int _pages = 0;
  int _page = 0;
  PageController? _pc;
  final Map<int, ui.Image> _imgs = {};
  final Set<int> _busyPages = {};
  double? _progress;
  bool _offline = false;
  // web fallback
  WebViewController? _web;
  bool _webLoading = true;
  bool _webFailed = false;
  String? _note;
  bool _starting = true;

  static const int _maxPdfBytes = 40 * 1024 * 1024;

  bool get _isPdf => _bytes != null;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _pc?.dispose();
    for (final i in _imgs.values) {
      i.dispose();
    }
    super.dispose();
  }

  Future<void> _start() async {
    final id = widget.item.id;
    try {
      _offline = await BookFiles.isOffline(id);
      File? file;
      if (_offline) {
        file = await BookFiles.offlineFile(id);
      } else {
        final cache = await BookFiles.cacheFile(id);
        if (await cache.exists()) {
          file = cache;
        } else {
          final url = await BookFiles.pdfUrl(widget.item.fileUrl);
          if (url != null) {
            try {
              await BookFiles.download(url, cache, onProgress: (p) {
                if (mounted) setState(() => _progress = p ?? -1);
              });
              file = cache;
            } catch (_) {
              file = null;
            }
          }
        }
      }
      if (file != null) {
        final len = await file.length();
        if (len <= _maxPdfBytes) {
          final bytes = await file.readAsBytes();
          final n = await _countPages(bytes);
          if (n > 0) {
            final sp = await SharedPreferences.getInstance();
            final last = (sp.getInt('book_page_$id') ?? 0).clamp(0, n - 1);
            _bytes = bytes;
            _pages = n;
            _page = last;
            _pc = PageController(initialPage: last);
            if (mounted) setState(() => _starting = false);
            _ensure(last);
            return;
          }
        } else {
          _note = 'big';
        }
      }
    } catch (_) {}
    _startWeb();
  }

  Future<int> _countPages(Uint8List b) async {
    // Fast path: the largest /Count in the file is the page tree total.
    final text = String.fromCharCodes(b.length > 3000000 ? b.sublist(0, 3000000) : b);
    var best = 0;
    for (final m in RegExp(r'/Type\s*/Pages[^>]*?/Count\s+(\d+)').allMatches(text)) {
      final v = int.tryParse(m.group(1)!) ?? 0;
      if (v > best) best = v;
    }
    if (best > 0 && await _exists(b, best - 1) && !await _exists(b, best)) {
      return best;
    }
    // Slow path: probe page indexes.
    var lo = 0;
    var hi = 1;
    while (await _exists(b, hi)) {
      lo = hi;
      hi *= 2;
      if (hi > 8192) break;
    }
    if (!await _exists(b, lo)) return 0;
    while (hi - lo > 1) {
      final mid = (lo + hi) ~/ 2;
      if (await _exists(b, mid)) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return lo + 1;
  }

  Future<bool> _exists(Uint8List b, int i) async {
    try {
      await for (final r in Printing.raster(b, pages: [i], dpi: 12)) {
        r.pixels;
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _ensure(int i) async {
    for (final k in [i, i + 1, i - 1]) {
      if (k < 0 || k >= _pages || _imgs.containsKey(k) || _busyPages.contains(k)) {
        continue;
      }
      _busyPages.add(k);
      try {
        await for (final r in Printing.raster(_bytes!, pages: [k], dpi: 150)) {
          final img = await r.toImage();
          if (!mounted) {
            img.dispose();
            return;
          }
          setState(() => _imgs[k] = img);
          break;
        }
      } catch (_) {}
      _busyPages.remove(k);
    }
    // keep memory small
    final drop = _imgs.keys.where((k) => (k - i).abs() > 3).toList();
    for (final k in drop) {
      _imgs.remove(k)?.dispose();
    }
  }

  Future<void> _onPage(int i) async {
    _page = i;
    setState(() {});
    _ensure(i);
    final sp = await SharedPreferences.getInstance();
    await sp.setInt('book_page_${widget.item.id}', i);
  }

  void _startWeb() {
    final link = BookLinks.resolve(widget.item.fileUrl);
    final c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          if (mounted) setState(() => _webLoading = false);
        },
        onWebResourceError: (e) {
          if (e.isForMainFrame == true && mounted) {
            setState(() {
              _webFailed = true;
              _webLoading = false;
            });
          }
        },
      ))
      ..loadRequest(Uri.parse(link.readerUrl));
    if (mounted) {
      setState(() {
        _web = c;
        _starting = false;
      });
    }
  }

  Future<void> _toggleOffline() async {
    if (_offline) {
      await BookFiles.removeOffline(widget.item.id);
    } else {
      await BookFiles.saveOffline(widget.item.id);
    }
    _offline = await BookFiles.isOffline(widget.item.id);
    if (mounted) setState(() {});
  }

  Future<void> _goTo() async {
    final ar = _ar(context);
    final c = TextEditingController(text: '${_page + 1}');
    final v = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ar ? 'اذهب إلى صفحة' : 'Go to page'),
        content: TextField(
          controller: c,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(hintText: '1 - $_pages'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(ar ? 'إلغاء' : 'Cancel')),
          FilledButton(
              onPressed: () =>
                  Navigator.of(ctx).pop(int.tryParse(c.text.trim())),
              child: Text(ar ? 'اذهب' : 'Go')),
        ],
      ),
    );
    if (v != null && v >= 1 && v <= _pages) _pc?.jumpToPage(v - 1);
  }

  @override
  Widget build(BuildContext context) {
    final ar = _ar(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (_isPdf)
            IconButton(
              tooltip: _offline
                  ? (ar ? 'إزالة النسخة من الجهاز' : 'Remove offline copy')
                  : (ar ? 'حفظ على الجهاز للقراءة بدون إنترنت' : 'Save for offline'),
              icon: Icon(_offline ? Icons.offline_pin : Icons.download_outlined),
              onPressed: _toggleOffline,
            ),
          if (_web != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () {
                setState(() {
                  _webFailed = false;
                  _webLoading = true;
                });
                _web!.reload();
              },
            ),
        ],
      ),
      body: _starting
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_progress != null && _progress! >= 0)
                    SizedBox(
                        width: 200,
                        child: LinearProgressIndicator(value: _progress))
                  else
                    const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                  Text(ar ? 'جاري تحميل الكتاب...' : 'Loading the book...'),
                ],
              ),
            )
          : _isPdf
              ? _pdfBody(ar)
              : _webBody(ar),
    );
  }

  Widget _pdfBody(bool ar) {
    return Column(
      children: [
        Expanded(
          child: PageView.builder(
            controller: _pc,
            itemCount: _pages,
            onPageChanged: _onPage,
            itemBuilder: (c, i) {
              final img = _imgs[i];
              if (img == null) {
                _ensure(i);
                return const Center(child: CircularProgressIndicator());
              }
              return InteractiveViewer(
                minScale: 1,
                maxScale: 5,
                child: Center(
                  child: AspectRatio(
                    aspectRatio: img.width / img.height,
                    child: RawImage(image: img, fit: BoxFit.contain),
                  ),
                ),
              );
            },
          ),
        ),
        InkWell(
          onTap: _goTo,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              '${_page + 1} / $_pages',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }

  Widget _webBody(bool ar) {
    return Stack(
      children: [
        if (_web != null) WebViewWidget(controller: _web!),
        if (_webLoading) const Center(child: CircularProgressIndicator()),
        if (_note == 'big')
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: Container(
              color: Colors.black54,
              padding: const EdgeInsets.all(8),
              child: Text(
                ar
                    ? 'الكتاب كبير، يُفتح في العارض العادي (بدون حفظ الصفحة).'
                    : 'Large book: opened in the basic viewer (no page memory).',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ),
        if (_webFailed)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                ar
                    ? 'تعذر فتح الكتاب. تأكد أن الرابط عام ("أي شخص لديه الرابط") وأن الإنترنت يعمل.'
                    : 'Could not open the book. Make sure the link is public and you are online.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}
