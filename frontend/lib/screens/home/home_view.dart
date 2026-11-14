import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../models/image_credits.dart';
import '../../models/location.dart';
import '../../theme.dart';
import '../../widgets/destination_photo.dart';

/// Hiligaynon greeting for the local time of day.
String hiligaynonGreeting(DateTime now) {
  final h = now.hour;
  if (h >= 5 && h < 11) return 'Maayong aga,';
  if (h >= 11 && h < 13) return 'Maayong udto,';
  if (h >= 13 && h < 18) return 'Maayong hapon,';
  return 'Maayong gab-i,';
}

/// One carousel card: a category with its real place count.
class HomeCategory {
  final String id;
  final int count;
  final LocationItem cover;

  const HomeCategory({
    required this.id,
    required this.count,
    required this.cover,
  });

  /// Big lowercase word on the card, e.g. "parks".
  String get word => _names[id]?.$1 ?? id;

  /// "3 spots" under the card.
  String get countLabel => count == 1 ? '1 spot' : '$count spots';

  /// "See 3 parks", "See 1 heritage spot".
  String get seeLabel {
    final n = _names[id];
    if (n == null) return 'See $countLabel';
    return 'See $count ${count == 1 ? n.$2 : n.$3}';
  }

  static const Map<String, (String, String, String)> _names = {
    'park': ('parks', 'park', 'parks'),
    'cafe': ('cafés', 'café', 'cafés'),
    'heritage': ('heritage', 'heritage spot', 'heritage spots'),
    'museum': ('museums', 'museum', 'museums'),
    'gallery': ('art', 'art spot', 'art spots'),
    'restaurant': ('dining', 'place to eat', 'places to eat'),
    'landmark': ('landmarks', 'landmark', 'landmarks'),
  };

  /// Where the carousel opens: heritage when present (Roel's choice, so
  /// cards peek from both sides), otherwise the middle card.
  static int startPage(List<HomeCategory> cats) {
    final heritage = cats.indexWhere((c) => c.id == 'heritage');
    return heritage >= 0 ? heritage : cats.length ~/ 2;
  }

  /// Categories by size (then name), each with a cover that has an
  /// approved photo when one exists. [home v3]
  static List<HomeCategory> fromLocations(
    List<LocationItem> locations, {
    ImageCredits? credits,
  }) {
    final groups = <String, List<LocationItem>>{};
    for (final loc in locations) {
      groups.putIfAbsent(loc.category, () => []).add(loc);
    }
    final c = credits ?? ImageCredits.instance;
    final list = [
      for (final e in groups.entries)
        HomeCategory(
          id: e.key,
          count: e.value.length,
          cover: e.value.firstWhere(
            (l) => c.creditFor(l.id, l.imageUrl) != null,
            orElse: () => e.value.first,
          ),
        ),
    ];
    list.sort((a, b) {
      final byCount = b.count.compareTo(a.count);
      return byCount != 0 ? byCount : a.word.compareTo(b.word);
    });
    return list;
  }
}

/// The v3 home: greeting pill, headline framed by floating Bacolod
/// elements, a category carousel and a "See N …" pill. [home v3]
class HomeView extends StatefulWidget {
  final String avatarLetter;
  final int spotCount;
  final int likedCount;
  final List<HomeCategory> categories;

  /// Shown instead of the carousel while places load or fail.
  final Widget? placesState;
  final VoidCallback onSearch;
  final VoidCallback onSaved;
  final VoidCallback onAccount;
  final ValueChanged<String> onSeeCategory;

  /// Test hook for the greeting.
  final DateTime Function() clock;

