import '../../core/maintenance.dart';
import 'package:flutter/material.dart';
import '../../core/pressable.dart';
import 'package:url_launcher/url_launcher.dart';
import 'books_shelf.dart';

import '../../core/l10n.dart';
import 'data/library_repo.dart';

IconData _iconFor(String type) => switch (type) {
      'pdf' => Icons.picture_as_pdf_outlined,
      'word' => Icons.description_outlined,
      'powerpoint' => Icons.slideshow_outlined,
      'excel' => Icons.table_chart_outlined,
      'image' => Icons.image_outlined,
      'video' => Icons.video_library_outlined,
      'audio' => Icons.audio_file_outlined,
      'zip' => Icons.folder_zip_outlined,
      'link' => Icons.link_outlined,
      _ => Icons.insert_drive_file_outlined,
    };

Color _colorFor(String type) => switch (type) {
      'pdf' => const Color(0xFFE53935),
      'word' => const Color(0xFF2196F3),
      'powerpoint' => const Color(0xFFF29900),
      'excel' => const Color(0xFF2E9E5B),
      'image' => const Color(0xFFAB47BC),
      'video' => const Color(0xFF00ACC1),
      'audio' => const Color(0xFF7C4DFF),
      'zip' => const Color(0xFF8D6E63),
      'link' => const Color(0xFF5C6BC0),
      _ => const Color(0xFF607D8B),
    };

String _sizeLabel(int? bytes) {
  if (bytes == null || bytes <= 0) return '';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// Resource library with search and category filter (doc section 16).
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _search = TextEditingController();
  List<LibraryItem>? _items;
  Set<String> _categories = const {};
  String? _category;
  bool _grid = true;

  @override
  void initState() {
    super.initState();
    _load();
    LibraryRepository.fetchCategories()
        .then((cats) {
          if (mounted) setState(() => _categories = cats);
        })
        .catchError((_) {});
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final items = await LibraryRepository.fetchItems(
          query: _search.text, category: _category);
      if (mounted) setState(() => _items = items);
    } catch (_) {
      if (mounted) setState(() => _items = const []);
    }
  }

  Future<void> _open(LibraryItem item) async {
    await LibraryRepository.bumpDownloads(item.id);
    final url = await LibraryRepository.resolveUrl(item.fileUrl);
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) =>
      MaintenanceGate(pageKey: 'library', child: Builder(builder: _mtBuild));

  Widget _mtBuild(BuildContext context) {
    final s = S.of(context);
    final items = _items;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('library_label')),
        actions: [
          IconButton(
            tooltip: 'Books',
            icon: const Icon(Icons.menu_book_rounded),
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const BooksShelfScreen())),
          ),
          IconButton(
            icon: Icon(_grid ? Icons.view_list_outlined : Icons.grid_view),
            onPressed: () => setState(() => _grid = !_grid),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _search,
              onChanged: (_) => _load(),
              decoration: InputDecoration(
                hintText: s.t('search_label'),
                prefixIcon: const Icon(Icons.search),
                isDense: true,
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          if (_categories.isNotEmpty)
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                children: [
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: ChoiceChip(
                      label: Text(s.t('filter_all')),
                      selected: _category == null,
                      onSelected: (_) {
                        setState(() => _category = null);
                        _load();
                      },
                    ),
                  ),
                  ..._categories.map((c) => Padding(
                        padding: const EdgeInsetsDirectional.only(end: 8),
                        child: ChoiceChip(
                          label: Text(c),
                          selected: _category == c,
                          onSelected: (_) {
                            setState(() => _category = c);
                            _load();
                          },
                        ),
                      )),
                ],
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: items == null
                  ? const Center(child: CircularProgressIndicator())
                  : items.isEmpty
                      ? ListView(
                          padding: const EdgeInsets.all(32),
                          children: [
                            const SizedBox(height: 60),
                            const Icon(Icons.folder_open,
                                size: 56, color: Colors.grey),
                            const SizedBox(height: 12),
                            Center(child: Text(s.t('no_library_items'))),
                          ],
                        )
                      : (_grid
                          ? GridView.builder(
                              padding: const EdgeInsets.all(16),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 12,
                                childAspectRatio: .9,
                              ),
                              itemCount: items.length,
                              itemBuilder: (context, i) =>
                                  _FileCard(item: items[i], onOpen: _open),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: items.length,
                              itemBuilder: (context, i) {
                                final item = items[i];
                                final size = _sizeLabel(item.sizeBytes);
                                final color = _colorFor(item.fileType);
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                  clipBehavior: Clip.antiAlias,
                                  child: ListTile(
                                    leading: Icon(_iconFor(item.fileType),
                                        color: color),
                                    title: Text(item.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis),
                                    subtitle: Text(
                                      [
                                        s.t('file_type_${item.fileType}'),
                                        if (size.isNotEmpty) size,
                                      ].join(' · '),
                                    ),
                                    onTap: () => _open(item),
                                  ),
                                );
                              },
                            )),
            ),
          ),
        ],
      ),
    );
  }
}

/// File card in the reference style: tinted header with the type icon and a
/// kebab menu, then title, size and date.
class _FileCard extends StatelessWidget {
  const _FileCard({required this.item, required this.onOpen});

  final LibraryItem item;
  final Future<void> Function(LibraryItem) onOpen;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final color = _colorFor(item.fileType);
    final size = _sizeLabel(item.sizeBytes);
    final d = item.createdAt;
    final date =
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    return PressScale(child: Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onOpen(item),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                color: color.withValues(alpha: .12),
                child: Stack(
                  children: [
                    Center(
                        child: Icon(_iconFor(item.fileType),
                            size: 48, color: color)),
                    PositionedDirectional(
                      top: 0,
                      end: 0,
                      child: PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert, size: 20),
                        onSelected: (_) => onOpen(item),
                        itemBuilder: (_) => [
                          PopupMenuItem(
                              value: 'open', child: Text(s.t('open_file'))),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                    [if (size.isNotEmpty) size, date].join(' · '),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ));
  }
}
