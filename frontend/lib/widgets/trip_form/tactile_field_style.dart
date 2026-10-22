import 'package:flutter/material.dart';

import '../../theme.dart';

/// Shared look for trip form inputs: white tactile surface, 2px slate
/// border, blue focus ring, rose error ring. [S2-04]
class TactileFieldStyle {
  static const Color border = Color(0xFFE2E8F0);
  static const Color bevel = Color(0xFFCBD5E1);
  static const Color error = Color(0xFFE11D48);
  static const double radius = 18;

  static const TextStyle label = TextStyle(
    fontFamily: 'Outfit',
    fontWeight: FontWeight.w800,
    fontSize: 14,
    color: AppTheme.slateDark,
  );

  static const TextStyle hint = TextStyle(
    fontWeight: FontWeight.w500,
    fontSize: 13,
    color: AppTheme.slateMuted,
  );

  static OutlineInputBorder _outline(Color color, [double width = 2]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: BorderSide(color: color, width: width),
      );

  static InputDecoration decoration({
    String? hintText,
    String? errorText,
    Widget? prefixIcon,
    String? prefixText,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: hint,
      errorText: errorText,
      errorMaxLines: 2,
      prefixIcon: prefixIcon,
      prefixText: prefixText,
      prefixStyle: label,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      enabledBorder: _outline(border),
      focusedBorder: _outline(AppTheme.primaryBlue, 2.4),
      errorBorder: _outline(error),
      focusedErrorBorder: _outline(error, 2.4),
      errorStyle: const TextStyle(
        color: error,
        fontWeight: FontWeight.w600,
        fontSize: 12,
      ),
    );
  }

  /// Sharp bottom bevel matching `GlassContainer`, drawn behind an input.
  static const List<BoxShadow> bevelShadow = [
    BoxShadow(color: bevel, offset: Offset(0, 3), blurRadius: 0),
  ];
}

/// Bold label above a form field, with an optional "Optional" tag.
class TactileFieldLabel extends StatelessWidget {
  final String text;
  final bool optional;

  const TactileFieldLabel(this.text, {super.key, this.optional = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Row(
        children: [
          Text(text, style: TactileFieldStyle.label),
          if (optional) ...[
            const SizedBox(width: 6),
            const Text(
              'Optional',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppTheme.slateMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Inline error line used by non-text fields (chips, date range).
class TactileFieldError extends StatelessWidget {
  final String? message;

  const TactileFieldError(this.message, {super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      alignment: Alignment.topLeft,
      child: message == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(left: 12, top: 6),
              child: Text(
                message!,
                style: const TextStyle(
                  color: TactileFieldStyle.error,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
    );
  }
}
