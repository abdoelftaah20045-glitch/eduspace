import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/l10n.dart';
import 'auth_gate.dart';

/// First-run onboarding (reference: Arabic welcome screens): 3 illustrated
/// pages with dots, Next/Skip, and a final Start button.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  static Future<bool> seen() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('onboarding_seen') ?? false;
  }

  static Future<void> markSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_seen', true);
  }

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pager = PageController();
  int _page = 0;

  void _finish() {
    OnboardingScreen.markSeen();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const AuthGate()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final scheme = Theme.of(context).colorScheme;
    final pages = [
      (Icons.lightbulb_outline, s.t('onboarding_1_title'), s.t('onboarding_1_sub')),
      (Icons.groups_outlined, s.t('onboarding_2_title'), s.t('onboarding_2_sub')),
      (Icons.emoji_events_outlined, s.t('onboarding_3_title'), s.t('onboarding_3_sub')),
    ];
    final last = _page == pages.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: AlignmentDirectional.topEnd,
              child: TextButton(
                onPressed: _finish,
                child: Text(s.t('skip')),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pager,
                itemCount: pages.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, i) {
                  final (icon, title, sub) = pages[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 200,
                          height: 200,
                          decoration: BoxDecoration(
                            color: scheme.primary.withValues(alpha: .1),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Container(
                              width: 130,
                              height: 130,
                              decoration: BoxDecoration(
                                color: scheme.primary,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: scheme.primary.withValues(alpha: .35),
                                    blurRadius: 30,
                                    offset: const Offset(0, 14),
                                  ),
                                ],
                              ),
                              child: Icon(icon,
                                  size: 64, color: scheme.onPrimary),
                            ),
                          ),
                        ),
                        const SizedBox(height: 40),
                        Text(
                          title,
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          sub,
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  height: 1.6),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                pages.length,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: i == _page ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: i == _page
                        ? scheme.primary
                        : scheme.primary.withValues(alpha: .25),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  if (!last)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _finish,
                        child: Text(s.t('skip')),
                      ),
                    ),
                  if (!last) const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: () {
                        if (last) {
                          _finish();
                        } else {
                          _pager.nextPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOut,
                          );
                        }
                      },
                      child:
                          Text(last ? s.t('start_journey') : s.t('next')),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
