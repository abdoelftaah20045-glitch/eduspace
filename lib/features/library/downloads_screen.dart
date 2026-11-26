import '../../core/maintenance.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../core/l10n.dart';
import '../../core/offline_store.dart';

/// Files saved for offline use.
class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  List<Map<String, dynamic>>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final l = await OfflineStore.list();
    if (mounted) setState(() => _items = l);
  }

  void _open(Map<String, dynamic> e) {
    openOfflineFile(context, e['path'] as String, e['name'] as String);
  }

  @override
  Widget build(BuildContext context) =>
      MaintenanceGate(pageKey: 'downloads', child: Builder(builder: _mtBuild));

  Widget _mtBuild(BuildContext context) {
    final s = S.of(context);
    final items = _items;
    return Scaffold(
      appBar: AppBar(title: Text(s.t('dl_title'))),
      body: items == null
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
              ? Center(
                  child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(s.t('dl_empty'), textAlign: TextAlign.center)))
              : ListView(children: [
                  for (final e in items)
                    ListTile(
                      leading: const Icon(Icons.offline_pin_outlined),
                      title: Text('${e['name']}'),
                      subtitle: Text(
                          '${((e['size'] as num? ?? 0) / 1024).round()} KB'),
                      onTap: () => _open(e),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          await OfflineStore.remove(e['id'] as String);
                          _load();
                        },
                      ),
                    ),
                ]),
    );
  }
}

/// Opens a saved file inside the app: PDF and images. Other types show a note.
void openOfflineFile(BuildContext context, String path, String name) {
  final lower = name.toLowerCase();
  Widget body;
  if (lower.endsWith('.pdf')) {
    body = PdfPreview(
      build: (_) => File(path).readAsBytes(),
      canChangePageFormat: false,
      canChangeOrientation: false,
      canDebug: false,
    );
  } else if (RegExp(r'\.(png|jpe?g|gif|webp)$').hasMatch(lower)) {
    body = InteractiveViewer(child: Center(child: Image.file(File(path))));
  } else {
    body = Center(
        child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(S.of(context).t('dl_saved_only'),
                textAlign: TextAlign.center)));
  }
  Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(appBar: AppBar(title: Text(name)), body: body)));
}
