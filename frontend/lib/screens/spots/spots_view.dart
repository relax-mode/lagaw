import 'package:flutter/material.dart';

import '../../models/location.dart';
import '../../theme.dart';
import '../../widgets/destination_photo.dart';
import '../../widgets/floating_elements.dart';
import '../../widgets/greeting_pill.dart';
import '../home/home_view.dart' show HomeCategory;

/// The v3 Spots page: the same greeting pill and floating elements as home,
/// a glass search, category chips built from the real data, and places as
/// photo cards that expand in place to show everything. [home v3]
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
  String? _expanded;

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
    if (_expanded != null && !widget.places.any((p) => p.id == _expanded)) {
      _expanded = null;
    }
  }

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
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

  void _toggle(String id) {
    setState(() => _expanded = _expanded == id ? null : id);
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.places.length;
    return Stack(
      clipBehavior: Clip.none,
      children: [
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
      crossAxisAlignment: CrossAxisAlignment.start,
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
                key: ValueKey('spot-${place.id}'),
                place: place,
                width: _expanded == place.id ? box.maxWidth : half,
                expanded: _expanded == place.id,
                saved: widget.isSaved(place.id),
                busy: widget.isBusy(place.id),
                rating: widget.ratingFor(place.id),
                onToggle: () => _toggle(place.id),
                onSave: () => widget.onSave(place),
                onRate: () => widget.onRate(place),
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

/// A place as a photo card with a color fade; tapping expands it in place
/// to show the description, details, and Save / Rate. [home v3]
class _PlaceCard extends StatelessWidget {
  final LocationItem place;
  final double width;
  final bool expanded;
  final bool saved;
  final bool busy;
  final double? rating;
  final VoidCallback onToggle;
  final VoidCallback onSave;
  final VoidCallback onRate;

  const _PlaceCard({
    super.key,
    required this.place,
    required this.width,
    required this.expanded,
    required this.saved,
    required this.busy,
    required this.rating,
    required this.onToggle,
    required this.onSave,
    required this.onRate,
  });

  /// The category color, deepened, for the bottom fade.
  Color get _fade =>
      Color.lerp(place.gradientColors.first, const Color(0xFF0B1424), 0.35)!;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeInOutCubic,
      width: width,
      decoration: BoxDecoration(
        color: Colors.white,
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
        child: AnimatedSize(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeInOutCubic,
          alignment: Alignment.topCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GestureDetector(
                key: ValueKey('spot-toggle-${place.id}'),
                onTap: onToggle,
                child: SizedBox(
                  height: expanded ? 210 : 232,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      DestinationPhoto(location: place, compact: !expanded),
                      IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              stops: const [0.35, 1],
                              colors: [_fade.withValues(alpha: 0), _fade],
                            ),
                          ),
                        ),
                      ),
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
                        child: IgnorePointer(child: _caption()),
                      ),
                    ],
                  ),
                ),
              ),
              // Details join once the card is wide enough for them, so
              // nothing squeezes while the width animates.
              if (expanded)
                LayoutBuilder(
                  builder: (context, box) => box.maxWidth < 280
                      ? const SizedBox(width: double.infinity)
                      : _details(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _caption() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          place.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: expanded ? 22 : 16,
            height: 1.1,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            shadows: const [Shadow(color: Color(0x55000000), blurRadius: 8)],
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
    );
  }

  Widget _details() {
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

    return Padding(
      key: ValueKey('spot-details-${place.id}'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (place.description.isNotEmpty) ...[
            Text(
              place.description,
              style: const TextStyle(
                fontSize: 14,
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
            const SizedBox(height: 12),
          ],
          info(Icons.place_outlined, place.address),
          info(Icons.schedule_rounded, place.duration),
          info(Icons.payments_outlined, place.costRange),
          if (rating != null)
            info(
              Icons.star_rounded,
              'You rated it ${rating!.toStringAsFixed(rating! % 1 == 0 ? 0 : 1)}',
            ),
          const SizedBox(height: 6),
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
                  style: OutlinedButton.styleFrom(shape: const StadiumBorder()),
                  icon: const Icon(Icons.star_border_rounded, size: 18),
                  label: Text(rating == null ? 'Rate' : 'Rate again'),
                ),
              ),
            ],
          ),
          Center(
            child: TextButton.icon(
              key: ValueKey('spot-less-${place.id}'),
              onPressed: onToggle,
              icon: const Icon(Icons.keyboard_arrow_up_rounded),
              label: const Text('Show less'),
            ),
          ),
        ],
      ),
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
