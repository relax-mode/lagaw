import 'package:flutter/material.dart';

import '../../theme.dart';

/// Shared look for trip form inputs: a soft filled field, an orange focus
/// ring and a red error ring, as on the v3 forms. [S2-04, home v3]
class TactileFieldStyle {
  static const Color border = Color(0xFFE2E8F0);
  static const Color bevel = Color(0xFFCBD5E1);
  static const Color error = Color(0xFFE11D48);
  static const double radius = 16;
  static const Color fill = Color(0xFFF1F5FB);

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
        borderSide: width == 0
            ? BorderSide.none
            : BorderSide(color: color, width: width),
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
      fillColor: fill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: _outline(Colors.transparent, 0),
      enabledBorder: _outline(Colors.transparent, 0),
      disabledBorder: _outline(Colors.transparent, 0),
      focusedBorder: _outline(const Color(0xFFF2620F), 1.6),
      errorBorder: _outline(error, 1.2),
      focusedErrorBorder: _outline(error, 1.6),
      errorStyle: const TextStyle(
        color: error,
        fontWeight: FontWeight.w600,
        fontSize: 12,
      ),
    );
  }

  /// Sharp bottom bevel matching `GlassContainer`, drawn behind an input.
  static const List<BoxShadow> bevelShadow = [];
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
          // Narrow pop-ups: long labels ellipsize instead of overflowing.
          Flexible(
            child: Text(
              text,
              style: TactileFieldStyle.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
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
