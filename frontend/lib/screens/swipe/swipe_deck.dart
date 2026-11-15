import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../models/location.dart';
import '../../theme.dart';
import '../../widgets/destination_photo.dart';
import '../home/home_view.dart' show HomeCategory;
import '../spots/spots_view.dart' show PlaceActions, openPlaceDetails;

const _orange = Color(0xFFF2620F);

/// The v3 swipe page: a centered title like Spots and Trips, then a deck of
/// full-photo cards with the next places stacked behind. Each card carries a
/// frosted panel with the place, its tags, and Pass and Like. Drag right to
/// like, left to pass. [home v3]
class SwipeDeck extends StatefulWidget {
  /// The card on top.
  final LocationItem spot;

  /// The next places, shown stacked behind (up to two).
  final List<LocationItem> upNext;

  /// 1-based position of [spot] and the deck size.
  final int position;
  final int total;

  final bool busy;
  final double? rating;
  final String? error;

  /// Records the swipe; the card leaves once it completes.
  final Future<void> Function(bool liked) onSwipe;
  final VoidCallback onRate;

  /// Tapping the card opens its full details, as on Spots.
  final PlaceActions? actions;

  const SwipeDeck({
    super.key,
    required this.spot,
    required this.upNext,
    required this.position,
    required this.total,
    required this.busy,
    required this.rating,
    required this.error,
    required this.onSwipe,
    required this.onRate,
    this.actions,
  });

  @override
  State<SwipeDeck> createState() => _SwipeDeckState();
}

class _SwipeDeckState extends State<SwipeDeck> with TickerProviderStateMixin {
  double _drag = 0;
  final GlobalKey _cardKey = GlobalKey();

  /// Opens the top card's details, growing from the card.
  void _openDetails() {
    final actions = widget.actions;
    final box = _cardKey.currentContext?.findRenderObject() as RenderBox?;
    if (actions == null || box == null || !box.hasSize || _drag != 0) return;
    openPlaceDetails(
      context,
      place: widget.spot,
      origin: box.localToGlobal(Offset.zero) & box.size,
      actions: actions,
    );
  }

  /// The card is flying off; ignore further swipes until the deck moves.
  bool _flying = false;

