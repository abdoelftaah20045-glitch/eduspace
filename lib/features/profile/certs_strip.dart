import 'package:flutter/material.dart';

import '../../core/l10n.dart';
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

  @override
  void initState() {
    super.initState();
    CertificatesRepository.fetchMine().then((c) {
      if (mounted) setState(() => _certs = c.where((x) => x.isValid).toList());
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    if (_certs.isEmpty) return const SizedBox.shrink();
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
        SizedBox(
          height: 112,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: _certs.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final c = _certs[i];
              return InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => CertificateViewScreen(cert: c))),
                child: Container(
                  width: 170,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Color(0xFF0D2A57), Color(0xFF1B4A8F)]),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFC9A227), width: 1.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.workspace_premium,
                          color: Color(0xFFC9A227), size: 26),
                      const Spacer(),
                      Text(c.courseTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold)),
                      Text(c.certificateNumber,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 10)),
                    ],
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
