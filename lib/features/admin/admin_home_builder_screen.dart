import 'package:flutter/material.dart';

import '../../core/remote_ui.dart';
import '../home/home_blocks.dart';
import 'auto_category.dart';
import 'data/admin_tools_repo.dart';

/// Admin: build the Home screen from blocks (banner, tiles, course rows,
/// categories, text). Saved to tenant_settings key ui_home; the app reads it.
class AdminHomeBuilderScreen extends StatefulWidget {
  const AdminHomeBuilderScreen({super.key});

  @override
  State<AdminHomeBuilderScreen> createState() => _AdminHomeBuilderScreenState();
}

const _typeNames = {
  'banner': 'بانر (صورة + رابط)',
  'tiles': 'أيقونات سريعة (روابط مخصصة)',
  'courses': 'صف كورسات',
  'categories': 'الأقسام (مع العدد)',
  'text': 'نص / إعلان',
  'chips': 'شريط أقسام سريع (فلاتر)',
  'numbered': 'الأفضل اليوم (ترقيم كبير)',
};
const _sourceNames = {
  'latest': 'الأحدث',
  'free': 'المجانية',
  'rated': 'الأعلى تقييمًا',
  'category': 'قسم معيّن',
};
const _styleNames = {'row': 'صف أفقي', 'grid': 'شبكة', 'list': 'قائمة'};

