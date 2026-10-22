import 'package:flutter/material.dart';

import '../models/trip.dart';
import '../services/trip_service.dart';
import '../theme.dart';
import '../widgets/status_banner.dart';
import '../widgets/tactile_motion.dart';
import '../widgets/trip_card.dart';
import 'trip_create_screen.dart';
import 'trip_detail_screen.dart';

/// "My Trips" tab: saved trips from `GET /api/v1/trips`, with entry points
/// to create, view, edit and delete. Lives inside the home screen's scroll
/// view. [S2-04, S2-05]
class TripsTab extends StatefulWidget {
  final TripService service;
  final bool isWide;

  const TripsTab({super.key, required this.service, required this.isWide});

  @override
  State<TripsTab> createState() => _TripsTabState();
}

class _TripsTabState extends State<TripsTab> {
  static const int _pageSize = 50;

  List<Trip> _trips = const [];
  bool _loading = true;
  String? _error;
  String? _notice;

  /// A full page came back, so the server may have more trips.
  bool _hasMore = false;
  bool _loadingMore = false;
  String? _loadMoreError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.service.listTrips(limit: _pageSize);
      if (!mounted) return;
      setState(() {
        _trips = page.items;
        _hasMore = page.items.length == _pageSize;
        _loadMoreError = null;
        _loading = false;
      });
    } on TripApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    setState(() {
      _loadingMore = true;
      _loadMoreError = null;
    });
    try {
      final page = await widget.service.listTrips(
        limit: _pageSize,
        offset: _trips.length,
      );
      if (!mounted) return;
      setState(() {
        final known = {for (final t in _trips) t.id};
        _trips = [..._trips, ...page.items.where((t) => !known.contains(t.id))];
        _hasMore = page.items.length == _pageSize;
        _loadingMore = false;
      });
    } on TripApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadMoreError = e.message;
        _loadingMore = false;
      });
    }
  }

  /// Opens [page]; whatever happened there, the list is re-fetched after.
  Future<Object?> _open(Widget page) async {
    final result = await Navigator.of(context)
        .push<Object?>(MaterialPageRoute(builder: (_) => page));
    if (mounted) {
      setState(() => _notice = null);
      _load();
    }
    return result;
  }

  void _create() => _open(TripCreateScreen(service: widget.service));

  Future<void> _openTrip(Trip trip) async {
    final result = await _open(
      TripDetailScreen(service: widget.service, tripId: trip.id, initial: trip),
    );
    if (result == TripDetailResult.deleted && mounted) {
      // Drop it right away; the reload started by _open confirms it.
      setState(() {
        _trips = _trips.where((t) => t.id != trip.id).toList();
        _notice = 'Trip deleted.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'My Trips',
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontWeight: FontWeight.w900,
                      fontSize: 26,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    _loading
                        ? 'Loading your trips…'
                        : _hasMore
                        ? '${_trips.length}+ saved trips'
                        : _trips.length == 1
                        ? '1 saved trip'
                        : '${_trips.length} saved trips',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                      color: Color(0xE6FFFFFF),
                    ),
                  ),
                ],
              ),
            ),
            Vector3DButton(
              key: const ValueKey('trips-refresh'),
              onTap: _loading ? null : _load,
              backgroundColor: Colors.white,
              shadowColor: const Color(0xFFCBD5E1),
              borderColor: const Color(0xFFE2E8F0),
              borderRadius: 18,
              padding: const EdgeInsets.all(9),
              depth: 3,
              child: const Icon(
                Icons.refresh_rounded,
                size: 20,
                color: AppTheme.slateDark,
              ),
            ),
            const SizedBox(width: 10),
            _PlanTripButton(
              key: const ValueKey('trips-create'),
              onTap: _create,
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_notice != null) ...[
          StatusBanner(
            key: const ValueKey('trips-notice'),
            tone: StatusTone.success,
            message: _notice!,
          ),
          const SizedBox(height: 14),
        ],
        if (_error != null)
          StatusBanner(
            key: const ValueKey('trips-error'),
            tone: StatusTone.error,
            message: _error!,
            actionLabel: 'Retry',
            onAction: _load,
          )
        else if (_loading && _trips.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 60),
            child: Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          )
        else if (_trips.isEmpty)
          _EmptyTrips(onCreate: _create)
        else
          _buildList(),
        if (_trips.isNotEmpty && _loadMoreError != null) ...[
          const SizedBox(height: 14),
          StatusBanner(
            key: const ValueKey('trips-more-error'),
            tone: StatusTone.error,
            message: _loadMoreError!,
            actionLabel: 'Retry',
            onAction: _loadMore,
          ),
        ] else if (_trips.isNotEmpty && _hasMore) ...[
          SizedBox(height: widget.isWide ? 18 : 6),
          Center(
            child: Vector3DButton(
              key: const ValueKey('trips-load-more'),
              onTap: _loadingMore ? null : _loadMore,
              backgroundColor: Colors.white,
              shadowColor: const Color(0xFFCBD5E1),
              borderColor: const Color(0xFFE2E8F0),
              borderRadius: 22,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              depth: 3,
              child: Text(
                _loadingMore ? 'Loading…' : 'Load more',
                style: const TextStyle(
                  fontFamily: 'Outfit',
                  fontWeight: FontWeight.w900,
                  fontSize: 13.5,
                  color: AppTheme.slateDark,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildList() {
    final cards = [
      for (final (i, trip) in _trips.indexed)
        FadeSlideIn(
          key: ValueKey(trip.id),
          index: i,
          child: TripCard(trip: trip, onTap: () => _openTrip(trip)),
        ),
    ];

    if (!widget.isWide) {
      return Column(
        children: [
          for (final card in cards)
            Padding(padding: const EdgeInsets.only(bottom: 12), child: card),
        ],
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 16) / 2;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            for (final card in cards) SizedBox(width: width, child: card),
          ],
        );
      },
    );
  }
}

class _PlanTripButton extends StatelessWidget {
  final VoidCallback onTap;

  const _PlanTripButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Vector3DButton(
      onTap: onTap,
      backgroundColor: const Color(0xFFEA580C),
      shadowColor: const Color(0xFF9A3412),
      borderColor: const Color(0xFFFDBA74),
      borderRadius: 22,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      depth: 3.5,
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.add_rounded, size: 18, color: Colors.white),
          SizedBox(width: 4),
          Text(
            'New trip',
            style: TextStyle(
              fontFamily: 'Outfit',
              fontWeight: FontWeight.w900,
              fontSize: 13,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyTrips extends StatelessWidget {
  final VoidCallback onCreate;

  const _EmptyTrips({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return FadeSlideIn(
      child: GlassContainer(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFFED7AA), width: 2),
              ),
              child: const Icon(
                Icons.luggage_rounded,
                size: 30,
                color: Color(0xFFEA580C),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'No trips yet',
              style: TextStyle(
                fontFamily: 'Outfit',
                fontWeight: FontWeight.w900,
                fontSize: 18,
                color: AppTheme.slateDark,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Plan your first Bacolod lagaw: dates, budget and vibes.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: AppTheme.slateMuted,
              ),
            ),
            const SizedBox(height: 18),
            _PlanTripButton(
              key: const ValueKey('trips-create-empty'),
              onTap: onCreate,
            ),
          ],
        ),
      ),
    );
  }
}
