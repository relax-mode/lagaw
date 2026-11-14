import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/location.dart';
import '../../theme.dart';
import '../../widgets/destination_photo.dart';
import '../../widgets/floating_elements.dart';
import '../../widgets/greeting_pill.dart';
import '../home/home_view.dart' show HomeCategory;

/// The v3 Spots page: the same greeting pill and floating elements as home,
/// a glass search, category chips built from the real data, and places as
/// photo cards that pop up to show everything. [home v3]
class SpotsView extends StatefulWidget {
  final String avatarLetter;
  final int likedCount;
  final VoidCallback onSaved;
  final VoidCallback onAccount;

  /// Places after the search and category filters.
  final List<LocationItem> places;

  /// Category ids present in the live data, largest first.
  final List<String> categories;
  final String selectedCategory;
  final String query;
  final ValueChanged<String> onQuery;
  final ValueChanged<String> onCategory;

  /// Showing only liked and saved places.
  final bool savedOnly;
  final VoidCallback onExitSaved;

  final bool Function(String id) isSaved;
  final bool Function(String id) isBusy;
  final double? Function(String id) ratingFor;
  final ValueChanged<LocationItem> onSave;
  final ValueChanged<LocationItem> onRate;

  /// Shown instead of the cards while places load or fail.
  final Widget? placesState;

  /// Off when the app draws one shared element layer for every tab.
  final bool showElements;

  /// Notifies when saves, ratings or busy states change, so an open card
  /// stays current.
  final Listenable? changes;

  const SpotsView({
    super.key,
    required this.avatarLetter,
    required this.likedCount,
    required this.onSaved,
    required this.onAccount,
    required this.places,
    required this.categories,
    required this.selectedCategory,
    required this.query,
    required this.onQuery,
    required this.onCategory,
    required this.savedOnly,
    required this.onExitSaved,
    required this.isSaved,
    required this.isBusy,
    required this.ratingFor,
    required this.onSave,
    required this.onRate,
    this.placesState,
    this.changes,
    this.showElements = true,
  });

  @override
  State<SpotsView> createState() => _SpotsViewState();
}

class _SpotsViewState extends State<SpotsView> {
  late final TextEditingController _search = TextEditingController(
    text: widget.query,
  );
  final FocusNode _searchFocus = FocusNode();
  final Map<String, GlobalKey> _chipKeys = {};
  final Map<String, GlobalKey> _cardKeys = {};