  /// Throws the card off the side before the next one shows.
  late final AnimationController _fly = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );

  /// Springs the card back when a drag isn't far enough.
  late final AnimationController _settle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  double _settleFrom = 0;

  @override
  void initState() {
    super.initState();
    _settle.addListener(() {
      setState(
        () => _drag =
            _settleFrom * (1 - Curves.easeOutBack.transform(_settle.value)),
      );
    });
  }

  @override
  void didUpdateWidget(SwipeDeck old) {
    super.didUpdateWidget(old);
    if (old.spot.id != widget.spot.id) {
      _drag = 0;
      _flying = false;
    }
  }

  @override
  void dispose() {
    _settle.dispose();
    _fly.dispose();
    super.dispose();
  }

  /// Flies the card off, then records the swipe. The deck moves on right
  /// away; if the swipe is cancelled or fails, the card springs back.
  Future<void> _swipe(bool liked) async {
    if (widget.busy || _flying) return;
    _flying = true;
    _settle.stop();
    final id = widget.spot.id;
    final reduce = MediaQuery.disableAnimationsOf(context);
    final from = _drag;
    final to = (liked ? 1 : -1) * MediaQuery.sizeOf(context).width * 1.3;
    if (!reduce) {
      void tick() => setState(
        () => _drag = from + (to - from) * Curves.easeIn.transform(_fly.value),
      );
      _fly.addListener(tick);
      await _fly.forward(from: 0);
      _fly.removeListener(tick);
    }
    if (!mounted) return;
    await widget.onSwipe(liked);
    if (!mounted) return;
    if (widget.spot.id == id) {
      // Cancelled (the pass explainer) or failed: bring it back.
      _flying = false;
      _springBack();
    }
  }

  void _springBack() {
    if (_drag == 0) return;
    _settleFrom = _drag;
    _settle.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final cardHeight = (w * 1.0).clamp(340.0, 420.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Swipe your vibe',
          key: ValueKey('swipe-title'),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 36,
            height: 1,
            fontWeight: FontWeight.w900,
            letterSpacing: -1.2,
            color: Colors.white,
            shadows: [
              Shadow(
                color: Color(0x40104AA0),
                blurRadius: 22,
                offset: Offset(0, 6),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Wraps under big text sizes instead of overflowing.
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 6,
          children: [
            const Text(
              'Drag right to like · left to pass',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xEBFFFFFF),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0x33FFFFFF),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0x55FFFFFF)),
              ),
              child: Text(
                '${widget.position} / ${widget.total}',
                key: const ValueKey('swipe-count'),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        // Clear room so the tilted back cards never touch the subtitle.
        const SizedBox(height: 44),
        Padding(
          // Inset so the whole card reads smaller, not just shorter.
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: SizedBox(
            height: cardHeight + 26,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.bottomCenter,
              children: [
                // The next places, tilted behind like a stack of photos.
                for (final (i, next)
                    in widget.upNext.take(2).indexed.toList()
                      ..sort((a, b) => b.$1.compareTo(a.$1)))
                  _BackCard(
                    key: ValueKey('swipe-next-${next.id}'),
                    place: next,
                    height: cardHeight,
                    depth: i + 1,
                    // The card behind leans in as you drag the top one away.
                    lift: i == 0 ? (_drag.abs() / 160).clamp(0.0, 1.0) : 0,
                  ),
                _frontCard(cardHeight),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        // Pass, rate and like sit under the card, so the photo stays clear.
        _ActionButtons(
          busy: widget.busy,
          rating: widget.rating,
          onPass: () => _swipe(false),
          onRate: widget.onRate,
          onLike: () => _swipe(true),
        ),
        if (widget.error != null)
          Container(
            key: const ValueKey('swipe-error'),
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              widget.error!,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Color(0xFFBE123C),
              ),
            ),
          ),
      ],
    );
  }

  Widget _frontCard(double height) {
    final spot = widget.spot;
    final liking = _drag > 0;
    final stamp = ((_drag.abs() - 16) / 80).clamp(0.0, 1.0);
    return GestureDetector(
      onTap: _openDetails,
      onPanStart: (_) => _settle.stop(),
      onPanUpdate: (d) {
        if (widget.busy) return;
        setState(() => _drag += d.delta.dx);
      },
      onPanEnd: (d) {
        if (widget.busy) return;
        final v = d.velocity.pixelsPerSecond.dx;
        if (_drag > 90 || v > 500) {
          _swipe(true);
        } else if (_drag < -90 || v < -500) {
          _swipe(false);
        } else {
          _springBack();
        }
      },
      child: Transform.translate(
        offset: Offset(_drag, _drag.abs() * 0.08),
        child: Transform.rotate(
          angle: _drag * 0.0012,
          child: TweenAnimationBuilder<double>(
            // A new top card settles in from the stack.
            key: ValueKey('swipe-card-${spot.id}'),
            tween: Tween(begin: 0.94, end: 1),
            duration: const Duration(milliseconds: 380),
            curve: Curves.easeOutCubic,
            builder: (context, scale, child) =>
                Transform.scale(scale: scale, child: child),
            child: Container(
              key: _cardKey,
              height: height,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: const Color(0xCCFFFFFF), width: 3),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x5C0F285A),
                    blurRadius: 40,
                    offset: Offset(0, 22),
                    spreadRadius: -16,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(29),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // The category chip is top-left, the panel at the
                    // bottom: credit top-right.
                    DestinationPhoto(
                      location: spot,
                      creditCorner: CreditCorner.topRight,
                    ),
                    _Fade(color: spot.gradientColors.first),
                    Positioned(
                      top: 14,
                      left: 14,
                      child: _Glass(
                        radius: 999,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        child: Text(
                          HomeCategory.labelFor(spot.category),
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 12,
                      child: _InfoPanel(spot: spot),
                    ),
                    // Drag feedback: the card warms toward Like or Pass.
                    if (stamp > 0)
                      IgnorePointer(
                        child: ColoredBox(
                          color: (liking ? _orange : const Color(0xFF0F172A))
                              .withValues(alpha: 0.18 * stamp),
                        ),
                      ),
                    if (stamp > 0)
                      Positioned(
                        top: 70,
                        left: liking ? 22 : null,
                        right: liking ? null : 22,
                        child: IgnorePointer(
                          child: Opacity(
                            opacity: stamp,
                            child: Transform.rotate(
                              angle: (liking ? -14 : 14) * math.pi / 180,
                              child: _Stamp(liked: liking),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The bottom fade in the place's category color, so the panel reads on
/// any photo.
class _Fade extends StatelessWidget {
  final Color color;

  const _Fade({required this.color});

  @override
  Widget build(BuildContext context) {
    final c = Color.lerp(color, const Color(0xFF0B1424), 0.35)!;
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: const [0.3, 1],
            colors: [c.withValues(alpha: 0), c.withValues(alpha: 0.9)],
          ),
        ),
      ),
    );
  }
}

/// Frosted glass, as on the reference's card panel.
class _Glass extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsets padding;
  final Color tint;

  const _Glass({
    required this.child,
    this.radius = 24,
    this.padding = const EdgeInsets.all(14),
    this.tint = const Color(0x2EFFFFFF),
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: tint,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: const Color(0x40FFFFFF)),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Just enough to decide: the name, a short description and the price.
/// Tap the card for everything else.
class _InfoPanel extends StatelessWidget {
  final LocationItem spot;

  const _InfoPanel({required this.spot});

  @override
  Widget build(BuildContext context) {
    return _Glass(
      padding: const EdgeInsets.fromLTRB(16, 13, 14, 14),
      tint: const Color(0x38FFFFFF),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            spot.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 24,
              height: 1.05,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
              color: Colors.white,
              shadows: [Shadow(color: Color(0x40000000), blurRadius: 10)],
            ),
          ),
          if (spot.description.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              spot.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w500,
                color: Color(0xF2FFFFFF),
              ),
            ),
          ],
          const SizedBox(height: 9),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0x2EFFFFFF),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0x40FFFFFF)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.payments_outlined,
                  size: 13,
                  color: Colors.white,
                ),
                const SizedBox(width: 4),
                Text(
                  spot.costRange,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Round buttons under the deck: pass on the left, rate in the middle,
/// like on the right.
class _ActionButtons extends StatelessWidget {
  final bool busy;
  final double? rating;
  final VoidCallback onPass;
  final VoidCallback onRate;
  final VoidCallback onLike;

  const _ActionButtons({
    required this.busy,
    required this.rating,
    required this.onPass,
    required this.onRate,
    required this.onLike,
  });

  static String _stars(double r) => r.toStringAsFixed(r % 1 == 0 ? 0 : 1);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _Round(
          key: const ValueKey('swipe-pass'),
          label: 'Pass',
          size: 64,
          color: Colors.white,
          onTap: busy ? null : onPass,
          child: const Icon(
            Icons.close_rounded,
            size: 32,
            color: Color(0xFFE11D48),
          ),
        ),
        const SizedBox(width: 22),
        _Round(
          key: const ValueKey('swipe-rate'),
          label: rating == null
              ? 'Rate this place'
              : 'You rated it ${_stars(rating!)}. Rate again',
          size: 52,
          color: Colors.white,
          onTap: busy ? null : onRate,
          child: rating == null
              ? const Icon(
                  Icons.star_rounded,
                  size: 26,
                  color: Color(0xFFF5B000),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.star_rounded,
                      size: 18,
                      color: Color(0xFFF5B000),
                    ),
                    Text(
                      _stars(rating!),
                      key: const ValueKey('swipe-rating'),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.slateDark,
                      ),
                    ),
                  ],
                ),
        ),
        const SizedBox(width: 22),
        _Round(
          key: const ValueKey('swipe-like'),
          label: 'Like',
          size: 64,
          color: _orange,
          onTap: busy ? null : onLike,
          child: busy
              ? const SizedBox(
                  key: ValueKey('swipe-busy'),
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.6,
                    color: Colors.white,
                  ),
                )
              : const Icon(
                  Icons.favorite_rounded,
                  size: 30,
                  color: Colors.white,
                ),
        ),
      ],
    );
  }
}

