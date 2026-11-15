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

  String get _countLabel => _loading && _trips.isEmpty
      ? 'Loading your trips…'
      : _hasMore
      ? '${_trips.length}+ saved trips'
      : _trips.length == 1
      ? '1 saved trip'
      : '${_trips.length} saved trips';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Centered like "Explore Bacolod" on Spots. [home v3]
        const Text(
          'My Trips',
          key: ValueKey('trips-title'),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 40,
            height: 1,
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
          _countLabel,
          key: const ValueKey('trips-count'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xEBFFFFFF),
          ),
        ),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _PlanTripButton(
              key: const ValueKey('trips-create'),
              onTap: _create,
            ),
            const SizedBox(width: 10),
            _RoundButton(
              key: const ValueKey('trips-refresh'),
              label: 'Refresh trips',
              icon: Icons.refresh_rounded,
              onTap: _loading ? null : _load,
            ),
          ],
        ),
        const SizedBox(height: 22),
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
            child: _SoftPillButton(
              key: const ValueKey('trips-load-more'),
              label: _loadingMore ? 'Loading…' : 'Load more',
              onTap: _loadingMore ? null : _loadMore,
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

/// The orange pill used for the main action across the v3 screens.
class _PlanTripButton extends StatelessWidget {
  final VoidCallback onTap;

  const _PlanTripButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFFF2620F),
        foregroundColor: Colors.white,
        shape: const StadiumBorder(),
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        elevation: 0,
        shadowColor: Colors.transparent,
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
      ),
      icon: const Icon(Icons.add_rounded, size: 20),
      label: const Text('Plan a new trip'),
    );
  }
}

/// A white circle with an icon, like the greeting pill's buttons.
class _RoundButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  const _RoundButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 48,
          height: 48,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xF5FFFFFF),
            boxShadow: [
              BoxShadow(
                color: Color(0x330F1B2D),
                blurRadius: 20,
                offset: Offset(0, 8),
                spreadRadius: -10,
              ),
            ],
          ),
          child: Icon(
            icon,
            size: 21,
            color: onTap == null ? AppTheme.slateMuted : AppTheme.slateDark,
          ),
        ),
      ),
    );
  }
}

class _SoftPillButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const _SoftPillButton({super.key, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        backgroundColor: const Color(0xF5FFFFFF),
        foregroundColor: AppTheme.slateDark,
        side: BorderSide.none,
        shape: const StadiumBorder(),
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 22),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
      child: Text(label),
    );
  }
}

class _EmptyTrips extends StatelessWidget {
  final VoidCallback onCreate;

  const _EmptyTrips({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return FadeSlideIn(
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 28, 22, 24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: const [
            BoxShadow(
              color: Color(0x4D0F285A),
              blurRadius: 30,
              offset: Offset(0, 16),
              spreadRadius: -16,
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: Color(0xFFFFF3EA),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.luggage_rounded,
                size: 30,
                color: Color(0xFFF2620F),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'No trips yet',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 22,
                letterSpacing: -0.4,
                color: AppTheme.slateDark,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Plan your first Bacolod lagaw: dates, budget and vibes.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 14,
                height: 1.4,
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
