import '../../core/admin_search.dart';
import '../../core/search_norm.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/l10n.dart';
import '../../core/tenant.dart';

SupabaseClient get _c => Supabase.instance.client;

/// Admin: payment requests (approve/reject), coupons and payment instructions.
class AdminPaymentsScreen extends StatelessWidget {
  const AdminPaymentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(s.t('admin_payments')),
          bottom: TabBar(tabs: [
            Tab(text: s.t('admin_pay_requests')),
            Tab(text: s.t('pay_coupon')),
            Tab(text: s.t('pay_how')),
            Tab(text: s.t('admin_subs')),
          ]),
        ),
        body: const TabBarView(children: [
          _RequestsTab(),
          _CouponsTab(),
          _InstructionsTab(),
          _SubsTab(),
        ]),
      ),
    );
  }
}

class _RequestsTab extends StatefulWidget {
  const _RequestsTab();
  @override
  State<_RequestsTab> createState() => _RequestsTabState();
}

class _RequestsTabState extends State<_RequestsTab> {
  List<Map<String, dynamic>> _rows = [];
  String _q = '';
  bool _loading = true;
  bool _error = false;
  String _errText = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final rows = await _c
          .from('payment_requests')
          .select(
              'id, amount, coupon_code, receipt_path, note, status, admin_note, created_at, user_id, courses(title)')
          .eq('tenant_id', TenantContext.id)
          .order('created_at', ascending: false)
          .limit(100)
          .timeout(const Duration(seconds: 20));
      final ids = rows.map((r) => r['user_id']).toSet().toList();
      final names = <String, String>{};
      if (ids.isNotEmpty) {
        final ps = await _c
            .from('profiles')
            .select('id, full_name, email')
            .inFilter('id', ids)
            .timeout(const Duration(seconds: 20));
        for (final p in ps) {
          names[p['id'] as String] =
              (p['full_name'] ?? p['email'] ?? '').toString();
        }
      }
      _rows = [
        for (final r in rows)
          {...Map<String, dynamic>.from(r), 'who': names[r['user_id']] ?? ''}
      ];
    } catch (e) {
      _error = true;
      _errText = e.toString();
      if (_errText.length > 200) _errText = _errText.substring(0, 200);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _receipt(String path) async {
    try {
      final url = await _c.storage.from('receipts').createSignedUrl(path, 600);
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Future<void> _decide(String id, bool ok) async {
    final s = S.of(context);
    final note = TextEditingController();
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ok ? s.t('admin_pay_approve') : s.t('admin_pay_reject')),
        content: TextField(
            controller: note,
            decoration: InputDecoration(labelText: s.t('pay_note'))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(s.t('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(s.t('save'))),
        ],
      ),
    );
    if (go != true) return;
    try {
      await _c.rpc('review_payment', params: {
        'p_id': id,
        'p_approve': ok,
        'p_note': note.text.trim(),
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(s.t('pay_sql_needed'))));
      }
    }
    _load();
  }

  Future<void> _refund(String id) async {
    final s = S.of(context);
    final note = TextEditingController();
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.t('admin_pay_refund')),
        content: TextField(
            controller: note,
            decoration: InputDecoration(labelText: s.t('pay_note'))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(s.t('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(s.t('admin_pay_refund'))),
        ],
      ),
    );
    if (go != true) return;
    try {
      await _c.rpc('refund_payment',
          params: {'p_id': id, 'p_reason': note.text.trim()});
    } catch (e) {
      if (mounted) {
        final t = '$e';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                '${s.t('pay_sql_needed')}\n${t.length > 120 ? t.substring(0, 120) : t}')));
      }
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error) {
      return Center(
          child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_errText.isEmpty ? s.t('generic_error') : _errText,
              textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(s.t('pay_sql_needed'), textAlign: TextAlign.center),
          TextButton(onPressed: _load, child: Text(s.t('retry'))),
        ]),
      ));
    }
    if (_rows.isEmpty) return Center(child: Text(s.t('admin_pay_none')));
    final shown = _rows.where((r) => matchesAny(_q, r)).toList();
    return Column(children: [
      AdminSearchField(onChanged: (v) => setState(() => _q = v)),
      Expanded(child: RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 16),
        itemCount: shown.length,
        itemBuilder: (_, i) {
          final r = shown[i];
          final pending = r['status'] == 'pending';
          final course = (r['courses'] is Map) ? r['courses']['title'] : '';
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${r['who']}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text('$course'),
                  Text(
                      '${(r['amount'] as num).toStringAsFixed(2)}'
                      '${r['coupon_code'] != null ? '  ·  ${r['coupon_code']}' : ''}'),
                  if ((r['note'] ?? '').toString().isNotEmpty)
                    Text('${r['note']}'),
                  const SizedBox(height: 4),
                  Text(s.t('pay_status_${r['status']}'),
                      style: Theme.of(context).textTheme.bodySmall),
                  Wrap(spacing: 8, children: [
                    if (r['receipt_path'] != null)
                      TextButton.icon(
                          onPressed: () => _receipt(r['receipt_path']),
                          icon: const Icon(Icons.receipt_long),
                          label: Text(s.t('admin_pay_receipt'))),
                    if (r['status'] == 'approved')
                      OutlinedButton(
                          onPressed: () => _refund(r['id']),
                          child: Text(s.t('admin_pay_refund'))),
                    if (pending) ...[
                      FilledButton(
                          onPressed: () => _decide(r['id'], true),
                          child: Text(s.t('admin_pay_approve'))),
                      OutlinedButton(
                          onPressed: () => _decide(r['id'], false),
                          child: Text(s.t('admin_pay_reject'))),
                    ],
                  ]),
                ],
              ),
            ),
          );
        },
      ),
    )),
    ]);
  }
}

