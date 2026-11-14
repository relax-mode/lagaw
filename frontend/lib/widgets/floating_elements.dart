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

  /// Swipe: peeking out from behind the card's sides, with two below it.
  static const swipe = [
    ElementPlacement(
      'piaya',
      width: 96,
      left: -40,
      top: 214,
      turns: 22 / 360,
      phase: .45,
    ),
    ElementPlacement(
      'masskara',
      width: 104,
      right: -44,
      top: 300,
      turns: 14 / 360,
      phase: .1,
    ),
    ElementPlacement(
      'carabao',
      width: 112,
      left: -34,
      top: 584,
      turns: 6 / 360,
      phase: .7,
    ),
    ElementPlacement(
      'inasal',
      width: 112,
      right: -34,
      top: 590,
      turns: -22 / 360,
      phase: .3,
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

  /// Off the page: tucked past the nearest side edge, so elements drift
  /// in and out from the edge instead of popping up mid-screen.
  _Pose absent(double screenWidth) => _Pose(
    asset,
    x: x + (x + width / 2 < screenWidth / 2 ? -1 : 1) * width * 0.75,
    y: y + 18,
    width: width,
    turns: turns,
    flip: flip,
    phase: phase,
    presence: 0,
  );

  _Pose shifted(double dy) => _Pose(
    asset,
    x: x,
    y: y + dy,
    width: width,
    turns: turns,
    flip: flip,
    phase: phase,
    presence: presence,
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
/// new set of [placements] (another page) and each element floats to its
/// new spot, a beat after the one before; ones not on the new page drift
/// out past the nearest edge and new ones drift in from it.
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

  /// Runs linearly; each element eases through its own slice of it.
  late final AnimationController _move = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 950),
    value: 1,
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
    _from = {for (final p in _poses(old.placements, _move.value)) p.asset: p};
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

  /// -1 for the left half of the screen, 1 for the right.
  int _side(_Pose p) => p.x + p.width / 2 < _width / 2 ? -1 : 1;

  /// Where everything is at glide progress [raw] (0..1, linear). Elements
  /// start a beat apart and ease in and out; ones that stay on screen rise
  /// in a slight arc, so the move reads as floating rather than sliding.
  Iterable<_Pose> _poses(List<ElementPlacement> target, double raw) sync* {
    final to = {for (final p in target) p.asset: _Pose.of(p, _width)};
    final assets = {..._from.keys, ...to.keys}.toList();
    for (final (i, asset) in assets.indexed) {
      final a = _from[asset] ?? to[asset]!.absent(_width);
      final b = to[asset] ?? _from[asset]!.absent(_width);
      if (raw >= 1) {
        if (b.presence > 0.01) yield b;
        continue;
      }
      final start = math.min(i * 0.07, 0.28);
      final t = Curves.easeInOutCubic.transform(
        Interval(start, start + 0.72).transform(raw),
      );
      final _Pose pose;
      if (a.presence > 0 && b.presence > 0 && _side(a) != _side(b)) {
        // Changing sides: drift out past the old edge, back in from the
        // new one, rather than flying across the page.
        pose = t < 0.5
            ? _Pose.lerp(a, a.absent(_width), t * 2)
            : _Pose.lerp(b.absent(_width), b, (t - 0.5) * 2);
      } else if (a.presence > 0 && b.presence > 0) {
        pose = _Pose.lerp(a, b, t).shifted(-math.sin(math.pi * t) * 22);
      } else {
        pose = _Pose.lerp(a, b, t);
      }
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
            animation: _move,
            builder: (context, _) => Stack(
              clipBehavior: Clip.none,
              children: [
                for (final p in _poses(widget.placements, _move.value))
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
                          scale: 0.82 + 0.18 * p.presence,
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
