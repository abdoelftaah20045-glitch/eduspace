import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/l10n.dart';

/// About (spec S50): version, terms, privacy, licenses, contact.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  Future<void> _mail(String to) =>
      launchUrl(Uri.parse('mailto:$to'), mode: LaunchMode.externalApplication);

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('about_app'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFF2196F3), Color(0xFF00ACC1)]),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(Icons.school, color: Colors.white, size: 46),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(s.t('app_name'),
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
          ),
          Center(child: Text('${s.t('app_version')} 0.3.0')),
          const SizedBox(height: 8),
          Center(child: Text(s.t('about_legalese'), textAlign: TextAlign.center)),
          const SizedBox(height: 20),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: Text(s.t('terms_label')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showDialog<void>(
              context: context,
              builder: (_) => AlertDialog(
                title: Text(s.t('terms_label')),
                content: Text(s.t('about_legalese')),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: Text(s.t('privacy_label')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showDialog<void>(
              context: context,
              builder: (_) => AlertDialog(
                title: Text(s.t('privacy_label')),
                content: Text(s.t('about_legalese')),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.gavel_outlined),
            title: const Text('Licenses'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showLicensePage(
                context: context, applicationName: s.t('app_name')),
          ),
          ListTile(
            leading: const Icon(Icons.mail_outline),
            title: Text(s.t('contact_us')),
            subtitle: const Text('abdoelftaah20045@gmail.com'),
            onTap: () => _mail('abdoelftaah20045@gmail.com'),
          ),
        ],
      ),
    );
  }
}
