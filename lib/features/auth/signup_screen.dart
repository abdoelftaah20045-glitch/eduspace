import 'package:flutter/material.dart';
import '../../core/password_field.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_state.dart';
import '../../core/config.dart';
import '../../core/l10n.dart';
import 'verify_email_screen.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _phone = TextEditingController();
  final _country = TextEditingController();
  final _governorate = TextEditingController();
  final _institution = TextEditingController();
  DateTime? _birth;
  bool _agree = false;
  bool _busy = false;
  String? _error;

  Future<void> _signup() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_agree) {
      setState(() => _error = S.of(context).t('must_agree_terms'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await Supabase.instance.client.auth.signUp(
        email: _email.text.trim(),
        password: _password.text,
        emailRedirectTo: kAuthRedirectUrl,
        data: {
          'full_name': _name.text.trim(),
          'locale': AppState.instance.locale.value.languageCode,
          if (_phone.text.trim().isNotEmpty) 'phone': _phone.text.trim(),
          if (_country.text.trim().isNotEmpty) 'country': _country.text.trim(),
          if (_governorate.text.trim().isNotEmpty)
            'governorate': _governorate.text.trim(),
          if (_institution.text.trim().isNotEmpty)
            'institution': _institution.text.trim(),
          if (_birth != null)
            'birth_date': _birth!.toIso8601String().substring(0, 10),
        },
      );
      if (!mounted) return;
      // Supabase hides duplicates: an existing email returns a fake success
      // with an empty identities list and sends nothing.
      final ids = res.user?.identities;
      if (res.session == null && ids != null && ids.isEmpty) {
        setState(() => _error = S.of(context).t('signup_exists'));
        return;
      }
      if (res.session != null) {
        // Email confirmation is off: the AuthGate stream already switches
        // to the home screen underneath, so just close this pushed route.
        Navigator.of(context).popUntil((route) => route.isFirst);
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const VerifyEmailScreen()),
        );
      }
    } on AuthException catch (e) {
      final m = e.message.toLowerCase();
      setState(() => _error = (m.contains('already') && m.contains('regist'))
          ? S.of(context).t('signup_exists')
          : e.message);
    } catch (_) {
      setState(() => _error = S.of(context).t('generic_error'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('signup'))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Icon(Icons.person_add_alt_rounded,
                      size: 36,
                      color: Theme.of(context).colorScheme.onPrimary),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                s.t('promo_title'),
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _name,
                decoration: InputDecoration(
                  labelText: s.t('full_name'),
                  prefixIcon: const Icon(Icons.person_outline),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? s.t('required_field') : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: s.t('email'),
                  prefixIcon: const Icon(Icons.mail_outline),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return s.t('required_field');
                  if (!v.contains('@')) return s.t('invalid_email');
                  return null;
                },
              ),
              const SizedBox(height: 16),
              PasswordField(
                controller: _password,
                label: s.t('password'),
                icon: Icons.lock_outline,
                validator: (v) =>
                    (v == null || v.length < 6) ? s.t('password_short') : null,
              ),
              const SizedBox(height: 16),
              PasswordField(
                controller: _confirm,
                label: s.t('confirm_password'),
                icon: Icons.lock_reset,
                validator: (v) =>
                    v != _password.text ? s.t('passwords_mismatch') : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: '${s.t('phone_label')} (${s.t('optional')})',
                  prefixIcon: const Icon(Icons.phone_outlined),
                ),
              ),
              const SizedBox(height: 16),
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _birth ?? DateTime(2000),
                    firstDate: DateTime(1940),
                    lastDate: DateTime.now(),
                  );
                  if (d != null) setState(() => _birth = d);
                },
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: '${s.t('birth_date')} (${s.t('optional')})',
                    prefixIcon: const Icon(Icons.cake_outlined),
                  ),
                  child: Text(_birth == null
                      ? ''
                      : _birth!.toIso8601String().substring(0, 10)),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _country,
                      decoration: InputDecoration(
                        labelText: s.t('country'),
                        prefixIcon: const Icon(Icons.public),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _governorate,
                      decoration: InputDecoration(
                        labelText: s.t('governorate'),
                        prefixIcon: const Icon(Icons.location_city_outlined),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _institution,
                decoration: InputDecoration(
                  labelText: s.t('institution'),
                  prefixIcon: const Icon(Icons.school_outlined),
                ),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _agree,
                onChanged: (v) => setState(() => _agree = v ?? false),
                title: Text(s.t('agree_terms')),
              ),
              const SizedBox(height: 16),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              FilledButton(
                onPressed: _busy ? null : _signup,
                child: _busy
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(s.t('signup')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