class _CouponsTab extends StatefulWidget {
  const _CouponsTab();
  @override
  State<_CouponsTab> createState() => _CouponsTabState();
}

class _CouponsTabState extends State<_CouponsTab> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await _c
          .from('coupons')
          .select()
          .eq('tenant_id', TenantContext.id)
          .order('created_at', ascending: false)
          .timeout(const Duration(seconds: 20));
      _rows = [for (final r in rows) Map<String, dynamic>.from(r)];
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _add() async {
    final s = S.of(context);
    final code = TextEditingController();
    final pct = TextEditingController();
    final max = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.t('admin_coupon_new')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: code,
              decoration: InputDecoration(labelText: s.t('pay_coupon'))),
          TextField(
              controller: pct,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: s.t('admin_coupon_pct'))),
          TextField(
              controller: max,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: s.t('admin_coupon_max'))),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(s.t('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(s.t('save'))),
        ],
      ),
    );
    final p = double.tryParse(pct.text.trim());
    if (ok != true || code.text.trim().isEmpty || p == null) return;
    try {
      await _c.from('coupons').insert({
        'tenant_id': TenantContext.id,
        'code': code.text.trim(),
        'percent_off': p.clamp(0, 100),
        'max_uses': int.tryParse(max.text.trim()),
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(s.t('pay_sql_needed'))));
      }
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return Scaffold(
      floatingActionButton:
          FloatingActionButton(onPressed: _add, child: const Icon(Icons.add)),
      body: ListView(
        children: [
          for (final r in _rows)
            ListTile(
              leading: const Icon(Icons.local_offer_outlined),
              title: Text('${r['code']}  ·  ${r['percent_off'] ?? 0}%'),
              subtitle: Text('${r['uses']}/${r['max_uses'] ?? '∞'}'),
              trailing: Switch(
                value: r['active'] == true,
                onChanged: (v) async {
                  await _c
                      .from('coupons')
                      .update({'active': v}).eq('id', r['id']);
                  _load();
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _InstructionsTab extends StatefulWidget {
  const _InstructionsTab();
  @override
  State<_InstructionsTab> createState() => _InstructionsTabState();
}

class _InstructionsTabState extends State<_InstructionsTab> {
  final _text = TextEditingController();

  @override
  void initState() {
    super.initState();
    _c
        .from('tenant_settings')
        .select('setting_value')
        .eq('tenant_id', TenantContext.id)
        .eq('setting_key', 'payment_instructions')
        .maybeSingle()
        .then((row) {
      final v = row?['setting_value'];
      if (v is Map && mounted) _text.text = (v['text'] ?? '').toString();
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        TextField(
            controller: _text,
            maxLines: 6,
            decoration: InputDecoration(
                labelText: s.t('pay_how'),
                helperText: s.t('admin_pay_instr_hint'),
                border: const OutlineInputBorder())),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () async {
            String msg;
            try {
              await _c.from('tenant_settings').upsert({
                'tenant_id': TenantContext.id,
                'setting_key': 'payment_instructions',
                'setting_value': {'text': _text.text.trim()},
              });
              msg = s.t('saved_ok');
            } catch (_) {
              msg = s.t('generic_error');
            }
            if (context.mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(msg)));
            }
          },
          child: Text(s.t('save')),
        ),
      ]),
    );
  }
}

class _SubsTab extends StatefulWidget {
  const _SubsTab();
  @override
  State<_SubsTab> createState() => _SubsTabState();
}

class _SubsTabState extends State<_SubsTab> {
  List<Map<String, dynamic>> _plans = [];
  List<Map<String, dynamic>> _subs = [];
  bool _loading = true;
  String _err = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _err = '';
    });
    try {
      final plans = await _c
          .from('subscription_plans')
          .select('id, name, months, price, currency, active')
          .eq('tenant_id', TenantContext.id)
          .order('created_at');
      final subs = await _c
          .from('subscriptions')
          .select('id, status, ends_at, user_id, subscription_plans(name)')
          .eq('tenant_id', TenantContext.id)
          .order('created_at', ascending: false)
          .limit(100);
      final ids = subs.map((r) => r['user_id']).toSet().toList();
      final names = <String, String>{};
      if (ids.isNotEmpty) {
        final ps = await _c
            .from('profiles')
            .select('id, full_name, email')
            .inFilter('id', ids);
        for (final p in ps) {
          names[p['id'] as String] =
              (p['full_name'] ?? p['email'] ?? '').toString();
        }
      }
      _plans = [for (final r in plans) Map<String, dynamic>.from(r)];
      _subs = [
        for (final r in subs)
          {...Map<String, dynamic>.from(r), 'who': names[r['user_id']] ?? ''}
      ];
    } catch (e) {
      final t = '$e';
      _err = t.length > 200 ? t.substring(0, 200) : t;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _addPlan() async {
    final s = S.of(context);
    final name = TextEditingController();
    final months = TextEditingController(text: '1');
    final price = TextEditingController(text: '0');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.t('admin_plan_add')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: name,
              decoration: InputDecoration(labelText: s.t('admin_plan_name'))),
          TextField(
              controller: months,
              keyboardType: TextInputType.number,
              decoration:
                  InputDecoration(labelText: s.t('admin_plan_months'))),
          TextField(
              controller: price,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: s.t('admin_plan_price'))),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(s.t('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(s.t('save'))),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    try {
      await _c.from('subscription_plans').insert({
        'tenant_id': TenantContext.id,
        'name': name.text.trim(),
        'months': int.tryParse(months.text.trim()) ?? 1,
        'price': double.tryParse(price.text.trim()) ?? 0,
      });
    } catch (e) {
      _toast('$e');
    }
    _load();
  }

  Future<void> _grant(Map<String, dynamic> plan) async {
    final s = S.of(context);
    final email = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${s.t('admin_plan_grant')}: ${plan['name']}'),
        content: TextField(
            controller: email,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(labelText: s.t('email'))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(s.t('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(s.t('admin_plan_grant'))),
        ],
      ),
    );
    if (ok != true || email.text.trim().isEmpty) return;
    try {
      await _c.rpc('grant_subscription',
          params: {'p_email': email.text.trim(), 'p_plan': plan['id']});
    } catch (e) {
      _toast('${s.t('pay_sql_needed')} $e');
    }
    _load();
  }

  Future<void> _cancel(String id) async {
    try {
      await _c.rpc('cancel_subscription', params: {'p_id': id});
    } catch (e) {
      _toast('$e');
    }
    _load();
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(m.length > 160 ? m.substring(0, 160) : m)));
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_err.isNotEmpty) {
      return Center(
          child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_err, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(s.t('pay_sql_needed'), textAlign: TextAlign.center),
          TextButton(onPressed: _load, child: Text(s.t('retry'))),
        ]),
      ));
    }
    return ListView(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 16), children: [
      Row(children: [
        Expanded(
            child: Text(s.t('admin_plans'),
                style: const TextStyle(fontWeight: FontWeight.bold))),
        FilledButton.icon(
            onPressed: _addPlan,
            icon: const Icon(Icons.add),
            label: Text(s.t('admin_plan_add'))),
      ]),
      for (final p in _plans)
        Card(
          child: ListTile(
            title: Text('${p['name']}'),
            subtitle: Text(
                '${p['months']} ${s.t('admin_plan_months')} - ${p['price']} ${p['currency']}'),
            trailing: OutlinedButton(
                onPressed: () => _grant(p),
                child: Text(s.t('admin_plan_grant'))),
          ),
        ),
      const SizedBox(height: 12),
      Text(s.t('admin_subs'),
          style: const TextStyle(fontWeight: FontWeight.bold)),
      for (final r in _subs)
        Card(
          child: ListTile(
            title: Text('${r['who']}'),
            subtitle: Text(
                '${(r['subscription_plans'] is Map) ? r['subscription_plans']['name'] : ''} - ${r['status']} - ${'${r['ends_at']}'.split('T').first}'),
            trailing: r['status'] == 'active'
                ? TextButton(
                    onPressed: () => _cancel(r['id'] as String),
                    child: Text(s.t('cancel')))
                : null,
          ),
        ),
    ]);
  }
}
