import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/l10n.dart';
import '../../core/tenant.dart';

SupabaseClient get _c => Supabase.instance.client;

/// Student: request access to a paid course by manual payment. No gateway:
/// the student pays outside the app, uploads the receipt, an admin approves.
class PaymentScreen extends StatefulWidget {
  const PaymentScreen({
    super.key,
    required this.courseId,
    required this.title,
    required this.price,
  });

  final String courseId;
  final String title;
  final double price;

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  final _coupon = TextEditingController();
  final _note = TextEditingController();
  String _instructions = '';
  double? _final;
  String? _couponMsg;
  String? _fileName;
  Uint8List? _bytes;
  bool _busy = false;
  Map<String, dynamic>? _existing;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _coupon.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final row = await _c
          .from('tenant_settings')
          .select('setting_value')
          .eq('tenant_id', TenantContext.id)
          .eq('setting_key', 'payment_instructions')
          .maybeSingle();
      final v = row?['setting_value'];
      if (v is Map && mounted) {
        setState(() => _instructions = (v['text'] ?? '').toString());
      }
    } catch (_) {}
    try {
      final rows = await _c
          .from('payment_requests')
          .select('status, admin_note, created_at')
          .eq('course_id', widget.courseId)
          .eq('user_id', _c.auth.currentUser!.id)
          .order('created_at', ascending: false)
          .limit(1);
      if (rows.isNotEmpty && mounted) {
        setState(() => _existing = Map<String, dynamic>.from(rows.first));
      }
    } catch (_) {}
  }

  Future<void> _applyCoupon() async {
    final s = S.of(context);
    final code = _coupon.text.trim();
    if (code.isEmpty) return;
    try {
      final r = await _c.rpc('validate_coupon',
          params: {'p_code': code, 'p_course': widget.courseId});
      final row = (r as List).isEmpty ? null : r.first as Map;
      if (row != null && row['ok'] == true) {
        setState(() {
          _final = (row['final_price'] as num).toDouble();
          _couponMsg = s.t('pay_coupon_ok');
        });
      } else {
        setState(() {
          _final = null;
          _couponMsg = s.t('pay_coupon_bad');
        });
      }
    } catch (_) {
      setState(() => _couponMsg = s.t('generic_error'));
    }
  }

  Future<void> _pick() async {
    final picked = await FilePicker.pickFiles();
    if (picked.isEmpty || !mounted) return;
    final f = picked.first;
    final b = await f.readAsBytes();
    if (!mounted) return;
    setState(() {
      _fileName = f.name;
      _bytes = b;
    });
  }

  Future<void> _submit() async {
    final s = S.of(context);
    if (_bytes == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.t('pay_need_receipt'))));
      return;
    }
    setState(() => _busy = true);
    try {
      final uid = _c.auth.currentUser!.id;
      final safe = (_fileName ?? 'receipt').replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final path = '$uid/${DateTime.now().millisecondsSinceEpoch}_$safe';
      await _c.storage.from('receipts').uploadBinary(path, _bytes!);
      await _c.rpc('submit_payment', params: {
        'p_course': widget.courseId,
        'p_coupon': _coupon.text.trim(),
        'p_receipt': path,
        'p_note': _note.text.trim(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.t('pay_sent'))));
      Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(s.t('pay_sql_needed'))));
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final shown = _final ?? widget.price;
    final pending = _existing?['status'] == 'pending';
    return Scaffold(
      appBar: AppBar(title: Text(s.t('pay_title'))),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 16),
        children: [
          Text(widget.title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.payments_outlined),
              title: Text(s.t('pay_amount')),
              trailing: Text(shown.toStringAsFixed(2),
                  style: Theme.of(context).textTheme.titleLarge),
            ),
          ),
          if (_existing != null)
            Card(
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(s.t('pay_status_${_existing!['status']}')),
                subtitle: (_existing!['admin_note'] ?? '').toString().isEmpty
                    ? null
                    : Text('${_existing!['admin_note']}'),
              ),
            ),
          if (_instructions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(s.t('pay_how'),
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            SelectableText(_instructions),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _coupon,
                  decoration: InputDecoration(
                      labelText: s.t('pay_coupon'),
                      prefixIcon: const Icon(Icons.local_offer_outlined)),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                  onPressed: _applyCoupon, child: Text(s.t('pay_apply'))),
            ],
          ),
          if (_couponMsg != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(_couponMsg!,
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _pick,
            icon: const Icon(Icons.upload_file),
            label: Text(_fileName ?? s.t('pay_attach')),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            maxLines: 2,
            decoration: InputDecoration(labelText: s.t('pay_note')),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: (_busy || pending) ? null : _submit,
            child: Text(_busy ? '...' : s.t('pay_send')),
          ),
        ],
      ),
    );
  }
}
