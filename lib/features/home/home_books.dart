import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../library/book_links.dart';
import '../library/books_shelf.dart';
import '../library/data/library_repo.dart';

/// Home "Books" area: several horizontal rows of books that flip as they
/// scroll sideways (continue reading, new, most read, free PDF, for you).
class HomeBooks extends StatefulWidget {
  const HomeBooks({super.key});

  @override
  State<HomeBooks> createState() => _HomeBooksState();
}

class _HomeBooksState extends State<HomeBooks> {
  List<LibraryItem> _books = const [];
  Map<String, int> _recent = {};
  bool _done = false;
  final int _seed = DateTime.now().microsecondsSinceEpoch;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final all = await LibraryRepository.fetchItems(limit: 300);
      final sp = await SharedPreferences.getInstance();
      final rec = <String, int>{};
      for (final e in sp.getStringList('books_recent') ?? const <String>[]) {
        final p = e.split('|');
        if (p.length == 2) rec[p[0]] = int.tryParse(p[1]) ?? 0;
      }
      if (!mounted) return;
      setState(() {
        final books = all.where((b) => b.kind == 'book').toList();
        // Home shows image cards: books with a real cover first; books without one
        // only fill in when there are too few covered books.
        final covered = books
            .where((b) =>
                BookLinks.resolve(b.fileUrl, coverOverride: b.coverUrl).coverUrl !=
                null)
            .toList();
        _books = covered.length >= 8
            ? covered
            : [...covered, ...books.where((b) => !covered.contains(b))];
        _recent = rec;
        _done = true;
      });
    } catch (_) {
      if (mounted) setState(() => _done = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_done || _books.isEmpty) return const SizedBox.shrink();
    final b = _books;
    final continueList = b.where((x) => _recent.containsKey(x.id)).toList()
      ..sort((x, y) => _recent[y.id]!.compareTo(_recent[x.id]!));
    final newest = [...b]..sort((x, y) => y.createdAt.compareTo(x.createdAt));
    final popular = [...b]..sort((x, y) => y.downloads.compareTo(x.downloads));
    final pdfs = b.where((x) => x.fileType.toLowerCase() == 'pdf').toList();
    final mix = [...b]..shuffle(math.Random(_seed));
    popular.sort((x, y) => y.downloads.compareTo(x.downloads));
    final popMix = popular.where((x) => x.downloads > 0).toList()..shuffle(math.Random(_seed + 1));
    final pdfMix = [...pdfs]..shuffle(math.Random(_seed + 2));
    Widget row(String title, List<LibraryItem> list) => list.isEmpty
        ? const SizedBox.shrink()
        : _BooksRow(title: title, items: list.take(14).toList());
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      row('كمّل القراءة', continueList),
      row('الكتب', newest),
      row('الأكثر قراءة', popMix),
      row('كتب PDF مجانية', pdfMix),
      row('مقترحة ليك', mix),
      const SizedBox(height: 8),
    ]);
  }
}

class _BooksRow extends StatefulWidget {
  const _BooksRow({required this.title, required this.items});
  final String title;
  final List<LibraryItem> items;

  @override
  State<_BooksRow> createState() => _BooksRowState();
}

class _BooksRowState extends State<_BooksRow> {
  final _c = PageController(viewportFraction: 0.36);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: Text(widget.title,
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const BooksShelfScreen())),
          child: const Text('عرض الكل'),
        ),
      ]),
      SizedBox(
        height: 210,
        child: PageView.builder(
          controller: _c,
          padEnds: false,
          physics: const BouncingScrollPhysics(),
          itemCount: widget.items.length,
          itemBuilder: (_, i) {
            final it = widget.items[i];
            return AnimatedBuilder(
              animation: _c,
              builder: (ctx, child) {
                var d = 0.0;
                if (_c.hasClients && _c.position.haveDimensions) {
                  d = ((_c.page ?? _c.initialPage.toDouble()) - i).clamp(-1.5, 1.5);
                }
                final m = Matrix4.identity()
                  ..setEntry(3, 2, 0.0012)
                  ..rotateY(d * 0.35);
                return Transform(
                  alignment: Alignment.center,
                  transform: m,
                  child: child,
                );
              },
              child: Padding(
                padding: const EdgeInsetsDirectional.only(end: 12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () async {
                    final sp = await SharedPreferences.getInstance();
                    final list = sp.getStringList('books_recent') ?? <String>[];
                    list.removeWhere((e) => e.startsWith('${it.id}|'));
                    list.add('${it.id}|${DateTime.now().millisecondsSinceEpoch}');
                    await sp.setStringList('books_recent', list);
                    if (!context.mounted) return;
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => BookReaderScreen(item: it)));
                  },
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: [
                                BoxShadow(
                                    color: Colors.black.withValues(alpha: .25),
                                    blurRadius: 8,
                                    offset: const Offset(2, 4)),
                              ],
                            ),
                            child: BookCover(item: it),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(it.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 12)),
                      ]),
                ),
              ),
            );
          },
        ),
      ),
      const SizedBox(height: 12),
    ]);
  }
}
