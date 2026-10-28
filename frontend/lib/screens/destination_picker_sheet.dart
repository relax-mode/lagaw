import 'package:flutter/material.dart';

import '../models/location.dart';
import '../models/trip.dart';
import '../models/trip_item.dart';
import '../services/api_service.dart';
import '../services/trip_service.dart';
import '../theme.dart';
import '../utils/trip_format.dart';
import '../widgets/destination_tile.dart';
import '../widgets/status_banner.dart';

/// Lets the user pick an existing Bacolod location and a day, then saves it
/// through `POST /api/v1/trips/{id}/items`. Resolves the saved item, or null
/// when dismissed. [S3-34]
Future<TripItem?> showDestinationPicker(
  BuildContext context, {
  required TripService service,
  required ApiService locations,
  required Trip trip,
  required List<TripItem> existing,
}) {
  return showModalBottomSheet<TripItem>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x660F172A),
    builder: (_) => DestinationPickerSheet(
      service: service,
      locations: locations,
      trip: trip,
      existing: existing,
    ),
  );
}

class DestinationPickerSheet extends StatefulWidget {
  final TripService service;
  final ApiService locations;
  final Trip trip;
  final List<TripItem> existing;

  const DestinationPickerSheet({
    super.key,
    required this.service,
    required this.locations,
    required this.trip,
    required this.existing,
  });

  @override
  State<DestinationPickerSheet> createState() => _DestinationPickerSheetState();
}

class _DestinationPickerSheetState extends State<DestinationPickerSheet> {
  List<LocationItem>? _options;
  bool _loading = true;
  String? _loadError;
  String? _saveError;
  bool _submitting = false;
  LocationItem? _selected;
  int _day = 1;

  int get _dayCount => tripDayCount(widget.trip.startDate, widget.trip.endDate);

  /// Appends after the day's last stop; orders need not be contiguous.
  int get _nextOrder {
    var last = 0;
    for (final item in widget.existing) {
      if (item.dayNumber == _day && item.visitOrder > last) {
        last = item.visitOrder;
      }
    }
    return last + 1;
  }

  @override
  void initState() {
    super.initState();
    _loadOptions();
  }

  Future<void> _loadOptions() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final options = await widget.locations.fetchAllLocations();
      if (!mounted) return;
      setState(() {
        _options = options;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = 'Could not load Bacolod destinations. Please try again.';
      });
    }
  }

  Future<void> _submit() async {
    final location = _selected;
    if (location == null || _submitting) return;
    setState(() {
      _submitting = true;
      _saveError = null;
    });
    try {
      final item = await widget.service.addTripItem(
        widget.trip.id,
        locationId: location.id,
        dayNumber: _day,
        visitOrder: _nextOrder,
      );
      if (mounted) Navigator.of(context).pop(item);
    } on TripApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _saveError =
            e.fieldErrors['day_number'] ??
            e.fieldErrors['visit_order'] ??
            e.fieldErrors['location_id'] ??
            e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.88;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight, maxWidth: 640),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: GlassContainer(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Add a destination',
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                    color: AppTheme.slateDark,
                  ),
                ),
                const SizedBox(height: 12),
                _dayPicker(),
                const SizedBox(height: 12),
                Flexible(child: _optionsList()),
                if (_saveError != null) ...[
                  const SizedBox(height: 12),
                  StatusBanner(
                    key: const ValueKey('picker-save-error'),
                    tone: StatusTone.error,
                    message: _saveError!,
                  ),
                ],
                const SizedBox(height: 14),
                _submitButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dayPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Day · stop #$_nextOrder',
          style: const TextStyle(
            fontFamily: 'Outfit',
            fontWeight: FontWeight.w800,
            fontSize: 13,
            color: AppTheme.slateMuted,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var day = 1; day <= _dayCount; day++)
              ChoiceChip(
                key: ValueKey('picker-day-$day'),
                label: Text('Day $day'),
                selected: _day == day,
                onSelected: _submitting
                    ? null
                    : (_) => setState(() {
                        _day = day;
                        _saveError = null;
                      }),
              ),
          ],
        ),
      ],
    );
  }

  Widget _optionsList() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_loadError != null) {
      return StatusBanner(
        key: const ValueKey('picker-load-error'),
        tone: StatusTone.error,
        message: _loadError!,
        actionLabel: 'Retry',
        onAction: _loadOptions,
      );
    }
    final options = _options ?? const [];
    if (options.isEmpty) {
      return const StatusBanner(
        key: ValueKey('picker-empty'),
        tone: StatusTone.info,
        message: 'No Bacolod destinations are available right now.',
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      itemCount: options.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final location = options[index];
        final selected = _selected?.id == location.id;
        return GestureDetector(
          key: ValueKey('destination-${location.id}'),
          onTap: _submitting
              ? null
              : () => setState(() {
                  _selected = location;
                  _saveError = null;
                }),
          child: DestinationTile(
            location: location,
            selected: selected,
            trailing: selected
                ? const Icon(
                    Icons.check_circle_rounded,
                    color: AppTheme.primaryBlue,
                  )
                : null,
          ),
        );
      },
    );
  }

  Widget _submitButton() {
    final enabled = _selected != null && !_submitting;
    return Vector3DButton(
      key: const ValueKey('picker-submit'),
      onTap: enabled ? _submit : null,
      backgroundColor: enabled ? AppTheme.primaryBlue : const Color(0xFF94A3B8),
      shadowColor: enabled ? const Color(0xFF1D4ED8) : const Color(0xFF64748B),
      borderColor: const Color(0xFF93C5FD),
      borderRadius: 26,
      padding: const EdgeInsets.symmetric(vertical: 14),
      depth: 4,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_submitting)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Colors.white,
              ),
            )
          else
            const Icon(Icons.add_location_alt_rounded, color: Colors.white),
          const SizedBox(width: 8),
          Text(
            _submitting ? 'Adding…' : 'Add to Day $_day',
            style: const TextStyle(
              fontFamily: 'Outfit',
              fontWeight: FontWeight.w900,
              fontSize: 15,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
