import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/l10n.dart';

/// All profile fields from doc section 8. Everything except the name is
/// optional; empty optional fields are stored as null.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _country = TextEditingController();
  final _governorate = TextEditingController();
  final _institution = TextEditingController();
  final _faculty = TextEditingController();
  final _specialization = TextEditingController();
  final _stage = TextEditingController();
  final _level = TextEditingController();
  final _group = TextEditingController();
  final _bio = TextEditingController();
  final _interests = TextEditingController();
  DateTime? _birthDate;
  bool _busy = false;

  SupabaseClient get _c => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _country.dispose();
    _governorate.dispose();
    _institution.dispose();
    _faculty.dispose();
    _specialization.dispose();
    _stage.dispose();
    _level.dispose();
    _group.dispose();
    _bio.dispose();
    _interests.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final uid = _c.auth.currentUser!.id;
    final row = await _c
        .from('profiles')
        .select()
        .eq('id', uid)
        .maybeSingle();
    if (row != null && mounted) {
      _name.text = row['full_name'] as String? ?? '';
      _phone.text = row['phone'] as String? ?? '';
      _country.text = row['country'] as String? ?? '';
      _governorate.text = row['governorate'] as String? ?? '';
      _institution.text = row['institution'] as String? ?? '';
      _faculty.text = row['faculty'] as String? ?? '';
      _specialization.text = row['specialization'] as String? ?? '';
      _stage.text = row['stage'] as String? ?? '';
      _level.text = row['level'] as String? ?? '';
      _group.text = row['group_name'] as String? ?? '';
      _bio.text = row['bio'] as String? ?? '';
      _interests.text = ((row['interests'] as List?) ?? const []).join(', ');
      _birthDate = row['birth_date'] != null
          ? DateTime.tryParse(row['birth_date'] as String)
          : null;
      setState(() {});
    }
  }

  String? _opt(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final uid = _c.auth.currentUser!.id;
      final tags = [
        for (final x in _interests.text.split(RegExp(r'[,،]')))
          if (x.trim().isNotEmpty) x.trim()
      ];
      if (tags.isNotEmpty) {
        // needs SQL part 25; ignored if the column does not exist yet
        try {
          await _c.from('profiles').update({'interests': tags}).eq('id', uid);
        } catch (_) {}
      }
      await _c.from('profiles').update({
        'full_name': _name.text.trim(),
        'phone': _opt(_phone),
        'country': _opt(_country),
        'governorate': _opt(_governorate),
        'institution': _opt(_institution),
        'faculty': _opt(_faculty),
        'specialization': _opt(_specialization),
        'stage': _opt(_stage),
        'level': _opt(_level),
        'group_name': _opt(_group),
        'bio': _opt(_bio),
        'birth_date': _birthDate == null
            ? null
            : DateFormat('yyyy-MM-dd').format(_birthDate!),
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', uid);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context).t('saved_ok'))),
        );
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context).t('generic_error'))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('edit_profile'))),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          TextField(
            controller: _name,
            decoration: InputDecoration(labelText: s.t('full_name')),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(labelText: s.t('phone_label')),
          ),
          const SizedBox(height: 16),
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () async {
              final now = DateTime.now();
              final d = await showDatePicker(
                context: context,
                initialDate: _birthDate ?? DateTime(now.year - 18),
                firstDate: DateTime(now.year - 100),
                lastDate: now,
              );
              if (d != null) setState(() => _birthDate = d);
            },
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: s.t('birth_date'),
                suffixIcon: _birthDate != null
                    ? IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => _birthDate = null),
                      )
                    : const Icon(Icons.calendar_today_outlined),
              ),
              child: Text(
                _birthDate == null
                    ? s.t('not_set')
                    : DateFormat('d MMM y', s.locale.languageCode)
                        .format(_birthDate!),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _country,
            decoration: InputDecoration(labelText: s.t('country')),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _governorate,
            decoration: InputDecoration(labelText: s.t('governorate')),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _institution,
            decoration: InputDecoration(labelText: s.t('institution')),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _specialization,
            decoration: InputDecoration(labelText: s.t('specialization')),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _bio,
            maxLines: 3,
            decoration: InputDecoration(labelText: s.t('bio')),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _interests,
            decoration: InputDecoration(labelText: s.t('pf_interests_hint')),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(s.t('save')),
          ),
        ],
      ),
    );
  }
}
