import 'package:flutter/material.dart';

import '../../core/config.dart';
import '../../core/l10n.dart';
import '../certificates/certificate_card.dart';
import '../certificates/certificate_view_screen.dart';
import '../certificates/data/certificates_repo.dart';
import '../certificates/my_certificates_screen.dart';

/// Horizontal strip of the student's certificates (profile reference).
class CertsStrip extends StatefulWidget {
  const CertsStrip({super.key});

  @override
  State<CertsStrip> createState() => _CertsStripState();
}

class _CertsStripState extends State<CertsStrip> {
  List<Certificate> _certs = const [];
  final Map<String, Map<String, dynamic>?> _settings = {};

  @override
  void initState() {
    super.initState();
    CertificatesRepository.fetchMine().then((c) {
      final v = c.where((x) => x.isValid).toList();
      if (mounted) setState(() => _certs = v);
      for (final id in v.map((x) => x.courseId).toSet()) {
        CertificatesRepository.settingsFor(id).then((m) {
          if (mounted) setState(() => _settings[id] = m);
        }).catchError((_) {});
      }
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final groups = groupCertsByCourse(_certs);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(children: [
            Expanded(
                child: Text(s.t('my_certificates'),
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold))),
            TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const MyCertificatesScreen())),
              child: Text(s.t('see_all')),
            ),
          ]),
        ),
        if (_certs.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(s.t('pf_no_certs'),
                style: Theme.of(context).textTheme.bodySmall),
          )
        else
        SizedBox(
          height: 190,
          child: PageView.builder(
            controller: PageController(viewportFraction: .82),
            itemCount: groups.length,
            itemBuilder: (_, i) {
              final g = groups[i];
              final c = pickCertLang(g, 'en');
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) =>
                          CertificateViewScreen(cert: c, siblings: g))),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: Theme.of(context).dividerColor, width: 1),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: IgnorePointer(
                      child: FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: 960,
                          height: 680,
                          child: CertificateCard(
                            cert: c,
                            lang: c.lang,
                            verifyUrl: '${AppConfig.supabaseUrl}/rest/v1/rpc/'
                                'verify_certificate?apikey=${AppConfig.supabaseAnonKey}'
                                '&p_number=${c.certificateNumber}',
                            settings: _settings[c.courseId],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
