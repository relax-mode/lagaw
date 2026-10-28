import 'package:flutter/material.dart';

import '../models/trip.dart';
import '../models/trip_item.dart';
import '../screens/destination_picker_sheet.dart';
import '../services/api_service.dart';
import '../services/trip_service.dart';
import '../theme.dart';
import 'confirm_dialog.dart';
import 'destination_tile.dart';
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
    setState(
      () => _notice = 'Added ${added.location.name} to Day ${added.dayNumber}.',
    );
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
    return GlassContainer(
      key: const ValueKey('itinerary-section'),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(),
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
          const SizedBox(height: 12),
          if (items == null && _loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (items != null && items.isEmpty)
            _emptyState()
          else if (items != null)
            ..._dayGroups(items),
        ],
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        const Icon(Icons.map_rounded, color: AppTheme.primaryBlue, size: 20),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            'Itinerary Locations',
            style: TextStyle(
              fontFamily: 'Outfit',
              fontWeight: FontWeight.w900,
              fontSize: 17,
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
        Vector3DButton(
          key: const ValueKey('itinerary-add'),
          onTap: _items == null ? null : _add,
          backgroundColor: AppTheme.primaryBlue,
          shadowColor: const Color(0xFF1D4ED8),
          borderColor: const Color(0xFF93C5FD),
          borderRadius: 18,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          depth: 3,
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_rounded, color: Colors.white, size: 16),
              SizedBox(width: 4),
              Text(
                'Add destination',
                style: TextStyle(
                  fontFamily: 'Outfit',
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _emptyState() {
    return Container(
      key: const ValueKey('itinerary-empty'),
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
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
            'No destinations yet',
            style: TextStyle(
              fontFamily: 'Outfit',
              fontWeight: FontWeight.w900,
              fontSize: 15,
              color: AppTheme.slateDark,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Add Bacolod spots you want to visit on this trip.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 12.5,
              color: AppTheme.slateMuted,
            ),
          ),
        ],
      ),
    );
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
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: Text(
            'Day $day',
            key: ValueKey('itinerary-day-$day'),
            style: const TextStyle(
              fontFamily: 'Outfit',
              fontWeight: FontWeight.w900,
              fontSize: 14,
              color: AppTheme.primaryBlue,
            ),
          ),
        ),
        for (final item
            in byDay[day]!
              ..sort((a, b) => a.visitOrder.compareTo(b.visitOrder))) ...[
          DestinationTile(
            key: ValueKey('itinerary-item-${item.id}'),
            location: item.location,
            badge: '${item.visitOrder}',
            trailing: _removeButton(item),
          ),
          const SizedBox(height: 8),
        ],
      ],
    ];
  }

  Widget _removeButton(TripItem item) {
    final busy = _removing.contains(item.id);
    return SizedBox(
      width: 36,
      height: 36,
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
                Icons.remove_circle_outline_rounded,
                color: Color(0xFFE11D48),
              ),
            ),
    );
  }
}
