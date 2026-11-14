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

  /// Trips: carabao and masskara either side of the centered title.
  static const trips = [
    ElementPlacement(
      'carabao',
      width: 124,
      left: -40,
      top: 74,
      turns: 8 / 360,
      phase: .1,
    ),
    ElementPlacement(
      'masskara',
      width: 112,
      right: -44,
      top: 50,
      turns: 16 / 360,
      phase: .5,
    ),
  ];

  /// You: all four around the avatar like stickers, kept above the name.
  static const you = [
    ElementPlacement(
      'masskara',
      width: 108,
      left: -20,
      top: -6,
      turns: -14 / 360,
      phase: .05,
    ),
    ElementPlacement(
      'inasal',
      width: 126,
      right: -30,
      top: -14,
      turns: -24 / 360,
      phase: .35,
    ),
    ElementPlacement(
      'piaya',
      width: 84,
      left: -8,
      top: 98,
      turns: 20 / 360,
      phase: .6,
    ),
    ElementPlacement(
      'carabao',
      width: 108,
      right: -26,
      top: 92,
      turns: -6 / 360,
      phase: .2,
      flip: true,
    ),
  ];
}

/// Where one element is drawn at a moment: absolute, so two placements
/// anchored to different edges can blend.
class _Pose {
  final String asset;
  final double x;
  final double y;
  final double width;
  final double turns;
  final bool flip;
  final double phase;

  /// 0 when off the page (entering or leaving), 1 when placed.
  final double presence;

  const _Pose(
    this.asset, {
    required this.x,
    required this.y,
    required this.width,
    required this.turns,
    required this.flip,
    required this.phase,
    required this.presence,
  });

  factory _Pose.of(ElementPlacement p, double screenWidth) {
    final k = screenWidth.clamp(320.0, 430.0) / 390;
    final w = p.width * k;
    return _Pose(
      p.asset,
      x: p.left != null ? p.left! * k : screenWidth - p.right! * k - w,
      y: p.top * k,
      width: w,
      turns: p.turns,
      flip: p.flip,
      phase: p.phase,
      presence: 1,
    );
  }

  _Pose absent() => _Pose(
    asset,
    x: x,
    y: y,
    width: width,
    turns: turns,
    flip: flip,
    phase: phase,
    presence: 0,
  );

  static double _l(double a, double b, double t) => a + (b - a) * t;

  static _Pose lerp(_Pose a, _Pose b, double t) => _Pose(
    b.asset,
    x: _l(a.x, b.x, t),
    y: _l(a.y, b.y, t),
    width: _l(a.width, b.width, t),
    turns: _l(a.turns, b.turns, t),
    flip: t < 0.5 ? a.flip : b.flip,
    phase: _l(a.phase, b.phase, t),
    presence: _l(a.presence, b.presence, t),
  );
}

/// Bundled 3D elements with a sky-tinted shadow, bobbing gently. Give it a
/// new set of [placements] (another page) and each element glides to its
/// new spot; ones not on the new page shrink away and new ones grow in.
/// The bob and the glide stop when the system asks for reduced motion.
/// Never takes touches. [home v3]
class FloatingElements extends StatefulWidget {
  final List<ElementPlacement> placements;

  const FloatingElements({super.key, required this.placements});

  @override
  State<FloatingElements> createState() => _FloatingElementsState();
}

class _FloatingElementsState extends State<FloatingElements>
    with TickerProviderStateMixin {
  late final AnimationController _float = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  );
  late final AnimationController _move = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 720),
    value: 1,
  );
  late final Animation<double> _moveCurve = CurvedAnimation(
    parent: _move,
    curve: Curves.easeInOutCubic,
  );

  /// Poses at the start of the current glide, by asset.
  Map<String, _Pose> _from = {};
  double _width = 390;
  bool _reduce = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = MediaQuery.disableAnimationsOf(context);
    _syncFloat();
  }

  /// Bob only while something is on the page and motion is welcome; the
  /// glide's own ticks cover elements that are leaving.
  void _syncFloat() {
    if (_reduce || widget.placements.isEmpty) {
      _float.stop();
    } else if (!_float.isAnimating) {
      _float.repeat();
    }
  }

  @override
  void didUpdateWidget(FloatingElements old) {
    super.didUpdateWidget(old);
    if (identical(old.placements, widget.placements)) return;
    // Start from wherever things are now, even mid-glide.
    _from = {
      for (final p in _poses(old.placements, _moveCurve.value)) p.asset: p,
    };
    if (_reduce) {
      _move.value = 1;
    } else {
      _move.forward(from: 0);
    }
    _syncFloat();
  }

  @override
  void dispose() {
    _float.dispose();
    _move.dispose();
    super.dispose();
  }

  Iterable<_Pose> _poses(List<ElementPlacement> target, double t) sync* {
    final to = {for (final p in target) p.asset: _Pose.of(p, _width)};
    for (final asset in {..._from.keys, ...to.keys}) {
      final a = _from[asset] ?? to[asset]!.absent();
      final b = to[asset] ?? _from[asset]!.absent();
      final pose = t >= 1 ? b : _Pose.lerp(a, b, t);
      if (pose.presence > 0.01) yield pose;
    }
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, box) {
          _width = box.maxWidth.isFinite
              ? box.maxWidth
              : MediaQuery.sizeOf(context).width;
          return AnimatedBuilder(
            animation: _moveCurve,
            builder: (context, _) => Stack(
              clipBehavior: Clip.none,
              children: [
                for (final p in _poses(widget.placements, _moveCurve.value))
                  Positioned(
                    key: ValueKey(p.asset),
                    left: p.x,
                    top: p.y,
                    child: AnimatedBuilder(
                      animation: _float,
                      builder: (context, child) => Transform.translate(
                        offset: Offset(
                          0,
                          math.sin((_float.value + p.phase) * 2 * math.pi) * 4,
                        ),
                        child: child,
                      ),
                      child: Opacity(
                        opacity: p.presence.clamp(0.0, 1.0),
                        child: Transform.scale(
                          scale: 0.6 + 0.4 * p.presence,
                          child: Transform.rotate(
                            angle: p.turns * 2 * math.pi,
                            child: Transform.flip(
                              flipX: p.flip,
                              child: _Element(asset: p.asset, width: p.width),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
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
