import 'package:flutter/material.dart';

import 'l10n.dart';

/// Password input with a show/hide eye toggle. Works inside or outside a Form.
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    required this.label,
    this.icon,
    this.validator,
    this.onSubmitted,
    this.textInputAction,
    this.showStrength = false,
  });

  final bool showStrength;

  final TextEditingController controller;
  final String label;
  final IconData? icon;
  final String? Function(String?)? validator;
  final void Function(String)? onSubmitted;
  final TextInputAction? textInputAction;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _hide = true;

  @override
  Widget build(BuildContext context) {
    final field = TextFormField(
      controller: widget.controller,
      obscureText: _hide,
      validator: widget.validator,
      onFieldSubmitted: widget.onSubmitted,
      textInputAction: widget.textInputAction,
      decoration: InputDecoration(
        labelText: widget.label,
        prefixIcon: widget.icon == null ? null : Icon(widget.icon),
        suffixIcon: IconButton(
          icon: Icon(_hide ? Icons.visibility_off_outlined : Icons.visibility_outlined),
          onPressed: () => setState(() => _hide = !_hide),
        ),
      ),
    );
    if (!widget.showStrength) return field;
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: widget.controller,
      builder: (context, v, _) {
        final p = v.text;
        var score = 0;
        if (p.length >= 8) score++;
        if (RegExp(r'[A-Z]').hasMatch(p) && RegExp(r'[a-z]').hasMatch(p)) {
          score++;
        }
        if (RegExp(r'\d').hasMatch(p) && RegExp(r'[^A-Za-z0-9]').hasMatch(p)) {
          score++;
        }
        final colors = [Colors.red, Colors.orange, Colors.lightGreen, Colors.green];
        final labels = ['pw_weak', 'pw_weak', 'pw_medium', 'pw_strong'];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            field,
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: p.isEmpty ? 0 : (score + 1) / 4,
                minHeight: 5,
                color: colors[score],
                backgroundColor: Colors.grey.shade300,
              ),
            ),
            if (p.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(S.of(context).t(labels[score]),
                    style: TextStyle(color: colors[score], fontSize: 12)),
              ),
          ],
        );
      },
    );
  }
}
