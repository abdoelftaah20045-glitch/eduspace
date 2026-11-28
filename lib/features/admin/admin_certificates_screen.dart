import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/l10n.dart';
import 'certificate_settings_screen.dart';
import 'data/admin_panel_repo.dart';

/// Admin: all issued certificates - search and cancel with a reason.
class AdminCertificatesScreen extends StatefulWidget {
  const AdminCertificatesScreen({super.key});

  @override
  State<AdminCertificatesScreen> createState() =>
      _AdminCertificatesScreenState();
}

class _AdminCertificatesScreenState extends State<AdminCertificatesScreen> {
  final _search = TextEditingController();
  List<Map<String, dynamic>>? _certs;

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
      final certs =
          await AdminPanelRepository.fetchCertificates(query: _search.text);
      if (mounted) setState(() => _certs = certs);
    } catch (_) {
      if (mounted) setState(() => _certs = const []);
    }
  }

  Future<void> _cancel(Map<String, dynamic> cert) async {
    final s = S.of(context);
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _CancelDialog(),
    );
    if (reason == null || reason.trim().isEmpty) return;
    try {
      await AdminPanelRepository.cancelCertificate(
          cert['id'] as String, reason);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.t('certificate_cancelled'))));
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.t('generic_error'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('pref_certificates')),
        actions: [
          IconButton(
            tooltip: s.t('cert_settings'),
            icon: const Icon(Icons.tune),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const CertificateSettingsScreen())),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: s.t('search_users'),
                prefixIcon: const Icon(Icons.search),
              ),
              onChanged: (_) => _load(),
            ),
          ),
          Expanded(
            child: _certs == null
                ? const Center(child: CircularProgressIndicator())
                : _certs!.isEmpty
                    ? Center(child: Text(s.t('no_certificates')))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(4, 0, 4, 16),
                        itemCount: _certs!.length,
                        itemBuilder: (context, i) {
                          final c = _certs![i];
                          final status = (c['status'] as String?) ?? 'valid';
                          final issued = DateTime.tryParse(
                                  (c['issued_at'] ?? '').toString())
                              ?.toLocal();
                          return Card(
                            clipBehavior: Clip.antiAlias,
                            child: ListTile(
                              leading: Icon(
                                Icons.workspace_premium,
                                color: status == 'valid' ? null : Colors.grey,
                              ),
                              title: Text(
                                (c['student_name'] as String?) ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style:
                                    const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              subtitle: Text(
                                '${c['course_title'] ?? ''}\n'
                                '${c['certificate_number'] ?? ''} · '
                                '${status == 'valid' ? s.t('status_valid') : s.t('status_cancelled')}'
                                '${issued == null ? '' : ' · ${DateFormat('d MMM y', s.locale.languageCode).format(issued)}'}'
                                '${(c['cancel_reason'] as String?)?.isNotEmpty == true ? '\n${c['cancel_reason']}' : ''}',
                              ),
                              isThreeLine: true,
                              trailing: status == 'valid'
                                  ? IconButton(
                                      tooltip: s.t('cancel_certificate'),
                                      icon: const Icon(Icons.block,
                                          color: Colors.red),
                                      onPressed: () => _cancel(c),
                                    )
                                  : null,
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _CancelDialog extends StatefulWidget {
  const _CancelDialog();

  @override
  State<_CancelDialog> createState() => _CancelDialogState();
}

class _CancelDialogState extends State<_CancelDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return AlertDialog(
      title: Text(s.t('cancel_certificate')),
      content: TextField(
        controller: _reason,
        decoration: InputDecoration(hintText: s.t('cancel_reason_label')),
        maxLines: 2,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(s.t('cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_reason.text),
          child: Text(s.t('save')),
        ),
      ],
    );
  }
}
