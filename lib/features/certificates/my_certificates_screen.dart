import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/l10n.dart';
import 'certificate_view_screen.dart';
import 'data/certificates_repo.dart';
import 'verify_certificate_screen.dart';

/// "My certificates": every certificate the student earned.
class MyCertificatesScreen extends StatefulWidget {
  const MyCertificatesScreen({super.key});

  @override
  State<MyCertificatesScreen> createState() => _MyCertificatesScreenState();
}

class _MyCertificatesScreenState extends State<MyCertificatesScreen> {
  List<Certificate>? _certs;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final certs = await CertificatesRepository.fetchMine();
      if (mounted) setState(() => _certs = certs);
    } catch (_) {
      if (mounted) setState(() => _certs = const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('my_certificates')),
        actions: [
          IconButton(
            tooltip: s.t('verify_certificate_title'),
            icon: const Icon(Icons.verified_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => const VerifyCertificateScreen()),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _certs == null
            ? const Center(child: CircularProgressIndicator())
            : _certs!.isEmpty
                ? ListView(
                    padding: const EdgeInsets.all(32),
                    children: [
                      const SizedBox(height: 80),
                      const Icon(Icons.workspace_premium_outlined,
                          size: 56, color: Colors.grey),
                      const SizedBox(height: 12),
                      Center(
                        child: Text(
                          s.t('no_certificates'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: groupCertsByCourse(_certs!).length,
                    itemBuilder: (context, i) {
                      final group = groupCertsByCourse(_certs!)[i];
                      final c = pickCertLang(group, 'en');
                      return Card(
                        clipBehavior: Clip.antiAlias,
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: c.isValid
                                ? theme.colorScheme.primary
                                : Colors.grey,
                            child: const Icon(Icons.workspace_premium,
                                color: Colors.white),
                          ),
                          title: Text(
                            c.courseTitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            '${group.map((x) => x.lang == 'ar' ? 'العربية' : 'English').join(' / ')}  ·  ${c.certificateNumber}\n'
                            '${DateFormat('d MMM y', s.locale.languageCode).format(c.issuedAt)}'
                            '${c.isValid ? '' : ' · ${s.t('status_cancelled')}'}',
                          ),
                          isThreeLine: true,
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => CertificateViewScreen(cert: c, siblings: group),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
