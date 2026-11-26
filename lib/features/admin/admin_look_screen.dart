import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../core/remote_ui.dart';
import 'data/admin_tools_repo.dart';

const _presets = [
  '2563EB', '1E40AF', '0EA5E9', '0D9488', '16A34A', '65A30D',
  'F59E0B', 'EA580C', 'DC2626', 'DB2777', '7C3AED', '475569',
];

/// Admin: main brand color of the app (buttons, tabs, accents).
class AdminLookScreen extends StatefulWidget {
  const AdminLookScreen({super.key});

  @override
  State<AdminLookScreen> createState() => _AdminLookScreenState();
}

class _AdminLookScreenState extends State<AdminLookScreen> {
  final _hex = TextEditingController(text: '2563EB');
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    RemoteUi.load().then((_) {
      final h = RemoteUi.primaryHex?.replaceAll('#', '');
      if (h != null && h.isNotEmpty && mounted) setState(() => _hex.text = h);
    });
  }

  Color? get _color {
    final h = _hex.text.replaceAll('#', '').trim();
    if (h.length != 6) return null;
    final v = int.tryParse(h, radix: 16);
    return v == null ? null : Color(0xFF000000 | v);
  }

  Future<void> _save() async {
    final s = S.of(context);
    final c = _color;
    if (c == null) return;
    setState(() => _saving = true);
    try {
      final hex = _hex.text.replaceAll('#', '').trim().toUpperCase();
      RemoteUi.primaryHex = hex;
      RemoteUi.version.value++;
      await AdminToolsRepository.saveSetting('ui_look', {'primary': hex});
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(s.t('saved'))));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(s.t('generic_error'))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('ui_look'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(spacing: 12, runSpacing: 12, children: [
            for (final p in _presets)
              GestureDetector(
                onTap: () => setState(() => _hex.text = p),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Color(0xFF000000 | int.parse(p, radix: 16)),
                    shape: BoxShape.circle,
                    border: Border.all(
                        width: 3,
                        color: _hex.text.toUpperCase() == p
                            ? Colors.black87
                            : Colors.transparent),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 20),
          TextField(
            controller: _hex,
            onChanged: (_) => setState(() {}),
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              labelText: s.t('look_hex'),
              prefixIcon: Icon(Icons.circle, color: _color ?? Colors.grey),
            ),
          ),
          const SizedBox(height: 8),
          Text(s.t('look_note'), style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 20),
          FilledButton(
              onPressed: _saving ? null : _save, child: Text(s.t('save'))),
        ],
      ),
    );
  }
}
