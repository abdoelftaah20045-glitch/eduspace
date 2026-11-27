import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../library/book_links.dart';
import '../library/books_shelf.dart';
import '../library/data/library_repo.dart';
import 'file_import_screen.dart' show parseTable;

bool _ar(BuildContext c) => Localizations.localeOf(c).languageCode == 'ar';

const kBooksTemplate = 'title,author,category,link,cover_url\n'
    'Book title,Author name,Medicine,https://drive.google.com/file/d/FILE_ID/view,\n'
    'Another book,,General,https://archive.org/details/ITEM_ID,\n';

/// Admin: books are only a title + external link (Drive, Archive.org,
/// Dropbox, direct PDF). No file is stored in the app or on the server.
class AdminBooksScreen extends StatefulWidget {
  const AdminBooksScreen({super.key});

  @override
  State<AdminBooksScreen> createState() => _AdminBooksScreenState();
}

class _AdminBooksScreenState extends State<AdminBooksScreen> {
  List<LibraryItem>? _books;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final all = await LibraryRepository.fetchItems(limit: 500);
      if (mounted) {
        setState(() => _books = all.where((b) => b.kind == 'book').toList());
      }
    } catch (_) {
      if (mounted) setState(() => _books = const []);
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _addOne() async {
    final ar = _ar(context);
    final title = TextEditingController();
    final author = TextEditingController();
    final cat = TextEditingController();
    final link = TextEditingController();
    final cover = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ar ? 'إضافة كتاب' : 'Add a book'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: title,
                decoration:
                    InputDecoration(labelText: ar ? 'اسم الكتاب' : 'Title')),
            TextField(
                controller: author,
                decoration:
                    InputDecoration(labelText: ar ? 'المؤلف' : 'Author')),
            TextField(
                controller: cat,
                decoration:
                    InputDecoration(labelText: ar ? 'التصنيف' : 'Category')),
            TextField(
                controller: link,
                decoration: InputDecoration(
                    labelText: ar
                        ? 'رابط الكتاب (Drive / Archive / PDF)'
                        : 'Book link (Drive / Archive / PDF)')),
            TextField(
                controller: cover,
                decoration: InputDecoration(
                    labelText: ar
                        ? 'رابط الغلاف (اختياري)'
                        : 'Cover URL (optional)')),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(ar ? 'إلغاء' : 'Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(ar ? 'حفظ' : 'Save')),
        ],
      ),
    );
    if (ok != true) return;
    if (title.text.trim().isEmpty || link.text.trim().isEmpty) {
      _snack(ar ? 'الاسم والرابط مطلوبان' : 'Title and link are required');
      return;
    }
    await _insert(title.text, author.text, cat.text, link.text, cover.text);
    await _load();
  }

  Future<void> _insert(
      String title, String author, String cat, String link, String cover) async {
    final l = BookLinks.resolve(link, coverOverride: cover);
    await LibraryRepository.create({
      'title': title.trim(),
      'file_url': link.trim(),
      'file_type': 'link',
      'category': cat.trim().isEmpty ? 'general' : cat.trim(),
      'author': author.trim(),
      'cover_url': l.coverUrl,
      'kind': 'book',
    });
  }

  Future<void> _bulk() async {
    final ar = _ar(context);
    final res = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['csv', 'xlsx'],
        withData: true);
    if (res == null || res.files.isEmpty) return;
    final f = res.files.first;
    final bytes = f.bytes;
    if (bytes == null) return;
    setState(() => _busy = true);
    var added = 0;
    var skipped = 0;
    try {
      final rows = parseTable(f.name, bytes);
      if (rows.isEmpty) {
        _snack(ar ? 'الملف فارغ' : 'Empty file');
        return;
      }
      final head = rows.first.map((e) => e.toLowerCase().trim()).toList();
      int col(List<String> names) {
        for (final n in names) {
          final i = head.indexOf(n);
          if (i >= 0) return i;
        }
        return -1;
      }

      final iT = col(['title', 'name', 'العنوان', 'الاسم']);
      final iA = col(['author', 'المؤلف']);
      final iC = col(['category', 'التصنيف']);
      final iL = col(['link', 'url', 'book_url', 'file_url', 'الرابط']);
      final iV = col(['cover_url', 'cover', 'الغلاف']);
      if (iT < 0 || iL < 0) {
        _snack(ar
            ? 'الأعمدة المطلوبة: title و link'
            : 'Columns needed: title and link');
        return;
      }
      String cell(List<String> r, int i) =>
          i >= 0 && i < r.length ? r[i].trim() : '';
      final existing = {for (final b in _books ?? const <LibraryItem>[]) b.fileUrl};
      for (final r in rows.skip(1)) {
        final t = cell(r, iT);
        final l = cell(r, iL);
        if (t.isEmpty || !l.startsWith('http') || existing.contains(l)) {
          skipped++;
          continue;
        }
        try {
          await _insert(t, cell(r, iA), cell(r, iC), l, cell(r, iV));
          existing.add(l);
          added++;
        } catch (_) {
          skipped++;
        }
      }
      _snack(ar
          ? 'تمت إضافة $added كتاب، وتخطي $skipped'
          : 'Added $added books, skipped $skipped');
    } catch (e) {
      _snack(ar ? 'تعذر قراءة الملف' : 'Could not read the file');
    } finally {
      if (mounted) setState(() => _busy = false);
      await _load();
    }
  }

  Future<void> _delete(LibraryItem b) async {
    final ar = _ar(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ar ? 'حذف الكتاب؟' : 'Delete this book?'),
        content: Text(b.title),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(ar ? 'إلغاء' : 'Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(ar ? 'حذف' : 'Delete')),
        ],
      ),
    );
    if (ok == true) {
      try {
        await LibraryRepository.delete(b.id);
      } catch (_) {}
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ar = _ar(context);
    final books = _books;
    return Scaffold(
      appBar: AppBar(
        title: Text(ar ? 'إدارة الكتب' : 'Manage books'),
        actions: [
          IconButton(
            tooltip: ar ? 'استيراد من ملف' : 'Import from file',
            icon: const Icon(Icons.upload_file),
            onPressed: _busy ? null : _bulk,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addOne,
        icon: const Icon(Icons.add),
        label: Text(ar ? 'كتاب جديد' : 'New book'),
      ),
      body: Column(
        children: [
          if (_busy) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Text(
              ar
                  ? 'الكتب روابط فقط (Drive أو Archive أو PDF). لا يتم تخزين أي ملف في التطبيق أو السيرفر. ملف الاستيراد: title, author, category, link, cover_url.'
                  : 'Books are links only (Drive, Archive or PDF). Nothing is stored in the app or on the server. Import columns: title, author, category, link, cover_url.',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
          Expanded(
            child: books == null
                ? const Center(child: CircularProgressIndicator())
                : books.isEmpty
                    ? Center(child: Text(ar ? 'لا توجد كتب' : 'No books yet'))
                    : ListView.builder(
                        itemCount: books.length,
                        itemBuilder: (c, i) {
                          final b = books[i];
                          return ListTile(
                            leading: SizedBox(
                                width: 40, height: 56, child: BookCover(item: b)),
                            title: Text(b.title,
                                maxLines: 2, overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                                [b.author, b.category]
                                    .where((x) => x.isNotEmpty)
                                    .join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _delete(b),
                            ),
                            onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                    builder: (_) => BookReaderScreen(item: b))),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
