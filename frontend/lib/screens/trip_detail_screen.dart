import 'package:flutter/material.dart';

import '../models/trip.dart';
import '../services/api_service.dart';
import '../services/trip_service.dart';
import '../theme.dart';
import '../utils/trip_format.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/itinerary_section.dart';
import '../widgets/status_banner.dart';
import '../widgets/tactile_motion.dart';
import '../widgets/trip_card.dart';
import '../widgets/trip_form/choice_chips_field.dart';
import '../widgets/trip_form/trip_form.dart';
import 'trip_edit_screen.dart';
import 'trip_page_scaffold.dart';

/// What a detail page tells the list when it closes.
enum TripDetailResult { deleted }

/// One saved trip, loaded through `GET /api/v1/trips/{id}`. [S2-04]
/// Pops [TripDetailResult.deleted] after a delete, or once the trip turns
/// out to be gone already, so the list can drop it. [S2-05]
class TripDetailScreen extends StatefulWidget {
  final TripService service;
  final String tripId;

  /// Shown immediately while the fresh copy loads (e.g. right after create).
  final Trip? initial;

  /// One-off success message, such as after creating the trip.
  final String? notice;

  /// Source of selectable destinations for the itinerary. [S3-34]
  final ApiService? locations;

  const TripDetailScreen({
    super.key,
    required this.service,
    required this.tripId,
    this.initial,
    this.notice,
    this.locations,
  });

