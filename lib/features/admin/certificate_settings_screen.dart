import '../../core/cached_avatar.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/l10n.dart';
import '../../core/tenant.dart';
import 'data/admin_repo.dart';

SupabaseClient get _c => Supabase.instance.client;

/// Admin: certificate template (uploaded design), issue rules and manual
/// issue. Scope: all courses, or one course (overrides the global one).
class CertificateSettingsScreen extends StatefulWidget {
  const CertificateSettingsScreen({super.key});

  @override
  State<CertificateSettingsScreen> createState() =>
      _CertificateSettingsScreenState();
}

class _CertificateSettingsScreenState extends State<CertificateSettingsScreen> {
  List<Map<String, dynamic>> _courses = [];
  String? _courseId; // null = all courses
  bool _loading = true;
  bool _enabled = true;
  String _template = '';
  String _color = 'dark';
  String _position = 'center';
  final _minExam = TextEditingController(text: '0');
  final _email = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    AdminRepository.fetchAllCourses().then((v) {
      if (mounted) setState(() => _courses = v);
    }).catchError((_) {});
    _load();
  }

  @override
  void dispose() {
    _minExam.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      var q = _c
          .from('certificate_settings')
          .select()
          .eq('tenant_id', TenantContext.id);
      q = _courseId == null
          ? q.filter('course_id', 'is', null)
          : q.eq('course_id', _courseId!);
      final rows = await q.limit(1);
      final r = rows.isEmpty ? null : rows.first;
      _enabled = r?['enabled'] != false;
      _template = (r?['template_url'] ?? '').toString();
      _color = (r?['text_color'] ?? 'dark').toString();
      _position = (r?['text_position'] ?? 'center').toString();
      _minExam.text = '${r?['min_exam_percent'] ?? 0}';
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  void _toast(String key) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(S.of(context).t(key))));
  }

  Future<void> _pickTemplate() async {
    final picked = await FilePicker.pickFiles();
    if (picked.isEmpty || !mounted) return;
    final f = picked.first;
    setState(() => _busy = true);
    try {
      final url = await AdminRepository.uploadCourseCover(
          fileName: f.name, bytes: await f.readAsBytes());
      setState(() => _template = url);
    } catch (_) {
      _toast('generic_error');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final values = {
        'tenant_id': TenantContext.id,
        'course_id': _courseId,
        'enabled': _enabled,
        'template_url': _template.isEmpty ? null : _template,
        'text_color': _color,
        'text_position': _position,
        'min_exam_percent': double.tryParse(_minExam.text.trim()) ?? 0,
        'updated_at': DateTime.now().toIso8601String(),
      };
      var q = _c
          .from('certificate_settings')
          .select('id')
          .eq('tenant_id', TenantContext.id);
      q = _courseId == null
          ? q.filter('course_id', 'is', null)
          : q.eq('course_id', _courseId!);
      final ex = await q.limit(1);
      if (ex.isEmpty) {
        await _c.from('certificate_settings').insert(values);
      } else {
        await _c
            .from('certificate_settings')
            .update(values)
            .eq('id', ex.first['id']);
      }
      _toast('saved_ok');
    } catch (_) {
      _toast('pay_sql_needed');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _issue() async {
    if (_courseId == null || _email.text.trim().isEmpty) {
      _toast('cert_issue_need');
      return;
    }
    setState(() => _busy = true);
    try {
      await _c.rpc('admin_issue_certificate',
          params: {'p_email': _email.text.trim(), 'p_course': _courseId});
      _toast('cert_issued');
    } catch (_) {
      _toast('generic_error');
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('cert_settings'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String?>(
            value: _courseId,
            decoration: InputDecoration(labelText: s.t('cert_scope')),
            items: [
              DropdownMenuItem(value: null, child: Text(s.t('cert_all_courses'))),
              for (final c in _courses)
                DropdownMenuItem(
                    value: c['id'] as String,
                    child: Text('${c['title']}', overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) {
              _courseId = v;
              _load();
            },
          ),
          if (_loading)
            const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()))
          else ...[
            SwitchListTile(
              value: _enabled,
              onChanged: (v) => setState(() => _enabled = v),
              title: Text(s.t('cert_enabled')),
            ),
            const SizedBox(height: 8),
            Text(s.t('cert_template'),
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(s.t('cert_template_hint'),
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            if (_template.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: AspectRatio(
                  aspectRatio: 960 / 680,
                  child: CachedImage(_template, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const Center(child: Icon(Icons.broken_image))),
                ),
              ),
            Wrap(spacing: 8, children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : _pickTemplate,
                icon: const Icon(Icons.upload),
                label: Text(s.t('cert_upload_template')),
              ),
              if (_template.isNotEmpty)
                TextButton(
                    onPressed: () => setState(() => _template = ''),
                    child: Text(s.t('cert_use_default'))),
            ]),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _color,
              decoration: InputDecoration(labelText: s.t('cert_text_color')),
              items: [
                DropdownMenuItem(value: 'dark', child: Text(s.t('cert_dark'))),
                DropdownMenuItem(value: 'light', child: Text(s.t('cert_light'))),
              ],
              onChanged: (v) => setState(() => _color = v ?? 'dark'),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _position,
              decoration: InputDecoration(labelText: s.t('cert_text_pos')),
              items: [
                DropdownMenuItem(value: 'top', child: Text(s.t('cert_top'))),
                DropdownMenuItem(value: 'center', child: Text(s.t('cert_center'))),
                DropdownMenuItem(value: 'low', child: Text(s.t('cert_low'))),
              ],
              onChanged: (v) => setState(() => _position = v ?? 'center'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _minExam,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                  labelText: s.t('cert_min_exam'),
                  helperText: s.t('cert_rule_hint')),
            ),
            const SizedBox(height: 16),
            FilledButton(
                onPressed: _busy ? null : _save, child: Text(s.t('save'))),
            const Divider(height: 40),
            Text(s.t('cert_manual'),
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(labelText: s.t('email')),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
                onPressed: _busy ? null : _issue,
                child: Text(s.t('cert_issue_now'))),
          ],
        ],
      ),
    );
  }
}
