import '../../core/maintenance.dart';
import 'package:flutter/material.dart';
import '../../core/image_carousel.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/l10n.dart';
import '../../core/tenant.dart';

class _Ann {
  _Ann(this.id, this.title, this.body, this.at,
      [this.images = const [], this.slideSeconds = 4]);
  final int slideSeconds;
  final List<String> images;
  final String id;
  final String title;
  final String body;
  final DateTime at;
}

/// Student: all active announcements, newest first, with a detail page
/// (screen 11).
class AnnouncementsScreen extends StatefulWidget {
  const AnnouncementsScreen({super.key});

  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen> {
  List<_Ann>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final now = DateTime.now().toUtc();
      final rows = await Supabase.instance.client
          .from('announcements')
          .select()
          .eq('tenant_id', TenantContext.id)
          .lte('starts_at', now.toIso8601String())
          .order('created_at', ascending: false)
          .limit(100);
      final out = <_Ann>[];
      for (final m in rows) {
        final ends = DateTime.tryParse((m['ends_at'] ?? '').toString());
        if (ends != null && ends.isBefore(now)) continue;
        out.add(_Ann(
          m['id'] as String,
          (m['title'] as String?) ?? '',
          (m['body'] as String?) ?? '',
          DateTime.tryParse((m['created_at'] ?? '').toString())?.toLocal() ??
              DateTime.now(),
          [
            if (m['images'] is List)
              for (final u in m['images'] as List) u.toString(),
          ],
          ((m['slide_seconds'] as num?)?.toInt() ?? 4).clamp(2, 30),
        ));
      }
      if (mounted) setState(() => _items = out);
    } catch (_) {
      if (mounted) setState(() => _items = const []);
    }
  }

  @override
  Widget build(BuildContext context) =>
      MaintenanceGate(pageKey: 'announcements', child: Builder(builder: _mtBuild));

  Widget _mtBuild(BuildContext context) {
    final s = S.of(context);
    final fmt = DateFormat('d MMM y', s.locale.languageCode);
    final items = _items;
    return Scaffold(
      appBar: AppBar(title: Text(s.t('ann_title'))),
      body: items == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: items.isEmpty
                  ? ListView(children: [
                      const SizedBox(height: 120),
                      Center(child: Text(s.t('ann_empty'))),
                    ])
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: items.length,
                      itemBuilder: (context, i) {
                        final a = items[i];
                        return Card(
                          child: ListTile(
                            leading: const CircleAvatar(
                                child: Icon(Icons.campaign_outlined)),
                            title: Text(a.title,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                                '${fmt.format(a.at)}\n${a.body}',
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis),
                            isThreeLine: true,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => _AnnDetail(a: a)),
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}

class _AnnDetail extends StatelessWidget {
  const _AnnDetail({required this.a});

  final _Ann a;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final fmt = DateFormat('d MMMM y, h:mm a', s.locale.languageCode);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('ann_title'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (a.images.isNotEmpty) ...[
            ImageCarousel(
                urls: a.images, interval: Duration(seconds: a.slideSeconds)),
            const SizedBox(height: 16),
          ],
          Text(a.title,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(fmt.format(a.at), style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          SelectableText(a.body, style: Theme.of(context).textTheme.bodyLarge),
        ],
      ),
    );
  }
}