  @override
  State<TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends State<TripDetailScreen> {
  Trip? _trip;
  bool _loading = true;
  String? _error;
  String? _notice;
  bool _deleting = false;

  /// The backend says this trip no longer exists (deleted elsewhere).
  bool _missing = false;

  late final ApiService _locations = widget.locations ?? ApiService();

  @override
  void initState() {
    super.initState();
    _trip = widget.initial;
    _notice = widget.notice;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final trip = await widget.service.getTrip(widget.tripId);
      if (!mounted) return;
      setState(() {
        _trip = trip;
        _loading = false;
      });
    } on TripApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (e.statusCode == 404) {
          _missing = true;
          _trip = null;
        } else {
          _error = e.message;
        }
      });
    }
  }

  void _closeAsDeleted() => Navigator.of(context).pop(TripDetailResult.deleted);

  Future<void> _delete() async {
    final trip = _trip;
    if (trip == null || _deleting) return;
    final confirmed = await showTactileConfirmDialog(
      context,
      title: 'Delete this trip?',
      message:
          '"${trip.title}" will be removed for good. This can\'t be undone.',
      confirmLabel: 'Delete',
    );
    if (!confirmed || !mounted) return;

    setState(() {
      _deleting = true;
      _error = null;
      _notice = null;
    });
    try {
      await widget.service.deleteTrip(trip.id);
      if (mounted) _closeAsDeleted();
    } on TripApiException catch (e) {
      if (!mounted) return;
      // Already gone (e.g. deleted on another device): same outcome.
      if (e.statusCode == 404) return _closeAsDeleted();
      setState(() {
        _deleting = false;
        _error = e.message;
      });
    }
  }

  Future<void> _edit() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            TripEditScreen(service: widget.service, tripId: widget.tripId),
      ),
    );
    if (saved == true && mounted) {
      setState(() => _notice = 'Changes saved.');
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final trip = _trip;

    return TripPageScaffold(
      title: trip?.title ?? 'your trip',
      subtitle: trip == null
          ? null
          : formatDateRange(trip.startDate, trip.endDate),
      trailing: trip == null ? null : TripStatusPill(trip.status),
      children: [
        if (_notice != null) ...[
          StatusBanner(
            key: const ValueKey('detail-notice'),
            tone: StatusTone.success,
            message: _notice!,
          ),
          const SizedBox(height: 14),
        ],
        if (_error != null) ...[
          StatusBanner(
            key: const ValueKey('detail-error'),
            tone: StatusTone.error,
            message: _error!,
            actionLabel: 'Retry',
            onAction: _load,
          ),
          const SizedBox(height: 14),
        ],
        if (_missing)
          StatusBanner(
            key: const ValueKey('detail-missing'),
            tone: StatusTone.info,
            message: 'This trip no longer exists. It may have been deleted.',
            actionLabel: 'Back to My Trips',
            onAction: _closeAsDeleted,
          ),
        if (trip == null && _loading)
          const Padding(
            padding: EdgeInsets.only(top: 80),
            child: Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          ),
        if (trip != null) ..._buildDetails(trip),
      ],
    );
  }

  List<Widget> _buildDetails(Trip trip) {
    final transport = chipOptionFor(
      kTransportationModes,
      trip.transportationMode,
    );
    final group = chipOptionFor(kGroupTypes, trip.groupType);
    final tags = [
      for (final tag in trip.preferredTags)
        chipOptionFor(kPreferredTags, tag) ?? ChipOption(tag, tag, Icons.tag),
    ];

    return [
      FadeSlideIn(
        child: Row(
          children: [
            Expanded(
              child: _FactTile(
                icon: Icons.calendar_month_rounded,
                label: 'Dates',
                value: formatDayCount(
                  tripDayCount(trip.startDate, trip.endDate),
                ),
                detail: formatDateRange(trip.startDate, trip.endDate),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _FactTile(
                icon: Icons.payments_rounded,
                label: 'Budget',
                value: formatPeso(trip.budgetMax),
                detail: trip.budgetMin == trip.budgetMax
                    ? 'Fixed budget'
                    : 'From ${formatPeso(trip.budgetMin)}',
                accent: const Color(0xFF16A34A),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      FadeSlideIn(
        index: 1,
        child: GlassContainer(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoRow(
                'Getting around',
                transport?.label ?? 'Not set',
                transport?.icon ?? Icons.alt_route_rounded,
              ),
              const Divider(height: 24, color: Color(0xFFE2E8F0)),
              _infoRow(
                'Who is coming',
                group?.label ?? 'Not set',
                group?.icon ?? Icons.group_add_rounded,
              ),
              const Divider(height: 24, color: Color(0xFFE2E8F0)),
              const Text(
                'Vibes',
                style: TextStyle(
                  fontFamily: 'Outfit',
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: AppTheme.slateMuted,
                ),
              ),
              const SizedBox(height: 8),
              if (tags.isEmpty)
                const Text(
                  'No vibes picked yet',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.slateDark,
                  ),
                )
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final tag in tags)
                      TripPill(
                        label: tag.label,
                        icon: tag.icon,
                        color: const Color(0xFFC2410C),
                        background: const Color(0xFFFFF7ED),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 14),
      FadeSlideIn(
        index: 2,
        child: ItineraryLocationsSection(
          key: ValueKey('itinerary-${trip.id}'),
          service: widget.service,
          locations: _locations,
          trip: trip,
        ),
      ),
      const SizedBox(height: 20),
      FadeSlideIn(
        index: 3,
        child: Vector3DButton(
          key: const ValueKey('trip-edit'),
          onTap: _deleting ? null : _edit,
          backgroundColor: AppTheme.primaryBlue,
          shadowColor: const Color(0xFF1D4ED8),
          borderColor: const Color(0xFF93C5FD),
          borderRadius: 28,
          padding: const EdgeInsets.symmetric(vertical: 15),
          depth: 4.5,
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.edit_rounded, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Text(
                'Edit trip',
                style: TextStyle(
                  fontFamily: 'Outfit',
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 14),
      FadeSlideIn(
        index: 4,
        child: Vector3DButton(
          key: const ValueKey('trip-delete'),
          onTap: _deleting ? null : _delete,
          backgroundColor: Colors.white,
          shadowColor: const Color(0xFFFDA4AF),
          borderColor: const Color(0xFFFECDD3),
          borderRadius: 28,
          padding: const EdgeInsets.symmetric(vertical: 14),
          depth: 3.5,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_deleting)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Color(0xFFE11D48),
                  ),
                )
              else
                const Icon(
                  Icons.delete_outline_rounded,
                  color: Color(0xFFE11D48),
                  size: 19,
                ),
              const SizedBox(width: 8),
              Text(
                _deleting ? 'Deleting…' : 'Delete trip',
                style: const TextStyle(
                  fontFamily: 'Outfit',
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  color: Color(0xFFE11D48),
                ),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  Widget _infoRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 18, color: AppTheme.primaryBlue),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: 'Outfit',
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: AppTheme.slateMuted,
            ),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 14,
            color: AppTheme.slateDark,
          ),
        ),
      ],
    );
  }
}

class _FactTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String detail;
  final Color accent;

  const _FactTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
    this.accent = AppTheme.primaryBlue,
  });

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      borderRadius: 20,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: accent),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontFamily: 'Outfit',
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  color: AppTheme.slateMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'Outfit',
              fontWeight: FontWeight.w900,
              fontSize: 22,
              color: AppTheme.slateDark,
            ),
          ),
          Text(
            detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 11.5,
              color: AppTheme.slateMuted,
            ),
          ),
        ],
      ),
    );
  }
}
