import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme.dart';

enum NavDestination { home, spots, trips, you }

enum SwipeMenuChoice { startMatching, planTrip }

const _orange = Color(0xFFF2620F);
const _orangeDeep = Color(0xFFB9430A);
const _navHeight = 66.0;

/// Raised above the bar, so the swipe button reads as the main action.
const _orbLift = 26.0;

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

/// The orange swipe card button, or the dark close button when [open].
class SwipeOrb extends StatelessWidget {
  final VoidCallback onTap;
  final bool open;

  const SwipeOrb({super.key, required this.onTap, this.open = false});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: open ? 'Close' : 'Swipe options',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 62,
          height: 62,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 4),
            gradient: open
                ? null
                : const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFFF9A3D), _orange],
                  ),
            color: open ? AppTheme.slateDark : null,
            boxShadow: [
              BoxShadow(
                color: open ? Colors.black : _orangeDeep,
                offset: const Offset(0, 5),
              ),
              BoxShadow(
                color: open ? const Color(0x80000000) : const Color(0x99B9430A),
                blurRadius: 22,
                offset: const Offset(0, 14),
                spreadRadius: -8,
              ),
            ],
          ),
          child: Icon(
            open ? Icons.close_rounded : Icons.style_rounded,
            color: Colors.white,
            size: 26,
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
    transitionDuration: Duration(milliseconds: reduce ? 150 : 280),
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
          bottom: bottomInset + _navHeight + 22,
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
            child: RotationTransition(
              turns: reduce
                  ? const AlwaysStoppedAnimation(0)
                  : Tween(begin: -0.125, end: 0.0).animate(fade),
              child: SwipeOrb(
                key: const ValueKey('swipe-menu-close'),
                open: true,
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
