import '../../core/admin_search.dart';
import '../../core/search_norm.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/l10n.dart';
import 'data/admin_tools_repo.dart';

/// Audit log (A33): who did what, when, on which record.
class AdminAuditScreen extends StatefulWidget {
  const AdminAuditScreen({super.key});

  @override
  State<AdminAuditScreen> createState() => _AdminAuditScreenState();
}

class _AdminAuditScreenState extends State<AdminAuditScreen> {
  List<Map<String, dynamic>>? _rows;
  String _q = '';
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await AdminToolsRepository.fetchAudit();
      if (mounted) setState(() => _rows = r);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final rows = _rows?.where((r) => matchesAny(_q, r)).toList();
    return Scaffold(
      appBar: AppBar(title: Text(s.t('audit_label'))),
      body: Column(children: [
        AdminSearchField(onChanged: (v) => setState(() => _q = v)),
        Expanded(child: _failed
          ? Center(child: Text(s.t('generic_error')))
          : rows == null
              ? const Center(child: CircularProgressIndicator())
              : rows.isEmpty
                  ? Center(child: Text(s.t('no_audit')))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: rows.length,
                        itemBuilder: (context, i) {
                          final r = rows[i];
                          final who = (r['profiles']
                                  as Map<String, dynamic>?)?['full_name'] ??
                              (r['profiles'] as Map<String, dynamic>?)?['email'] ??
                              '-';
                          final at = DateTime.tryParse(
                                  (r['created_at'] as String?) ?? '')
                              ?.toLocal();
                          final details = r['details'] as Map?;
                          return Card(
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                            child: ListTile(
                              leading: const CircleAvatar(
                                  child: Icon(Icons.history, size: 20)),
                              title: Text('${r['action']}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              subtitle: Text([
                                '$who',
                                if (at != null)
                                  DateFormat('d MMM y, h:mm a').format(at),
                                if (details != null && details.isNotEmpty)
                                  details.entries
                                      .map((e) => '${e.key}: ${e.value}')
                                      .join(' | '),
                              ].join('\n')),
                              isThreeLine: true,
                            ),
                          );
                        },
                      ),
                    ),
    ),
      ]),
    );
  }
}
