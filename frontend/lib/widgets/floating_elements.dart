import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// Where one Bacolod 3D element floats, in points on a 390-wide screen
/// (scaled to the real width). [home v3]
class ElementPlacement {
  final String asset;
  final double width;
  final double? left;
  final double? right;
  final double top;

  /// Tilt in turns (1 = full circle).
  final double turns;

  /// Offset in the shared float cycle, so elements don't bob in sync.
  final double phase;
  final bool flip;

  const ElementPlacement(
    this.asset, {
    required this.width,
    this.left,
    this.right,
    required this.top,
    this.turns = 0,
    this.phase = 0,
    this.flip = false,
  });

  /// Home: four elements framing the headline and the carousel.
  static const home = [
    ElementPlacement(
      'masskara',
      width: 138,
      left: -58,
      top: 92,
      turns: -16 / 360,
    ),
    ElementPlacement(
      'inasal',
      width: 168,
      right: -48,
      top: 90,
      turns: -20 / 360,
      phase: .3,
    ),
    ElementPlacement(
      'piaya',
      width: 132,
      left: -50,
      top: 606,
      turns: 18 / 360,
      phase: .6,
    ),
    ElementPlacement(
      'carabao',
      width: 150,
      right: -44,
      top: 598,
      turns: -6 / 360,
      phase: .15,
      flip: true,
    ),
  ];

  /// Spots: the centered title framed by inasal (right) and piaya (left).
  static const spots = [
    ElementPlacement(
      'inasal',
      width: 150,
      right: -44,
      top: 74,
      turns: -18 / 360,
      phase: .2,
    ),
    // Beside the centered title, lower than the inasal so they stagger.
    ElementPlacement(
      'piaya',
      width: 104,
      left: -14,
      top: 150,
      turns: 22 / 360,
      phase: .55,
    ),
  ];
}

/// Bundled 3D elements with a sky-tinted shadow, bobbing gently. The bob
/// stops when the system asks for reduced motion. Never takes touches.
class FloatingElements extends StatefulWidget {
  final List<ElementPlacement> placements;

  const FloatingElements({super.key, required this.placements});

  @override
  State<FloatingElements> createState() => _FloatingElementsState();
}

class _FloatingElementsState extends State<FloatingElements>
    with SingleTickerProviderStateMixin {
  late final AnimationController _float = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _float.stop();
    } else if (!_float.isAnimating) {
      _float.repeat();
    }
  }

  @override
  void dispose() {
    _float.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final k = MediaQuery.sizeOf(context).width.clamp(320.0, 430.0) / 390;
    return IgnorePointer(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final p in widget.placements)
            Positioned(
              left: p.left == null ? null : p.left! * k,
              right: p.right == null ? null : p.right! * k,
              top: p.top * k,
              child: AnimatedBuilder(
                animation: _float,
                builder: (context, child) => Transform.translate(
                  offset: Offset(
                    0,
                    math.sin((_float.value + p.phase) * 2 * math.pi) * 4,
                  ),
                  child: child,
                ),
                child: Transform.rotate(
                  angle: p.turns * 2 * math.pi,
                  child: Transform.flip(
                    flipX: p.flip,
                    child: _Element(asset: p.asset, width: p.width * k),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Element extends StatelessWidget {
  final String asset;
  final double width;

  const _Element({required this.asset, required this.width});

  @override
  Widget build(BuildContext context) {
    final path = 'assets/elements/$asset.webp';
    return SizedBox(
      width: width,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Transform.translate(
            offset: const Offset(0, 16),
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Image.asset(
                path,
                width: width,
                color: const Color(0x52123E8C),
                colorBlendMode: BlendMode.srcIn,
              ),
            ),
          ),
          Image.asset(path, width: width),
        ],
      ),
    );
  }
}
