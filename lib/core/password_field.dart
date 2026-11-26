import 'package:flutter/material.dart';

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
  });

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
    return TextFormField(
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
  }
}
