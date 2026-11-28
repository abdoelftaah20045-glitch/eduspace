import 'package:flutter/material.dart';

import '../../core/remote_ui.dart';
import 'data/admin_tools_repo.dart';

/// Admin: edit the in-app animated splash (colors, slogan, speed, style).
/// Takes effect on the next app launch. The Android launch screen shown
/// before the app starts is native and only changes with a full release.
class AdminSplashScreen extends StatefulWidget {
  const AdminSplashScreen({super.key});

  @override
  State<AdminSplashScreen> createState() => _AdminSplashScreenState();
}

class _AdminSplashScreenState extends State<AdminSplashScreen> {
  late final TextEditingController _bg1;
  late final TextEditingController _bg2;
  late final TextEditingController _sc;
  late final TextEditingController _slogan;
  bool _show = true;
  double _secs = 2.8;
  String _anim = 'drop';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final m = RemoteUi.splash;
    _bg1 = TextEditingController(text: '${m['bg1'] ?? '#EFF6FF'}');
    _bg2 = TextEditingController(text: '${m['bg2'] ?? '#DBEAFE'}');
    _sc = TextEditingController(text: '${m['slogan_color'] ?? '#D96A43'}');
    _slogan = TextEditingController(text: '${m['slogan'] ?? ''}');
    _show = m['show_slogan'] != false;
    _secs = (m['seconds'] is num) ? (m['seconds'] as num).toDouble().clamp(1.5, 8.0) : 2.8;
    _anim = '${m['anim'] ?? 'drop'}';
    for (final c in [_bg1, _bg2, _sc]) {
      c.addListener(() => setState(() {}));
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final m = <String, dynamic>{
      'bg1': _bg1.text.trim(),
      'bg2': _bg2.text.trim(),
      'slogan_color': _sc.text.trim(),
      'slogan': _slogan.text.trim(),
      'show_slogan': _show,
      'seconds': _secs,
      'anim': _anim,
    };
    try {
      await AdminToolsRepository.saveSetting('ui_splash', m);
      RemoteUi.splash = m;
      await RemoteUi.saveSplashCache();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم الحفظ. هيظهر في المرة الجاية اللي التطبيق يفتح فيها')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر الحفظ: $e')));
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  Widget _f(TextEditingController c, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
            controller: c,
            decoration: InputDecoration(labelText: label, border: const OutlineInputBorder())),
      );

  @override
  Widget build(BuildContext context) {
    final c1 = RemoteUi.hexColor(_bg1.text) ?? const Color(0xFFEFF6FF);
    final c2 = RemoteUi.hexColor(_bg2.text) ?? const Color(0xFFDBEAFE);
    final sc = RemoteUi.hexColor(_sc.text) ?? const Color(0xFFD96A43);
    return Scaffold(
      appBar: AppBar(title: const Text('شاشة البداية'), actions: [
        TextButton(onPressed: _saving ? null : _save, child: const Text('حفظ')),
      ]),
      body: ListView(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 16), children: [
        Container(
          height: 140,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(colors: [c1, c2]),
          ),
          child: Text(
              _show ? (_slogan.text.trim().isEmpty ? 'الشعار الافتراضي' : _slogan.text.trim()) : '',
              style: TextStyle(color: sc, fontSize: 22, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: 16),
        _f(_bg1, 'لون الخلفية 1 (مثال #EFF6FF)'),
        _f(_bg2, 'لون الخلفية 2'),
        _f(_sc, 'لون الشعار'),
        _f(_slogan, 'نص الشعار (فاضي = الافتراضي)'),
        SwitchListTile(
            value: _show,
            title: const Text('إظهار الشعار'),
            onChanged: (v) => setState(() => _show = v)),
        ListTile(
          title: Text('مدة الأنيميشن: ${_secs.toStringAsFixed(1)} ثانية'),
          subtitle: Slider(
              value: _secs,
              min: 1.5,
              max: 8,
              divisions: 13,
              onChanged: (v) => setState(() => _secs = v)),
        ),
        DropdownButtonFormField<String>(
          initialValue: _anim,
          decoration: const InputDecoration(labelText: 'شكل الدخول'),
          items: const [
            DropdownMenuItem(value: 'drop', child: Text('نزول بارتداد')),
            DropdownMenuItem(value: 'fade', child: Text('ظهور هادئ')),
          ],
          onChanged: (v) => setState(() => _anim = v ?? 'drop'),
        ),
        const SizedBox(height: 12),
        const Text(
            'ملاحظة: شاشة أندرويد الأولى (قبل فتح التطبيق) ثابتة ومش بتتغير إلا بإصدار كامل.',
            style: TextStyle(fontSize: 12)),
      ]),
    );
  }
}
