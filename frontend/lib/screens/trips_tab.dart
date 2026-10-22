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
/// to create, view and edit. Lives inside the home screen's scroll view. [S2-04]
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

  Future<void> _open(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (mounted) _load();
  }

  void _create() => _open(TripCreateScreen(service: widget.service));

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
      ],
    );
  }

  Widget _buildList() {
    final cards = [
      for (final (i, trip) in _trips.indexed)
        FadeSlideIn(
          key: ValueKey(trip.id),
          index: i,
          child: TripCard(
            trip: trip,
            onTap: () => _open(
              TripDetailScreen(
                service: widget.service,
                tripId: trip.id,
                initial: trip,
              ),
            ),
          ),
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
