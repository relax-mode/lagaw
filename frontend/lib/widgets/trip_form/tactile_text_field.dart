import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tactile_field_style.dart';

/// Labeled text input in the tactile style. [serverError] shows a backend
/// 422 message until the user edits the field. [S2-04]
class TactileTextField extends StatefulWidget {
  final String label;
  final TextEditingController controller;
  final String? hintText;
  final String? serverError;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final Widget? prefixIcon;
  final String? prefixText;
  final int? maxLength;
  final bool optional;
  final TextInputAction? textInputAction;

  const TactileTextField({
    super.key,
    required this.label,
    required this.controller,
    this.hintText,
    this.serverError,
    this.validator,
    this.keyboardType,
    this.inputFormatters,
    this.prefixIcon,
    this.prefixText,
    this.maxLength,
    this.optional = false,
    this.textInputAction,
  });

  @override
  State<TactileTextField> createState() => _TactileTextFieldState();
}

class _TactileTextFieldState extends State<TactileTextField> {
  String? _dismissedServerError;

  @override
  Widget build(BuildContext context) {
    final serverError = widget.serverError == _dismissedServerError
        ? null
        : widget.serverError;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TactileFieldLabel(widget.label, optional: widget.optional),
        TextFormField(
          controller: widget.controller,
          validator: widget.validator,
          keyboardType: widget.keyboardType,
          inputFormatters: widget.inputFormatters,
          textInputAction: widget.textInputAction,
          maxLength: widget.maxLength,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          onChanged: (_) {
            if (serverError != null) {
              setState(() => _dismissedServerError = widget.serverError);
            }
          },
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 15,
            color: Color(0xFF0F172A),
          ),
          decoration: TactileFieldStyle.decoration(
            hintText: widget.hintText,
            errorText: serverError,
            prefixIcon: widget.prefixIcon,
            prefixText: widget.prefixText,
          ).copyWith(counterText: ''),
        ),
      ],
    );
  }
}
