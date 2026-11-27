import 'package:flutter/material.dart';

import 'l10n.dart';

/// Live search box used at the top of every admin list.
class AdminSearchField extends StatefulWidget {
  const AdminSearchField({super.key, required this.onChanged});
  final ValueChanged<String> onChanged;

  @override
  State<AdminSearchField> createState() => _AdminSearchFieldState();
}

class _AdminSearchFieldState extends State<AdminSearchField> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: TextField(
        controller: _c,
        textInputAction: TextInputAction.search,
        onChanged: (v) {
          setState(() {});
          widget.onChanged(v);
        },
        decoration: InputDecoration(
          hintText: S.of(context).t('search_hint'),
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _c.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    _c.clear();
                    setState(() {});
                    widget.onChanged('');
                  }),
          filled: true,
          fillColor: scheme.surfaceContainerHighest.withValues(alpha: .6),
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(28),
              borderSide: BorderSide.none),
        ),
      ),
    );
  }
}