class _Round extends StatelessWidget {
  final String label;
  final double size;
  final Color color;
  final VoidCallback? onTap;
  final Widget child;

  const _Round({
    super.key,
    required this.label,
    required this.size,
    required this.color,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: onTap == null ? 0.6 : 1,
          child: Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: const [
                BoxShadow(
                  color: Color(0x400F285A),
                  blurRadius: 20,
                  offset: Offset(0, 10),
                  spreadRadius: -8,
                ),
              ],
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// A next place peeking out behind the top card, tilted and smaller.
class _BackCard extends StatelessWidget {
  final LocationItem place;
  final double height;

  /// 1 = right behind the top card, 2 = behind that.
  final int depth;

  /// 0..1: how far the top card has been dragged away.
  final double lift;

  const _BackCard({
    super.key,
    required this.place,
    required this.height,
    required this.depth,
    required this.lift,
  });

  @override
  Widget build(BuildContext context) {
    final d = depth - lift;
    final turn = (depth.isOdd ? 1 : -1) * 4.5 * d * math.pi / 180;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 26,
      child: IgnorePointer(
        child: Transform.translate(
          offset: Offset(0, -13.0 * d),
          child: Transform.rotate(
            angle: turn * (1 - lift * 0.6),
            child: Transform.scale(
              scale: 1 - 0.05 * d,
              child: Opacity(
                opacity: (1 - 0.18 * d).clamp(0.0, 1.0),
                child: Container(
                  height: height,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(32),
                    border: Border.all(
                      color: const Color(0x99FFFFFF),
                      width: 3,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x330F285A),
                        blurRadius: 24,
                        offset: Offset(0, 12),
                        spreadRadius: -12,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(29),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        DestinationPhoto(location: place, compact: true),
                        _Fade(color: place.gradientColors.first),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Stamp extends StatelessWidget {
  final bool liked;

  const _Stamp({required this.liked});

  @override
  Widget build(BuildContext context) {
    final color = liked ? _orange : Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: liked ? Colors.white : const Color(0x330F172A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color, width: 3),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            liked ? Icons.favorite_rounded : Icons.close_rounded,
            color: color,
            size: 24,
          ),
          const SizedBox(width: 6),
          Text(
            liked ? 'LIKE' : 'PASS',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 20,
              letterSpacing: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}
