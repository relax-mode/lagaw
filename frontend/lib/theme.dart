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
    fontFamily: 'SF Pro Display',
  );
}

/// Reusable 3D Vector Card Widget (Clean, solid, tactile 3D style)
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
    this.borderColor = const Color(0xFFE2E8F0),
    this.blur = 0,
    this.boxShadow,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: tintColor,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: borderColor, width: 2.0),
        boxShadow: boxShadow ??
            const [
              BoxShadow(
                color: Color(0xFFCBD5E1),
                offset: Offset(0, 4),
                blurRadius: 0, // Sharp 3D tactile bottom bevel
              ),
              BoxShadow(
                color: Color(0x180F172A),
                offset: Offset(0, 8),
                blurRadius: 16,
              ),
            ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius - 2),
        child: Padding(
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}

/// Tactile 3D Vector Button with Solid Colorful Depth.
/// Lifts slightly on hover and sinks into its bevel when pressed.
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
    // Pressed: the face travels down into its bevel. Hovered: it rises a touch.
    final travel = _pressed
        ? widget.depth * 0.75
        : (_hovered && enabled ? -1.5 : 0.0);
    final edge = widget.depth - travel;

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
        child: AnimatedContainer(
          duration: Duration(milliseconds: _pressed ? 70 : 160),
          curve: Curves.easeOutCubic,
          transform: Matrix4.translationValues(0, travel, 0),
          padding: widget.padding,
          decoration: BoxDecoration(
            color: widget.backgroundColor,
            borderRadius: BorderRadius.circular(widget.borderRadius),
            border: Border.all(
              color: widget.borderColor ?? widget.shadowColor,
              width: 2.0,
            ),
            boxShadow: [
              BoxShadow(
                color: widget.shadowColor,
                offset: Offset(0, edge),
                blurRadius: 0, // Solid 3D vector bottom edge
              ),
              BoxShadow(
                color: const Color(0x220F172A),
                offset: Offset(0, edge + 3),
                blurRadius: _hovered && !_pressed ? 10 : 6,
              ),
            ],
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
