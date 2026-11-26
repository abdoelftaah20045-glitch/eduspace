import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/l10n.dart';

/// Public certificate verification (exec guide 17.2/17.3): anyone can type
/// a certificate number and see its status via the privacy-minimal
/// verify_certificate function — no login-dependent data.
class VerifyCertificateScreen extends StatefulWidget {
  const VerifyCertificateScreen({super.key});

  @override
  State<VerifyCertificateScreen> createState() =>
      _VerifyCertificateScreenState();
}

class _VerifyCertificateScreenState extends State<VerifyCertificateScreen> {
  final _number = TextEditingController();
  bool _loading = false;
  Map<String, dynamic>? _result;

  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final s = S.of(context);
    final number = _number.text.trim();
    if (number.isEmpty) return;
    setState(() {
      _loading = true;
      _result = null;
    });
    try {
      final result = await Supabase.instance.client
          .rpc('verify_certificate', params: {'p_number': number});
      if (mounted) {
        setState(() =>
            _result = result is Map ? Map<String, dynamic>.from(result) : null);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(s.t('generic_error'))));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final result = _result;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('verify_certificate_title'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _number,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              labelText: s.t('cert_number'),
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => _verify(),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _loading ? null : _verify,
            icon: const Icon(Icons.verified_outlined),
            label: Text(s.t('verify_action')),
          ),
          const SizedBox(height: 24),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (result != null)
            _resultCard(result, s, theme),
        ],
      ),
    );
  }

  Widget _resultCard(Map<String, dynamic> result, S s, ThemeData theme) {
    final status = result['status'] as String? ?? 'not_found';
    final found = status != 'not_found';
    final valid = status == 'valid';
    final issuedRaw = result['issued_at'] as String?;
    String issued = '';
    if (issuedRaw != null && issuedRaw.isNotEmpty) {
      final parsed = DateTime.tryParse(issuedRaw);
      if (parsed != null) issued = DateFormat.yMMMd().format(parsed.toLocal());
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: valid
                    ? const Color(0xFF16A34A)
                    : const Color(0xFFDC2626),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(children: [
                Icon(
                  valid
                      ? Icons.verified
                      : found
                          ? Icons.gpp_bad_outlined
                          : Icons.search_off,
                  color: Colors.white,
                  size: 48,
                ),
                const SizedBox(height: 8),
                Text(
                  !found
                      ? s.t('cert_not_found')
                      : valid
                          ? s.t('cert_valid')
                          : s.t('status_cancelled'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(
                      color: Colors.white, fontWeight: FontWeight.w800),
                ),
              ]),
            ),
            if (found) ...[
              const Divider(height: 24),
              _row(s.t('student'), result['student_name'] as String? ?? ''),
              _row(s.t('tab_courses'), result['course_title'] as String? ?? ''),
              _row(s.t('hours_label'), '${result['hours'] ?? 0}'),
              if (issued.isNotEmpty) _row(s.t('issued_on'), issued),
              _row('Language', result['lang'] == 'en' ? 'English' : 'العربية'),
              _row(s.t('cert_number'),
                  result['certificate_number'] as String? ?? ''),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