class _AdminHomeBuilderScreenState extends State<AdminHomeBuilderScreen> {
  late List<Map<String, dynamic>> _blocks;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _blocks = [for (final b in RemoteUi.homeBlocks) Map<String, dynamic>.from(b)];
    if (!RemoteUi.homeBlocksSet && _blocks.isEmpty) {
      _blocks = [
        for (final b in defaultHomeBlocks) Map<String, dynamic>.from(b),
      ];
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      RemoteUi.homeBlocksSet = true;
      RemoteUi.homeBlocks = [for (final b in _blocks) Map<String, dynamic>.from(b)];
      await AdminToolsRepository.saveSetting('ui_home', {'blocks': _blocks});
      RemoteUi.version.value++;
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('تم الحفظ، الصفحة الرئيسية اتحدثت')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر الحفظ: $e')));
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _add() async {
    final type = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('نوع القسم'),
        children: [
          for (final e in _typeNames.entries)
            SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, e.key), child: Text(e.value)),
        ],
      ),
    );
    if (type == null) return;
    final b = <String, dynamic>{
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'type': type,
      'title': '',
      'enabled': true,
      'at': 1,
      'rows': 6,
      'style': 'row',
      'source': 'latest',
    };
    final ok = await _edit(b);
    if (ok == true) setState(() => _blocks.add(b));
  }

  String _tilesToText(Map<String, dynamic> b) => [
        for (final e in (b['items'] as List? ?? const []))
          if (e is Map) '${e['icon'] ?? ''}|${e['label'] ?? ''}|${e['link'] ?? ''}',
      ].join('\n');

  Future<bool?> _edit(Map<String, dynamic> b) {
    final type = '${b['type']}';
    final title = TextEditingController(text: '${b['title'] ?? ''}');
    final at = TextEditingController(text: '${b['at'] ?? 1}');
    final rows = TextEditingController(text: '${b['rows'] ?? 6}');
    final image = TextEditingController(text: '${b['image'] ?? ''}');
    final link = TextEditingController(text: '${b['link'] ?? ''}');
    final body = TextEditingController(text: '${b['body'] ?? ''}');
    final cat = TextEditingController(text: '${b['category'] ?? ''}');
    final tiles = TextEditingController(text: _tilesToText(b));
    var style = '${b['style'] ?? 'row'}';
    var source = '${b['source'] ?? 'latest'}';
    Widget f(TextEditingController c, String label,
            {int lines = 1, TextInputType? kb}) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextField(
              controller: c,
              maxLines: lines,
              keyboardType: kb,
              decoration: InputDecoration(labelText: label, border: const OutlineInputBorder())),
        );
    return showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(_typeNames[type] ?? type),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              f(title, 'العنوان'),
              f(at, 'مكانه (0 = فوق كل الأقسام، 1 = بعد أول قسم ...)',
                  kb: TextInputType.number),
              if (type == 'banner') ...[
                f(image, 'رابط الصورة'),
                f(link, 'الرابط عند الضغط'),
              ],
              if (type == 'text') f(body, 'النص', lines: 4),
              if (type == 'courses' || type == 'categories' || type == 'numbered')
                f(rows, 'عدد العناصر', kb: TextInputType.number),
              if (type == 'courses' || type == 'numbered') ...[
                DropdownButtonFormField<String>(
                  initialValue: source,
                  decoration: const InputDecoration(labelText: 'المصدر'),
                  items: [
                    for (final e in _sourceNames.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) => setD(() => source = v ?? 'latest'),
                ),
                if (source == 'category')
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Autocomplete<String>(
                      initialValue: TextEditingValue(text: cat.text),
                      optionsBuilder: (v) => AutoCategory.allNames()
                          .where((n) => n.contains(v.text)),
                      onSelected: (v) => cat.text = v,
                      fieldViewBuilder: (c, ctrl, fn, _) {
                        ctrl.addListener(() => cat.text = ctrl.text);
                        return TextField(
                            controller: ctrl,
                            focusNode: fn,
                            decoration: const InputDecoration(
                                labelText: 'اسم القسم', border: OutlineInputBorder()));
                      },
                    ),
                  ),
                if (type == 'courses') DropdownButtonFormField<String>(
                  initialValue: style,
                  decoration: const InputDecoration(labelText: 'الشكل'),
                  items: [
                    for (final e in _styleNames.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) => setD(() => style = v ?? 'row'),
                ),
              ],
              if (type == 'tiles')
                f(tiles,
                    'كل أيقونة في سطر: رمز|الاسم|الرابط\nمثال: 📚|كورساتي|screen:courses\nالروابط: screen:courses/lives/exams/library/qbank/schedule/certs/support، course:رقم، أو رابط https',
                    lines: 6),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            FilledButton(
              onPressed: () {
                b['title'] = title.text.trim();
                b['at'] = int.tryParse(at.text.trim()) ?? 1;
                b['rows'] = int.tryParse(rows.text.trim()) ?? 6;
                b['image'] = image.text.trim();
                b['link'] = link.text.trim();
                b['body'] = body.text.trim();
                b['category'] = cat.text.trim();
                b['style'] = style;
                b['source'] = source;
                if (type == 'tiles') {
                  b['items'] = [
                    for (final line in tiles.text.split('\n'))
                      if (line.trim().isNotEmpty)
                        {
                          'icon': line.split('|').first.trim(),
                          'label': line.split('|').length > 1 ? line.split('|')[1].trim() : '',
                          'link': line.split('|').length > 2 ? line.split('|')[2].trim() : '',
                        },
                  ];
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('بناء الصفحة الرئيسية'), actions: [
        TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('حفظ ونشر')),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('قسم جديد'),
      ),
      body: _blocks.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                    'مفيش أقسام مخصصة لسه. اضغط "قسم جديد" وضيف بانر أو أيقونات أو صف كورسات أو الأقسام. الأقسام الأصلية بتفضل زي ما هي وتقدر ترتبها من "الواجهة والترتيب".',
                    textAlign: TextAlign.center),
              ),
            )
          : ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              itemCount: _blocks.length,
              onReorder: (a, b) => setState(() {
                if (b > a) b--;
                _blocks.insert(b, _blocks.removeAt(a));
              }),
              itemBuilder: (_, i) {
                final b = _blocks[i];
                return Card(
                  key: ValueKey(b['id']),
                  child: ListTile(
                    title: Text('${b['title']}'.isEmpty ? '(بدون عنوان)' : '${b['title']}'),
                    subtitle: Text('${_typeNames[b['type']] ?? b['type']}  •  مكانه ${b['at']}'),
                    leading: Switch(
                      value: b['enabled'] != false,
                      onChanged: (v) => setState(() => b['enabled'] = v),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => setState(() => _blocks.removeAt(i)),
                    ),
                    onTap: () async {
                      await _edit(b);
                      if (mounted) setState(() {});
                    },
                  ),
                );
              },
            ),
    );
  }
}
