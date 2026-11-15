import 'package:flutter/material.dart';

class AppTheme {
  static const Color skyTop = Color(0xFF1E88E5);
  static const Color skyMid = Color(0xFF64B5F6);
  static const Color skyBottom = Color(0xFFF3F7FA);
  static const Color primaryBlue = Color(0xFF2563EB);
  static const Color slateDark = Color(0xFF0F172A);
  static const Color slateMuted = Color(0xFF64748B);

  static final ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    colorSchemeSeed: primaryBlue,
    scaffoldBackgroundColor: skyBottom,
    // Bundled (assets/fonts); 'SF Pro Display' was never shipped. [home v3]
    fontFamily: 'Outfit',
  );
}

/// The app's card: white, rounded, with a soft shadow (the v3 style; it
/// used to be a bevelled 3D card). [home v3]
class GlassContainer extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final Color tintColor;
  final Color borderColor;
  final double blur;
  final List<BoxShadow>? boxShadow;

  const GlassContainer({
    super.key,
    required this.child,
    this.borderRadius = 24,
    this.padding = const EdgeInsets.all(16),
    this.tintColor = Colors.white,
    this.borderColor = Colors.transparent,
    this.blur = 0,
    this.boxShadow,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: tintColor,
        borderRadius: BorderRadius.circular(borderRadius),
        border: borderColor == Colors.transparent
            ? null
            : Border.all(color: borderColor, width: 1.5),
        boxShadow:
            boxShadow ??
            const [
              BoxShadow(
                color: Color(0x4D0F285A),
                offset: Offset(0, 16),
                blurRadius: 30,
                spreadRadius: -16,
              ),
            ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius - 2),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// The app's button: a flat, rounded surface with a soft shadow that
/// presses in slightly (the v3 style; it used to be a bevelled 3D button).
/// [home v3]
class Vector3DButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final Color backgroundColor;
  final Color shadowColor;
  final Color? borderColor;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final double depth;

  const Vector3DButton({
    super.key,
    required this.child,
    this.onTap,
    required this.backgroundColor,
    required this.shadowColor,
    this.borderColor,
    this.borderRadius = 24,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    this.depth = 3.5,
  });

  @override
  State<Vector3DButton> createState() => _Vector3DButtonState();
}

class _Vector3DButtonState extends State<Vector3DButton> {
  bool _hovered = false;
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final white = widget.backgroundColor.computeLuminance() > 0.9;
    final lift = _hovered && enabled && !_pressed;

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: enabled ? (_) => _setPressed(true) : null,
        onTapUp: enabled ? (_) => _setPressed(false) : null,
        onTapCancel: enabled ? () => _setPressed(false) : null,
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1,
          duration: Duration(milliseconds: _pressed ? 70 : 160),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            padding: widget.padding,
            decoration: BoxDecoration(
              color: widget.backgroundColor,
              borderRadius: BorderRadius.circular(widget.borderRadius),
              // White buttons get a hairline so they read on white cards.
              border: white
                  ? Border.all(color: const Color(0xFFE3E9F2), width: 1.2)
                  : null,
              boxShadow: [
                BoxShadow(
                  color: white
                      ? const Color(0x1A0F285A)
                      : widget.backgroundColor.withValues(alpha: 0.28),
                  offset: Offset(0, lift ? 8 : 6),
                  blurRadius: lift ? 18 : 14,
                  spreadRadius: -6,
                ),
              ],
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
