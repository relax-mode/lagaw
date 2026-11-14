import 'package:flutter/material.dart';

import '../../models/image_credits.dart';
import '../../models/location.dart';
import '../../theme.dart';
import '../../widgets/destination_photo.dart';
import '../../widgets/floating_elements.dart';
import '../../widgets/greeting_pill.dart';

export '../../widgets/greeting_pill.dart' show hiligaynonGreeting;

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

  /// Chip label for a category id, e.g. "Parks", "Cafés", "Art".
  static String labelFor(String id) {
    final w = _names[id]?.$1 ?? id;
    return w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}';
  }

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

  /// Off when the app draws one shared element layer for every tab.
  final bool showElements;
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
    this.showElements = true,
    this.clock = DateTime.now,
  });

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  /// Created with the first categories so it can open on heritage.
  PageController? _pages;
  int _page = 0;

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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cats = widget.categories;
    if (cats.isNotEmpty) _controllerFor(cats);
    final current = cats.isEmpty ? null : cats[_page.clamp(0, cats.length - 1)];

    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (widget.showElements)
          const Positioned.fill(
            child: FloatingElements(placements: ElementPlacement.home),
          ),
        SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 120),
          child: Column(
            children: [
              GreetingPill(
                avatarLetter: widget.avatarLetter,
                likedCount: widget.likedCount,
                onSearch: widget.onSearch,
                onSaved: widget.onSaved,
                onAccount: widget.onAccount,
                clock: widget.clock,
              ),
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