  /// The card lifted into the pop-up; hidden in the grid meanwhile so the
  /// morph reads as one card moving, not a copy.
  final ValueNotifier<String?> _lifted = ValueNotifier(null);
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealChip());
  }

  @override
  void didUpdateWidget(SpotsView old) {
    super.didUpdateWidget(old);
    if (widget.query != _search.text) _search.text = widget.query;
    if (old.selectedCategory != widget.selectedCategory) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealChip());
    }
  }

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    _lifted.dispose();
    super.dispose();
  }

  /// Keeps the selected chip on screen (e.g. after "See 1 museum").
  void _revealChip() {
    final ctx = _chipKeys[widget.selectedCategory]?.currentContext;
    if (ctx == null || !mounted) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.5,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  /// Lifts the card out of its spot into the centered expanded card.
  Future<void> _open(LocationItem place) async {
    final box =
        _cardKeys[place.id]?.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || _opening) return;
    _opening = true;
    final origin = box.localToGlobal(Offset.zero) & box.size;
    // Hide the grid card once the pop-up has drawn its first frame, so
    // there is never a frame with neither.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _lifted.value = place.id;
    });
    await showPlacePopup(
      context,
      place: place,
      origin: origin,
      changes: widget.changes,
      details: () => _PlaceDetails(
        place: place,
        saved: widget.isSaved(place.id),
        busy: widget.isBusy(place.id),
        rating: widget.ratingFor(place.id),
        onSave: () => widget.onSave(place),
        onRate: () => widget.onRate(place),
      ),
      saved: () => widget.isSaved(place.id),
      busy: () => widget.isBusy(place.id),
      onSave: () => widget.onSave(place),
    );
    _opening = false;
    if (mounted) _lifted.value = null;
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.places.length;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (widget.showElements)
          const Positioned.fill(
            child: FloatingElements(placements: ElementPlacement.spots),
          ),
        SingleChildScrollView(
          key: const ValueKey('spots-scroll'),
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: GreetingPill(
                  avatarLetter: widget.avatarLetter,
                  likedCount: widget.likedCount,
                  onSearch: () => _searchFocus.requestFocus(),
                  onSaved: widget.onSaved,
                  onAccount: widget.onAccount,
                ),
              ),
              const SizedBox(height: 26),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: _title(count),
              ),
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _searchField(),
              ),
              const SizedBox(height: 14),
              _chips(),
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: widget.placesState ?? _grid(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _title(int count) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (widget.savedOnly)
          GestureDetector(
            key: const ValueKey('spots-exit-saved'),
            onTap: widget.onExitSaved,
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.fromLTRB(10, 6, 14, 6),
              decoration: BoxDecoration(
                color: const Color(0x2EFFFFFF),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0x66FFFFFF)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.arrow_back_rounded, size: 16, color: Colors.white),
                  SizedBox(width: 6),
                  Text(
                    'All spots',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        Text(
          widget.savedOnly ? 'Your picks' : 'Explore\nBacolod',
          key: const ValueKey('spots-title'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 40,
            height: 0.98,
            fontWeight: FontWeight.w900,
            letterSpacing: -1.4,
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
        Text(
          widget.savedOnly
              ? (count == 1
                    ? '1 place you liked or saved'
                    : '$count places you liked or saved')
              : (count == 1 ? 'Showing 1 place' : 'Showing $count places'),
          key: const ValueKey('spots-count'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xEBFFFFFF),
          ),
        ),
      ],
    );
  }

  Widget _searchField() {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
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
        children: [
          const Icon(Icons.search_rounded, color: AppTheme.slateMuted),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              key: const ValueKey('spots-search'),
              controller: _search,
              focusNode: _searchFocus,
              onChanged: widget.onQuery,
              textInputAction: TextInputAction.search,
              style: const TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w600,
                color: AppTheme.slateDark,
              ),
              decoration: const InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: 'Search cafés, heritage, food…',
                hintStyle: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF94A3B8),
                ),
              ),
            ),
          ),
          if (widget.query.isNotEmpty)
            GestureDetector(
              key: const ValueKey('spots-search-clear'),
              onTap: () {
                _search.clear();
                widget.onQuery('');
              },
              child: const Icon(
                Icons.close_rounded,
                size: 20,
                color: AppTheme.slateMuted,
              ),
            ),
        ],
      ),
    );
  }

  Widget _chips() {
    final ids = ['all', ...widget.categories];
    return SizedBox(
      height: 40,
      child: ListView.separated(
        key: const ValueKey('spots-chips'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: ids.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final id = ids[i];
          final on = widget.selectedCategory == id;
          return Semantics(
            button: true,
            selected: on,
            child: GestureDetector(
              key: _chipKeys.putIfAbsent(id, GlobalKey.new),
              onTap: () => widget.onCategory(id),
              child: AnimatedContainer(
                key: ValueKey('spots-chip-$id'),
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: on ? Colors.white : const Color(0x2EFFFFFF),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: on ? Colors.white : const Color(0x66FFFFFF),
                  ),
                ),
                child: Text(
                  id == 'all' ? 'All spots' : HomeCategory.labelFor(id),
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: on ? FontWeight.w700 : FontWeight.w600,
                    color: on ? AppTheme.slateDark : Colors.white,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _grid() {
    if (widget.places.isEmpty) return _empty();
    return LayoutBuilder(
      builder: (context, box) {
        const gap = 12.0;
        final half = (box.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final place in widget.places)
              _PlaceCard(
                key: _cardKeys.putIfAbsent(place.id, GlobalKey.new),
                place: place,
                width: half,
                saved: widget.isSaved(place.id),
                busy: widget.isBusy(place.id),
                onOpen: () => _open(place),
                onSave: () => widget.onSave(place),
                lifted: _lifted,
              ),
          ],
        );
      },
    );
  }

  Widget _empty() {
    return Container(
      key: const ValueKey('spots-empty'),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xF5FFFFFF),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.travel_explore_rounded,
            size: 34,
            color: AppTheme.primaryBlue,
          ),
          const SizedBox(height: 10),
          Text(
            widget.savedOnly
                ? 'Nothing liked or saved yet. Swipe right or tap a heart to keep places here.'
                : 'No places match. Try another word or category.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: AppTheme.slateDark,
            ),
          ),
          if (!widget.savedOnly) ...[
            const SizedBox(height: 12),
            TextButton(
              key: const ValueKey('spots-show-all'),
              onPressed: () {
                _search.clear();
                widget.onQuery('');
                widget.onCategory('all');
              },
              child: const Text('Show all places'),
            ),
          ],
        ],
      ),
    );
  }
}

