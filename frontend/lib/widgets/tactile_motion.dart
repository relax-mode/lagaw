import 'package:flutter/material.dart';

/// Shared motion timings so every tactile surface feels the same.
class TactileMotion {
  static const Duration press = Duration(milliseconds: 110);
  static const Duration hover = Duration(milliseconds: 180);
  static const Duration enter = Duration(milliseconds: 420);
  static const Duration tab = Duration(milliseconds: 320);
  static const Curve curve = Curves.easeOutCubic;
}

/// Lifts its child on hover and presses it in on tap, like a physical card.
/// With [onTap] null it only reacts to hover (no click cursor).
class TactilePressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double hoverLift;
  final double pressedScale;

  const TactilePressable({
    super.key,
    required this.child,
    this.onTap,
    this.hoverLift = 4,
    this.pressedScale = 0.97,
  });

  @override
  State<TactilePressable> createState() => _TactilePressableState();
}

class _TactilePressableState extends State<TactilePressable> {
  bool _hovered = false;
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final lift = _pressed ? 0.0 : (_hovered ? -widget.hoverLift : 0.0);
    final scale = _pressed ? widget.pressedScale : 1.0;

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onTapDown: enabled ? (_) => _setPressed(true) : null,
        onTapUp: enabled ? (_) => _setPressed(false) : null,
        onTapCancel: enabled ? () => _setPressed(false) : null,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: lift),
          duration: _pressed ? TactileMotion.press : TactileMotion.hover,
          curve: TactileMotion.curve,
          builder: (context, dy, child) =>
              Transform.translate(offset: Offset(0, dy), child: child),
          child: AnimatedScale(
            scale: scale,
            duration: TactileMotion.press,
            curve: TactileMotion.curve,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// Fades and slides its child up once when it first appears.
/// [index] staggers siblings in lists and grids.
class FadeSlideIn extends StatelessWidget {
  final Widget child;
  final int index;
  final double offsetY;

  const FadeSlideIn({
    super.key,
    required this.child,
    this.index = 0,
    this.offsetY = 18,
  });

  @override
  Widget build(BuildContext context) {
    // Stagger by delaying progress inside one tween; capped so long lists stay quick.
    final delay = (index.clamp(0, 8)) * 0.06;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration:
          TactileMotion.enter + Duration(milliseconds: (delay * 1000).round()),
      builder: (context, t, child) {
        final progress = TactileMotion.curve.transform(
          ((t - delay) / (1 - delay)).clamp(0.0, 1.0),
        );
        return Opacity(
          opacity: progress,
          child: Transform.translate(
            offset: Offset(0, (1 - progress) * offsetY),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

/// Cross-fades and slides between pages keyed by [pageKey].
class TactilePageSwitcher extends StatelessWidget {
  final Object pageKey;
  final Widget child;

  const TactilePageSwitcher({
    super.key,
    required this.pageKey,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: TactileMotion.tab,
      switchInCurve: TactileMotion.curve,
      switchOutCurve: Curves.easeIn,
      // Outgoing pages stay visible while fading but must not take taps.
      // Wrappers reuse each child's key so its state survives the swap.
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [
          for (final child in previous)
            IgnorePointer(key: child.key, child: child),
          if (current != null)
            IgnorePointer(key: current.key, ignoring: false, child: current),
        ],
      ),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, 0.03),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: KeyedSubtree(key: ValueKey(pageKey), child: child),
    );
  }
}