  const HomeView({
    super.key,
    required this.avatarLetter,
    required this.spotCount,
    required this.likedCount,
    required this.categories,
    required this.onSearch,
    required this.onSaved,
    required this.onAccount,
    required this.onSeeCategory,
    this.placesState,
    this.clock = DateTime.now,
  });

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView>
    with SingleTickerProviderStateMixin {
  /// Created with the first categories so it can open on heritage.
  PageController? _pages;
  late final AnimationController _float = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  );
  int _page = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Gentle floating, off when the system asks for reduced motion.
    if (MediaQuery.disableAnimationsOf(context)) {
      _float.stop();
    } else if (!_float.isAnimating) {
      _float.repeat();
    }
  }

  @override
  void didUpdateWidget(HomeView old) {
    super.didUpdateWidget(old);
    if (_page >= widget.categories.length && widget.categories.isNotEmpty) {
      _page = HomeCategory.startPage(widget.categories);
    }
  }

  /// Opens on the start page (heritage), so cards peek from both sides.
  PageController _controllerFor(List<HomeCategory> cats) =>
      _pages ??= PageController(
        viewportFraction: 0.56,
        initialPage: _page = HomeCategory.startPage(cats),
      );

  @override
  void dispose() {
    _pages?.dispose();
    _float.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width.clamp(320.0, 430.0);
    final cats = widget.categories;
    if (cats.isNotEmpty) _controllerFor(cats);
    final current = cats.isEmpty ? null : cats[_page.clamp(0, cats.length - 1)];

    return Stack(
      clipBehavior: Clip.none,
      children: [
        ..._elements(width),
        SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 120),
          child: Column(
            children: [
              _greetingPill(),
              const SizedBox(height: 34),
              Text(
                widget.spotCount == 1
                    ? '1 spot to explore'
                    : '${widget.spotCount} spots to explore',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xEBFFFFFF),
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'Where to\ntoday?',
                key: ValueKey('home-headline'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 56,
                  height: 0.95,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -2,
                  color: Colors.white,
                  shadows: [
                    Shadow(
                      color: Color(0x40104AA0),
                      blurRadius: 24,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Swipe your vibe, tour Bacolod your way',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xF2FFFFFF),
                ),
              ),
              const SizedBox(height: 22),
              if (cats.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: widget.placesState ?? const SizedBox(height: 290),
                )
              else ...[
                SizedBox(height: 286, child: _carousel(cats)),
                const SizedBox(height: 10),
                _dots(cats.length),
                const SizedBox(height: 16),
                _seePill(current!),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // --- Greeting pill ------------------------------------------------------

  Widget _greetingPill() {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xF5FFFFFF),
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [
          BoxShadow(
            color: Color(0x330F1B2D),
            blurRadius: 24,
            offset: Offset(0, 10),
            spreadRadius: -12,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            button: true,
            label: 'Your account',
            child: GestureDetector(
              key: const ValueKey('home-account'),
              onTap: widget.onAccount,
              child: Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFFF9A3D), Color(0xFFF2620F)],
                  ),
                ),
                child: Text(
                  widget.avatarLetter,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                hiligaynonGreeting(widget.clock()),
                key: const ValueKey('home-greeting'),
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF4A5B73),
                  height: 1.1,
                ),
              ),
              const Text(
                'Bacolod City',
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.slateDark,
                  height: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(width: 14),
          _pillIcon(
            key: const ValueKey('home-saved'),
            label: 'Liked and saved places',
            onTap: widget.onSaved,
            icon: Icons.favorite_rounded,
            color: const Color(0xFFF2620F),
            badge: widget.likedCount,
          ),
          const SizedBox(width: 6),
          _pillIcon(
            key: const ValueKey('home-search'),
            label: 'Search places',
            onTap: widget.onSearch,
            icon: Icons.search_rounded,
            color: AppTheme.slateDark,
          ),
        ],
      ),
    );
  }

  Widget _pillIcon({
    required Key key,
    required String label,
    required VoidCallback onTap,
    required IconData icon,
    required Color color,
    int badge = 0,
  }) {
    return Semantics(
      button: true,
      label: badge > 0 ? '$label, $badge' : label,
      child: GestureDetector(
        key: key,
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFEEF4FC),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 20, color: color),
              ),
              if (badge > 0)
                Positioned(
                  top: -3,
                  right: -3,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 18),
                    height: 18,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF2620F),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: Text(
                      badge > 99 ? '99+' : '$badge',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // --- Floating elements --------------------------------------------------

  List<Widget> _elements(double w) {
    // Positions follow the v3 mockup at 390 wide, scaled to the screen.
    final k = w / 390;
    Widget el(
      String name, {
      required double width,
      double? left,
      double? right,
      required double top,
      required double turns,
      double phase = 0,
      bool flip = false,
    }) {
      return Positioned(
        left: left == null ? null : left * k,
        right: right == null ? null : right * k,
        top: top * k,
        child: IgnorePointer(
          child: AnimatedBuilder(
            animation: _float,
            builder: (context, child) => Transform.translate(
              offset: Offset(
                0,
                math.sin((_float.value + phase) * 2 * math.pi) * 4,
              ),
              child: child,
            ),
            child: Transform.rotate(
              angle: turns * 2 * math.pi,
              child: Transform.flip(
                flipX: flip,
                child: _FloatingElement(asset: name, width: width * k),
              ),
            ),
          ),
        ),
      );
    }

    return [
      el('masskara', width: 138, left: -58, top: 92, turns: -16 / 360),
      el(
        'inasal',
        width: 168,
        right: -48,
        top: 90,
        turns: -20 / 360,
        phase: .3,
      ),
      el('piaya', width: 132, left: -50, top: 290, turns: 18 / 360, phase: .6),
      el(
        'carabao',
        width: 150,
        right: -44,
        top: 284,
        turns: -6 / 360,
        phase: .15,
        flip: true,
      ),
    ];
  }

  // --- Category carousel --------------------------------------------------

  Widget _carousel(List<HomeCategory> cats) {
    final pages = _controllerFor(cats);
    return PageView.builder(
      key: const ValueKey('home-carousel'),
      controller: pages,
      itemCount: cats.length,
      onPageChanged: (i) => setState(() => _page = i),
      itemBuilder: (context, i) => AnimatedBuilder(
        animation: pages,
        builder: (context, child) {
          final page = pages.hasClients && pages.position.haveDimensions
              ? pages.page ?? _page.toDouble()
              : _page.toDouble();
          final delta = (i - page).clamp(-1.0, 1.0);
          return Transform(
            alignment: delta > 0 ? Alignment.centerLeft : Alignment.centerRight,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0012)
              ..rotateY(-delta * 0.72)
              ..scaleByDouble(
                1 - delta.abs() * 0.1,
                1 - delta.abs() * 0.1,
                1,
                1,
              ),
            child: child,
          );
        },
        child: _categoryCard(cats[i], i),
      ),
    );
  }

  Widget _categoryCard(HomeCategory cat, int index) {
    return GestureDetector(
      key: ValueKey('home-category-${cat.id}'),
      onTap: () => index == _page
          ? widget.onSeeCategory(cat.id)
          : _pages!.animateToPage(
              index,
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
            ),
      child: Column(
        children: [
          Container(
            height: 244,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x660F285A),
                  blurRadius: 40,
                  offset: Offset(0, 26),
                  spreadRadius: -20,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(30),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  DestinationPhoto(location: cat.cover),
                  const IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment(0, -0.1),
                          colors: [Color(0x6B091220), Color(0x00091220)],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 14,
                    left: 8,
                    right: 8,
                    child: IgnorePointer(
                      child: Text(
                        cat.word,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.fade,
                        softWrap: false,
                        style: const TextStyle(
                          fontSize: 38,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -1.2,
                          color: Colors.white,
                          shadows: [
                            Shadow(
                              color: Color(0x40000000),
                              blurRadius: 14,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            cat.countLabel,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Color(0xFF4A5B73),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dots(int count) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == _page ? 18 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: i == _page ? AppTheme.slateDark : const Color(0x330F1B2D),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ],
    );
  }

  Widget _seePill(HomeCategory cat) {
    return Semantics(
      button: true,
      child: GestureDetector(
        key: const ValueKey('home-see-category'),
        onTap: () => widget.onSeeCategory(cat.id),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: Container(
            key: ValueKey(cat.id),
            padding: const EdgeInsets.fromLTRB(22, 12, 18, 12),
            decoration: BoxDecoration(
              color: const Color(0xF5FFFFFF),
              borderRadius: BorderRadius.circular(999),
              boxShadow: const [
                BoxShadow(color: Color(0x1F0F285A), offset: Offset(0, 4)),
                BoxShadow(
                  color: Color(0x730F285A),
                  blurRadius: 22,
                  offset: Offset(0, 12),
                  spreadRadius: -12,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  cat.seeLabel,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.slateDark,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.arrow_forward_rounded,
                  size: 18,
                  color: AppTheme.slateDark,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A bundled 3D element with a soft sky-tinted shadow underneath, so it
/// reads as floating in the sky rather than pasted on it.
class _FloatingElement extends StatelessWidget {
  final String asset;
  final double width;

  const _FloatingElement({required this.asset, required this.width});

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