/// What a place card can do, so pages other than Spots (e.g. You) can show
/// the same cards and pop-up. [home v3]
class PlaceActions {
  final bool Function(String id) isSaved;
  final bool Function(String id) isBusy;
  final double? Function(String id) ratingFor;
  final ValueChanged<LocationItem> onSave;
  final ValueChanged<LocationItem> onRate;
  final Listenable? changes;

  const PlaceActions({
    required this.isSaved,
    required this.isBusy,
    required this.ratingFor,
    required this.onSave,
    required this.onRate,
    this.changes,
  });
}

/// A Spots photo card for use outside Spots: same look, and tapping it
/// opens the same pop-up from where it sits. [home v3]
class PlacePickCard extends StatefulWidget {
  final LocationItem place;
  final double width;
  final PlaceActions actions;

  const PlacePickCard({
    super.key,
    required this.place,
    required this.width,
    required this.actions,
  });

  @override
  State<PlacePickCard> createState() => _PlacePickCardState();
}

class _PlacePickCardState extends State<PlacePickCard> {
  final ValueNotifier<String?> _lifted = ValueNotifier(null);
  bool _opening = false;

  @override
  void dispose() {
    _lifted.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || _opening) return;
    _opening = true;
    final place = widget.place;
    final a = widget.actions;
    // Hide the grid card once the pop-up has drawn its first frame, so
    // there is never a frame with neither.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _lifted.value = place.id;
    });
    await showPlacePopup(
      context,
      place: place,
      origin: box.localToGlobal(Offset.zero) & box.size,
      changes: a.changes,
      details: () => _PlaceDetails(
        place: place,
        saved: a.isSaved(place.id),
        busy: a.isBusy(place.id),
        rating: a.ratingFor(place.id),
        onSave: () => a.onSave(place),
        onRate: () => a.onRate(place),
      ),
      saved: () => a.isSaved(place.id),
      busy: () => a.isBusy(place.id),
      onSave: () => a.onSave(place),
    );
    _opening = false;
    if (mounted) _lifted.value = null;
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.actions;
    final place = widget.place;
    return _PlaceCard(
      place: place,
      width: widget.width,
      saved: a.isSaved(place.id),
      busy: a.isBusy(place.id),
      onOpen: _open,
      onSave: () => a.onSave(place),
      lifted: _lifted,
    );
  }
}

/// The photo with its category-colored fade, name, category · price and
/// heart; shared by the grid card and the expanded card. [home v3]
class _PlacePhoto extends StatelessWidget {
  final LocationItem place;
  final bool large;
  final bool saved;
  final bool busy;
  final VoidCallback onSave;

