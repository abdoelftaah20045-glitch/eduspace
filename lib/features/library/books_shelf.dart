import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

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

class _BooksShelfScreenState extends State<BooksShelfScreen> {
  final _search = TextEditingController();
  List<LibraryItem>? _books;
  Map<String, int> _recent = {};
  String? _cat;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final all = await LibraryRepository.fetchItems(limit: 500);
      final sp = await SharedPreferences.getInstance();
      final rec = <String, int>{};
      for (final e in sp.getStringList('books_recent') ?? const <String>[]) {
        final p = e.split('|');
        if (p.length == 2) rec[p[0]] = int.tryParse(p[1]) ?? 0;
      }
      if (mounted) {
        setState(() {
          _books = all.where((b) => b.kind == 'book').toList();
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

  @override
  Widget build(BuildContext context) {
    final ar = _ar(context);
    final books = _books;
    final q = _search.text.trim().toLowerCase();
    final cats = <String>{
      for (final b in books ?? const <LibraryItem>[])
        if (b.category.isNotEmpty) b.category
    };
    final shown = (books ?? const <LibraryItem>[]).where((b) {
      if (_cat != null && b.category != _cat) return false;
      if (q.isEmpty) return true;
      return b.title.toLowerCase().contains(q) ||
          b.author.toLowerCase().contains(q);
    }).toList();
    final recent = (books ?? const <LibraryItem>[])
        .where((b) => _recent.containsKey(b.id))
        .toList()
      ..sort((a, b) => _recent[b.id]!.compareTo(_recent[a.id]!));
    return Scaffold(
      appBar: AppBar(
        title: Text(ar ? 'الكتب' : 'Books'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: ar ? 'ابحث باسم الكتاب أو المؤلف' : 'Search books',
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
                  if (cats.isNotEmpty)
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: 48,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: ChoiceChip(
                                label: Text(ar ? 'الكل' : 'All'),
                                selected: _cat == null,
                                onSelected: (_) => setState(() => _cat = null),
                              ),
                            ),
                            for (final c in cats)
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 4),
                                child: ChoiceChip(
                                  label: Text(c),
                                  selected: _cat == c,
                                  onSelected: (_) => setState(() => _cat = c),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  if (recent.isNotEmpty && q.isEmpty && _cat == null) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                        child: Text(ar ? 'تابع القراءة' : 'Continue reading',
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 15)),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: 170,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          children: [
                            for (final b in recent.take(8))
                              Padding(
                                padding: const EdgeInsets.all(4),
                                child: SizedBox(
                                  width: 110,
                                  child: _BookTile(
                                      book: b, onTap: () => _open(b)),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (shown.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Text(ar ? 'لا توجد كتب بعد' : 'No books yet'),
                      ),
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
  late final WebViewController _c;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    final link = BookLinks.resolve(widget.item.fileUrl);
    _c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          if (mounted) setState(() => _loading = false);
        },
        onWebResourceError: (e) {
          if (e.isForMainFrame == true && mounted) {
            setState(() {
              _failed = true;
              _loading = false;
            });
          }
        },
      ))
      ..loadRequest(Uri.parse(link.readerUrl));
  }

  @override
  Widget build(BuildContext context) {
    final ar = _ar(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                _failed = false;
                _loading = true;
              });
              _c.reload();
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _c),
          if (_loading) const Center(child: CircularProgressIndicator()),
          if (_failed)
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
      ),
    );
  }
}
