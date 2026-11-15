import 'package:flutter/material.dart';

import '../models/trip.dart';
import '../models/trip_item.dart';
import '../screens/destination_picker_sheet.dart';
import '../services/api_service.dart';
import '../services/trip_service.dart';
import '../theme.dart';
import '../utils/trip_format.dart';
import 'confirm_dialog.dart';
import 'destination_photo.dart';
import 'status_banner.dart';

/// "Itinerary Locations" on Trip Details: the trip's saved itinerary items,
/// grouped by day, with manual add and remove. All data comes from the
/// FastAPI item endpoints; nothing is hardcoded. [S3-34]
class ItineraryLocationsSection extends StatefulWidget {
  final TripService service;
  final ApiService locations;
  final Trip trip;

  const ItineraryLocationsSection({
    super.key,
    required this.service,
    required this.locations,
    required this.trip,
  });

  @override
  State<ItineraryLocationsSection> createState() =>
      _ItineraryLocationsSectionState();
}

class _ItineraryLocationsSectionState extends State<ItineraryLocationsSection> {
  List<TripItem>? _items;
  bool _loading = true;
  String? _error;
  String? _notice;
  final Set<String> _removing = {};

  /// The backend clears a trip's estimated total on any manual item change,
  /// so hide the total locally instead of showing a stale figure.
  bool _totalCleared = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Keeps the current list on screen while reloading, so a failed refresh
  /// never wipes what the user was looking at.
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await widget.service.listTripItems(widget.trip.id);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } on TripApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  Future<void> _add() async {
    final added = await showDestinationPicker(
      context,
      service: widget.service,
      locations: widget.locations,
      trip: widget.trip,
      existing: _items ?? const [],
    );
    if (added == null || !mounted) return;
    setState(() {
      _notice = 'Added ${added.location.name} to Day ${added.dayNumber}.';
      _totalCleared = true;
    });
    await _load();
  }

  Future<void> _remove(TripItem item) async {
    if (_removing.contains(item.id)) return;
    final confirmed = await showTactileConfirmDialog(
      context,
      title: 'Remove this destination?',
      message:
          '"${item.location.name}" will be taken off Day ${item.dayNumber}. '
          'You can add it again later.',
      confirmLabel: 'Remove',
      icon: Icons.wrong_location_rounded,
    );
    if (!confirmed || !mounted) return;

    setState(() {
      _removing.add(item.id);
      _error = null;
      _notice = null;
    });
    try {
      await widget.service.removeTripItem(widget.trip.id, item.id);
      if (!mounted) return;
      setState(() {
        _removing.remove(item.id);
        _notice = 'Removed ${item.location.name}.';
        _totalCleared = true;
      });
      await _load();
    } on TripApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _removing.remove(item.id);
        _error = e.message;
      });
      // Already gone elsewhere: show the fresh list instead of a stale row.
      if (e.statusCode == 404) await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Column(
      key: const ValueKey('itinerary-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(),
        if (widget.trip.estimatedTotalCost != null && !_totalCleared) ...[
          const SizedBox(height: 6),
          Text(
            'Estimated total: ${formatPeso(widget.trip.estimatedTotalCost!)}',
            key: const ValueKey('itinerary-total'),
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13.5,
              color: Color(0xFF16A34A),
            ),
          ),
        ],
        if (_notice != null) ...[
          const SizedBox(height: 12),
          StatusBanner(
            key: const ValueKey('itinerary-notice'),
            tone: StatusTone.success,
            message: _notice!,
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          StatusBanner(
            key: const ValueKey('itinerary-error'),
            tone: StatusTone.error,
            message: _error!,
            actionLabel: 'Retry',
            onAction: _load,
          ),
        ],
        const SizedBox(height: 14),
        if (items == null && _loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: CircularProgressIndicator(color: Color(0xFFF2620F)),
            ),
          )
        else if (items != null && items.isEmpty)
          _emptyState()
        else if (items != null)
          ..._dayGroups(items),
      ],
    );
  }

  Widget _header() {
    return Row(
      children: [
        const Expanded(
          child: Text(
            'Your stops',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 19,
              letterSpacing: -0.3,
              color: AppTheme.slateDark,
            ),
          ),
        ),
        if (_loading && _items != null)
          const Padding(
            padding: EdgeInsets.only(right: 10),
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        OutlinedButton.icon(
          key: const ValueKey('itinerary-add'),
          onPressed: _items == null ? null : _add,
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFF2620F),
            side: const BorderSide(color: Color(0xFFFBD5BD)),
            shape: const StadiumBorder(),
            visualDensity: VisualDensity.compact,
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Add a stop'),
        ),
      ],
    );
  }

  Widget _emptyState() {
    return Container(
      key: const ValueKey('itinerary-empty'),
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 18),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F8FC),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Column(
        children: [
          Icon(
            Icons.add_location_alt_outlined,
            size: 30,
            color: AppTheme.slateMuted,
          ),
          SizedBox(height: 8),
          Text(
            'No stops yet',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: AppTheme.slateDark,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Plan with AI, or add Bacolod spots you want to visit.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 13.5,
              color: AppTheme.slateMuted,
            ),
          ),
        ],
      ),
    );
  }

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// "Day 2 · Sun, Nov 11".
  String _dayLabel(int day) {
    final date = widget.trip.startDate.add(Duration(days: day - 1));
    return 'Day $day · ${_weekdays[date.weekday - 1]}, '
        '${_months[date.month - 1]} ${date.day}';
  }

  List<Widget> _dayGroups(List<TripItem> items) {
    final byDay = <int, List<TripItem>>{};
    for (final item in items) {
      byDay.putIfAbsent(item.dayNumber, () => []).add(item);
    }
    final days = byDay.keys.toList()..sort();
    return [
      for (final day in days) ...[
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 10),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppTheme.skyTop, AppTheme.skyMid],
                  ),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _dayLabel(day),
                  key: ValueKey('itinerary-day-$day'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
        for (final (i, item)
            in (byDay[day]!
                  ..sort((a, b) => a.visitOrder.compareTo(b.visitOrder)))
                .indexed)
          _stop(item, last: i == byDay[day]!.length - 1),
        const SizedBox(height: 8),
      ],
    ];
  }

  /// One stop on the day's timeline: number and line on the left, then the
  /// photo, name, time and cost. Generated stops show their schedule; ones
  /// you added show "Added by you". No ranking internals. [home v3]
  Widget _stop(TripItem item, {required bool last}) {
    final place = item.location;
    return IntrinsicHeight(
      key: ValueKey('itinerary-item-${item.id}'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 30,
            child: Column(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFFF2620F),
                  ),
                  child: Text(
                    '${item.visitOrder}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
                if (!last)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: const Color(0xFFE3E9F2),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F8FC),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: DestinationPhoto(
                        location: place,
                        width: 52,
                        height: 52,
                        compact: true,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            place.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14.5,
                              height: 1.15,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.slateDark,
                            ),
                          ),
                          const SizedBox(height: 3),
                          _schedule(item),
                        ],
                      ),
                    ),
                    _removeButton(item),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _schedule(TripItem item) {
    const muted = TextStyle(
      fontWeight: FontWeight.w600,
      fontSize: 12.5,
      color: AppTheme.slateMuted,
    );
    if (!item.isScheduled && item.estimatedCost == null) {
      return Text(
        'Added by you',
        key: ValueKey('itinerary-manual-${item.id}'),
        style: muted,
      );
    }
    final parts = [
      if (item.isScheduled)
        '${formatClock(item.arrivalTime!)} – ${formatClock(item.departureTime!)}',
      if (item.estimatedCost != null) formatPeso(item.estimatedCost!),
    ];
    return Column(
      key: ValueKey('itinerary-schedule-${item.id}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (parts.isNotEmpty)
          Text(
            parts.join(' · '),
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
              color: AppTheme.primaryBlue,
            ),
          ),
        if (item.estimatedTravelTime != null)
          Text('${item.estimatedTravelTime} min to get here', style: muted),
      ],
    );
  }

  Widget _removeButton(TripItem item) {
    final busy = _removing.contains(item.id);
    return SizedBox(
      width: 34,
      height: 34,
      child: busy
          ? const Padding(
              padding: EdgeInsets.all(9),
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFFE11D48),
              ),
            )
          : IconButton(
              key: ValueKey('itinerary-remove-${item.id}'),
              tooltip: 'Remove ${item.location.name}',
              padding: EdgeInsets.zero,
              onPressed: () => _remove(item),
              icon: const Icon(
                Icons.close_rounded,
                size: 19,
                color: AppTheme.slateMuted,
              ),
            ),
    );
  }
}