  const _PlacePhoto({
    required this.place,
    required this.large,
    required this.saved,
    required this.busy,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final fade = Color.lerp(
      place.gradientColors.first,
      const Color(0xFF0B1424),
      0.35,
    )!;
    return Stack(
      fit: StackFit.expand,
      children: [
        DestinationPhoto(location: place, compact: !large),
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.35, 1],
                colors: [fade.withValues(alpha: 0), fade],
              ),
            ),
          ),
        ),
        // The open card saves with its Save button, so only the grid card
        // carries a heart.
        if (!large)
          Positioned(
            top: 10,
            right: 10,
            child: _HeartButton(
              key: ValueKey('spot-heart-${place.id}'),
              saved: saved,
              busy: busy,
              onTap: onSave,
            ),
          ),
        Positioned(
          left: 14,
          right: 14,
          bottom: 14,
          child: IgnorePointer(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  place.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: large ? 24 : 16,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    shadows: const [
                      Shadow(color: Color(0x55000000), blurRadius: 8),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${HomeCategory.labelFor(place.category)} · ${place.costRange}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xE6FFFFFF),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A place in the grid. It never changes size; tapping lifts it into the
/// expanded pop-up, so the other cards stay where they are. [home v3]
class _PlaceCard extends StatelessWidget {
  final LocationItem place;
  final double width;
  final bool saved;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback onSave;
  final ValueListenable<String?> lifted;

  const _PlaceCard({
    super.key,
    required this.place,
    required this.width,
    required this.saved,
    required this.busy,
    required this.onOpen,
    required this.onSave,
    required this.lifted,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: lifted,
      builder: (context, id, child) =>
          Opacity(opacity: id == place.id ? 0 : 1, child: child),
      child: _card(),
    );
  }

  Widget _card() {
    return GestureDetector(
      key: ValueKey('spot-toggle-${place.id}'),
      onTap: onOpen,
      child: Container(
        key: ValueKey('spot-${place.id}'),
        width: width,
        height: 232,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(
              color: Color(0x4D0F285A),
              blurRadius: 26,
              offset: Offset(0, 14),
              spreadRadius: -14,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: _PlacePhoto(
            place: place,
            large: false,
            saved: saved,
            busy: busy,
            onSave: onSave,
          ),
        ),
      ),
    );
  }
}

/// Opens [place] as a pop-up with a container-transform morph: the
/// background blurs and dims (like the swipe menu) while the card's frame
/// grows from [origin], its spot in the grid, into one centered size used
/// for every place. The grid card fades out as the full card fades in,
/// already laid out at its final size, so nothing reflows or jumps.
/// Closing runs it back into the grid. [home v3]
Future<void> showPlacePopup(
  BuildContext context, {
  required LocationItem place,
  required Rect origin,
  required Widget Function() details,
  required bool Function() saved,
  required bool Function() busy,
  required VoidCallback onSave,
  Listenable? changes,
}) {
  final reduce = MediaQuery.disableAnimationsOf(context);
  return Navigator.of(context, rootNavigator: true).push<void>(
    PageRouteBuilder<void>(
      opaque: false,
      barrierDismissible: true,
      barrierLabel: 'Close ${place.name}',
      barrierColor: Colors.transparent,
      transitionDuration: Duration(milliseconds: reduce ? 150 : 520),
      reverseTransitionDuration: Duration(milliseconds: reduce ? 150 : 400),
      pageBuilder: (context, animation, _) => _PlacePopup(
        place: place,
        origin: origin,
        animation: animation,
        reduce: reduce,
        details: details,
        saved: saved,
        busy: busy,
        onSave: onSave,
        changes: changes,
      ),
    ),
  );
}

/// Material's emphasized curves: a quick start that settles slowly, and a
/// gentle lift-off on the way back.
const _emphasized = Cubic(0.2, 0, 0, 1);
const _emphasizedBack = Cubic(0.3, 0, 0.8, 0.15);

class _PlacePopup extends StatelessWidget {
  final LocationItem place;
  final Rect origin;
  final Animation<double> animation;
  final bool reduce;
  final Widget Function() details;
  final bool Function() saved;
  final bool Function() busy;
  final VoidCallback onSave;
  final Listenable? changes;

  const _PlacePopup({
    required this.place,
    required this.origin,
    required this.animation,
    required this.reduce,
    required this.details,
    required this.saved,
    required this.busy,
    required this.onSave,
    required this.changes,
  });

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    // One expanded size for every place.
    final width = (screen.width - 32).clamp(0.0, 420.0);
    final height = (screen.height - pad.vertical - 72).clamp(0.0, 590.0);
    final target = Rect.fromLTWH(
      (screen.width - width) / 2,
      pad.top + (screen.height - pad.vertical - height) / 2,
      width,
      height,
    );
    final fade = CurvedAnimation(parent: animation, curve: Curves.easeOut);
    final grow = CurvedAnimation(
      parent: animation,
      curve: _emphasized,
      reverseCurve: _emphasizedBack.flipped,
    );
    void close() => Navigator.of(context).pop();

    // The full card, built once at its final size.
    final full = SizedBox(
      width: target.width,
      height: target.height,
      child: ListenableBuilder(
        listenable: changes ?? const AlwaysStoppedAnimation(0),
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 290,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _PlacePhoto(
                    place: place,
                    large: true,
                    saved: saved(),
                    busy: busy(),
                    onSave: onSave,
                  ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: _CloseButton(onTap: close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                child: details(),
              ),
            ),
          ],
        ),
      ),
    );
    // The grid card as it looked, at its own size.
    final small = SizedBox(
      width: origin.width,
      height: origin.height,
      child: _PlacePhoto(
        place: place,
        large: false,
        saved: saved(),
        busy: busy(),
        onSave: onSave,
      ),
    );

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            key: const ValueKey('spot-popup-backdrop'),
            onTap: close,
            child: FadeTransition(
              opacity: fade,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                child: const ColoredBox(color: Color(0x590A1830)),
              ),
            ),
          ),
        ),
        AnimatedBuilder(
          animation: grow,
          builder: (context, _) {
            final t = reduce ? 1.0 : grow.value;
            final rect = Rect.lerp(origin, target, t)!;
            final radius = BorderRadius.circular(24 + 4 * t);
            // The grid card fades out early; the full card fades in a beat
            // later. Both scale with the frame's width, so neither reflows.
            final smallOpacity = reduce
                ? 0.0
                : 1 - const Interval(0, 0.35).transform(t);
            final fullOpacity = reduce
                ? fade.value
                : const Interval(0.15, 0.6).transform(t);
            return Positioned.fromRect(
              rect: rect,
              child: Material(
                type: MaterialType.transparency,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color.lerp(
                      place.gradientColors.first,
                      Colors.white,
                      const Interval(0.1, 0.5).transform(t),
                    ),
                    borderRadius: radius,
                    boxShadow: [
                      BoxShadow(
                        color: Color.lerp(
                          const Color(0x4D0F285A),
                          const Color(0x8C000000),
                          t,
                        )!,
                        blurRadius: 26 + 14 * t,
                        offset: Offset(0, 14 + 8 * t),
                        spreadRadius: -14,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: radius,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (smallOpacity > 0)
                          IgnorePointer(
                            child: Opacity(
                              opacity: smallOpacity,
                              child: _ScaledToWidth(
                                width: rect.width,
                                child: small,
                              ),
                            ),
                          ),
                        Opacity(
                          opacity: fullOpacity,
                          child: _ScaledToWidth(width: rect.width, child: full),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

/// Lays [child] out at its own fixed size and scales it to [width], pinned
/// to the top, so the morph never reflows its text.
class _ScaledToWidth extends StatelessWidget {
  final double width;
  final SizedBox child;

  const _ScaledToWidth({required this.width, required this.child});

  @override
  Widget build(BuildContext context) {
    final w = child.width!;
    final h = child.height!;
    return OverflowBox(
      alignment: Alignment.topCenter,
      minWidth: w,
      maxWidth: w,
      minHeight: h,
      maxHeight: h,
      child: Transform.scale(
        scale: w == 0 ? 1 : width / w,
        alignment: Alignment.topCenter,
        child: child,
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  final VoidCallback onTap;

  const _CloseButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Close',
      child: GestureDetector(
        key: const ValueKey('spot-popup-close'),
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xEBFFFFFF),
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.close_rounded,
            size: 19,
            color: AppTheme.slateDark,
          ),
        ),
      ),
    );
  }
}

/// Everything about a place, below the photo in the expanded card.
class _PlaceDetails extends StatelessWidget {
  final LocationItem place;
  final bool saved;
  final bool busy;
  final double? rating;
  final VoidCallback onSave;
  final VoidCallback onRate;

  const _PlaceDetails({
    required this.place,
    required this.saved,
    required this.busy,
    required this.rating,
    required this.onSave,
    required this.onRate,
  });

  @override
  Widget build(BuildContext context) {
    Widget info(IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppTheme.primaryBlue),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: AppTheme.slateDark,
              ),
            ),
          ),
        ],
      ),
    );

    return Column(
      key: ValueKey('spot-details-${place.id}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (place.description.isNotEmpty) ...[
          Text(
            place.description,
            style: const TextStyle(
              fontSize: 14.5,
              height: 1.45,
              color: Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (place.vibeTags.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final tag in place.vibeTags)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '#$tag',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1D4ED8),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
        ],
        info(Icons.place_outlined, place.address),
        info(Icons.schedule_rounded, place.duration),
        info(Icons.payments_outlined, place.costRange),
        if (rating != null)
          info(
            Icons.star_rounded,
            'You rated it ${rating!.toStringAsFixed(rating! % 1 == 0 ? 0 : 1)}',
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                key: ValueKey('spot-save-${place.id}'),
                onPressed: busy ? null : onSave,
                style: FilledButton.styleFrom(
                  backgroundColor: saved
                      ? const Color(0xFFFFEDD5)
                      : const Color(0xFFF2620F),
                  foregroundColor: saved
                      ? const Color(0xFFC2410C)
                      : Colors.white,
                  shape: const StadiumBorder(),
                  minimumSize: const Size.fromHeight(46),
                ),
                icon: Icon(
                  saved
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  size: 18,
                ),
                label: Text(saved ? 'Saved' : 'Save'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                key: ValueKey('spot-rate-${place.id}'),
                onPressed: busy ? null : onRate,
                style: OutlinedButton.styleFrom(
                  shape: const StadiumBorder(),
                  minimumSize: const Size.fromHeight(46),
                ),
                icon: const Icon(Icons.star_border_rounded, size: 18),
                label: Text(rating == null ? 'Rate' : 'Rate again'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _HeartButton extends StatelessWidget {
  final bool saved;
  final bool busy;
  final VoidCallback onTap;

  const _HeartButton({
    super.key,
    required this.saved,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: saved ? 'Saved' : 'Save',
      child: GestureDetector(
        onTap: busy ? null : onTap,
        child: Container(
          width: 34,
          height: 34,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xEBFFFFFF),
          ),
          alignment: Alignment.center,
          child: busy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  saved
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  size: 18,
                  color: const Color(0xFFF2620F),
                ),
        ),
      ),
    );
  }
}
