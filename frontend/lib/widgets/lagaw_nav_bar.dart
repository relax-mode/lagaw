import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme.dart';

enum NavDestination { home, spots, trips, you }

enum SwipeMenuChoice { startMatching, planTrip }

const _orange = Color(0xFFF2620F);
const _navHeight = 66.0;

/// How far the swipe button rises above the bar: enough to read as the
/// main action while still sitting in the white pill.
const _orbLift = 12.0;

/// Floating nav: Home · Spots · swipe card button · Trips · You. [home v3]
class LagawNavBar extends StatelessWidget {
  final NavDestination? active;
  final ValueChanged<NavDestination> onSelect;
  final VoidCallback onSwipe;

  const LagawNavBar({
    super.key,
    required this.active,
    required this.onSelect,
    required this.onSwipe,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _navHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xF7FFFFFF),
                borderRadius: BorderRadius.circular(999),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x730F1B2D),
                    blurRadius: 30,
                    offset: Offset(0, 14),
                    spreadRadius: -14,
                  ),
                ],
              ),
            ),
          ),
          Row(
            children: [
              _tab(NavDestination.home, Icons.home_rounded, 'Home'),
              _tab(NavDestination.spots, Icons.place_outlined, 'Spots'),
              const Expanded(child: SizedBox()),
              _tab(NavDestination.trips, Icons.luggage_outlined, 'Trips'),
              _tab(NavDestination.you, Icons.person_outline_rounded, 'You'),
            ],
          ),
          Positioned(
            top: -_orbLift,
            left: 0,
            right: 0,
            child: Center(
              child: SwipeOrb(key: const ValueKey('nav-swipe'), onTap: onSwipe),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tab(NavDestination d, IconData icon, String label) {
    final on = d == active;
    final color = on ? _orange : const Color(0xFF7E8BA0);
    return Expanded(
      child: Semantics(
        button: true,
        selected: on,
        child: InkResponse(
          key: ValueKey('nav-${d.name}'),
          onTap: () => onSelect(d),
          radius: 30,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 22, color: color),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: on ? FontWeight.w700 : FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The swipe button in the app-logo style: a blue tile holding the yellow
/// mascot card. [openness] 0 is the closed nav button (the card stands
/// straight, alone); 1 is the open menu, where the glass back card has fanned
/// out behind and the yellow card tilts, matching the Lagaw logo. [home v3]
class SwipeOrb extends StatelessWidget {
  final VoidCallback onTap;
  final double openness;

  const SwipeOrb({super.key, required this.onTap, this.openness = 0});

  static const _blueDeep = Color(0xFF1C5FC4);

  @override
  Widget build(BuildContext context) {
    final t = openness.clamp(0.0, 1.0);
    final open = t >= 0.5;
    return Semantics(
      button: true,
      label: open ? 'Close' : 'Swipe options',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 62,
          height: 62,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 4),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF2E7FEA), Color(0xFF7EBEFF)],
            ),
            boxShadow: const [
              BoxShadow(color: _blueDeep, offset: Offset(0, 5)),
              BoxShadow(
                color: Color(0x8C1C5FC4),
                blurRadius: 22,
                offset: Offset(0, 14),
                spreadRadius: -8,
              ),
            ],
          ),
          child: ClipOval(
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Glass back card: hidden behind the yellow card when closed,
                // fans out to the right as the menu opens.
                Opacity(
                  opacity: Curves.easeOut.transform((t * 1.6).clamp(0.0, 1.0)),
                  child: Transform.translate(
                    offset: Offset(7 * t, -2 * t),
                    child: Transform.rotate(
                      angle: 0.26 * t,
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        width: 26,
                        height: 34,
                        decoration: BoxDecoration(
                          color: const Color(0xD9D6E9FF),
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(
                            color: const Color(0x99FFFFFF),
                            width: 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Yellow mascot card: straight when closed, tilts as it opens.
                Transform.translate(
                  offset: Offset(-3 * t, 2 + 1.5 * t),
                  child: Transform.rotate(
                    angle: -0.12 * t,
                    alignment: Alignment.bottomCenter,
                    child: Image.asset(
                      'assets/brand/swipe_card.png',
                      height: 38,
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens the swipe menu over the screen. [bottomInset] is the gap between
/// the nav bar and the bottom of the screen, so the close button lands
/// exactly on the swipe button. Resolves to the chosen option, or null.
Future<SwipeMenuChoice?> showSwipeMenu(
  BuildContext context, {
  required double bottomInset,
}) {
  final reduce = MediaQuery.disableAnimationsOf(context);
  return showGeneralDialog<SwipeMenuChoice>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close swipe options',
    barrierColor: Colors.transparent,
    transitionDuration: Duration(milliseconds: reduce ? 150 : 380),
    pageBuilder: (context, _, _) =>
        _SwipeMenu(bottomInset: bottomInset, reduce: reduce),
  );
}

class _SwipeMenu extends StatelessWidget {
  final double bottomInset;
  final bool reduce;

  const _SwipeMenu({required this.bottomInset, required this.reduce});

  @override
  Widget build(BuildContext context) {
    final animation = ModalRoute.of(context)!.animation!;
    final fade = CurvedAnimation(parent: animation, curve: Curves.easeOut);

    Widget rise(Widget child, double start) {
      if (reduce) return FadeTransition(opacity: fade, child: child);
      final t = CurvedAnimation(
        parent: animation,
        curve: Interval(start, 1, curve: Curves.easeOutBack),
        reverseCurve: Interval(start, 1, curve: Curves.easeIn),
      );
      return FadeTransition(
        opacity: CurvedAnimation(
          parent: animation,
          curve: Interval(start, 0.7 + start * 0.3),
        ),
        child: ScaleTransition(
          scale: Tween(begin: 0.6, end: 1.0).animate(t),
          alignment: Alignment.bottomCenter,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, 0.35),
              end: Offset.zero,
            ).animate(t),
            child: child,
          ),
        ),
      );
    }

    void close([SwipeMenuChoice? choice]) => Navigator.of(context).pop(choice);

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            key: const ValueKey('swipe-menu-backdrop'),
            onTap: close,
            child: FadeTransition(
              opacity: fade,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                child: const ColoredBox(color: Color(0x730A1830)),
              ),
            ),
          ),
        ),
        Positioned(
          left: 22,
          right: 22,
          // Clear of the close button, which sits where the swipe button is.
          bottom: bottomInset + _navHeight + _orbLift + 20,
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FadeTransition(
                  opacity: fade,
                  child: const Padding(
                    padding: EdgeInsets.only(bottom: 14),
                    child: Text(
                      'What do you feel like?',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                rise(
                  _option(
                    key: const ValueKey('swipe-menu-start'),
                    title: 'Start matching',
                    subtitle: 'Swipe through Bacolod spots',
                    icon: Icons.style_rounded,
                    primary: true,
                    onTap: () => close(SwipeMenuChoice.startMatching),
                  ),
                  0,
                ),
                const SizedBox(height: 10),
                rise(
                  _option(
                    key: const ValueKey('swipe-menu-plan'),
                    title: 'Plan a trip',
                    subtitle: 'Lagaw fills in the stops for you',
                    icon: Icons.luggage_outlined,
                    primary: false,
                    onTap: () => close(SwipeMenuChoice.planTrip),
                  ),
                  0.15,
                ),
              ],
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: bottomInset + _navHeight - 62 + _orbLift,
          child: Center(
            // The cards open into the Lagaw logo; closing folds them back.
            // Reduced motion: no fan, it shows the open logo directly.
            child: AnimatedBuilder(
              animation: animation,
              builder: (context, _) => SwipeOrb(
                key: const ValueKey('swipe-menu-close'),
                openness: reduce
                    ? 1
                    : Curves.easeInOutCubic.transform(animation.value),
                onTap: close,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _option({
    required Key key,
    required String title,
    required String subtitle,
    required IconData icon,
    required bool primary,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      child: GestureDetector(
        key: key,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [
              BoxShadow(
                color: Color(0x8C000000),
                blurRadius: 30,
                offset: Offset(0, 16),
                spreadRadius: -16,
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: primary ? null : const Color(0xFFE7F0FD),
                  gradient: primary
                      ? const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFFFF9A3D), _orange],
                        )
                      : null,
                ),
                child: Icon(
                  icon,
                  color: primary ? Colors.white : AppTheme.primaryBlue,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.slateDark,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.slateMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFF9AA6B8)),
            ],
          ),
        ),
      ),
    );
  }
}
