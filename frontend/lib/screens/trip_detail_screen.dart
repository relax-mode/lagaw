import 'package:flutter/material.dart';

import '../config.dart';
import '../models/trip.dart';
import '../models/trip_plan.dart';
import '../services/api_service.dart';
import '../services/discovery_service.dart';
import '../services/trip_service.dart';
import '../theme.dart';
import '../utils/trip_format.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/itinerary_section.dart';
import '../widgets/status_banner.dart';
import '../widgets/trip_card.dart';
import '../widgets/trip_form/choice_chips_field.dart';
import '../widgets/trip_form/trip_form.dart';
import 'trip_edit_screen.dart';
import 'trip_planner_screen.dart';
import '../widgets/popup_route.dart';

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

  /// 0: Overview, 1: Itinerary.
  int _tab = 0;

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

  /// Bumped to make the itinerary section reload from the server.
  int _itineraryVersion = 0;

  /// Opens Plan with AI. The trip and itinerary are always reloaded on
  /// return: a timed-out generation may still have been saved. [S3-11]
  Future<void> _plan() async {
    final trip = _trip;
    if (trip == null) return;
    final result = await Navigator.of(context).push<GenerationResult>(
      blurPopupRoute(
        (_) => TripPlannerScreen(
          service: widget.service,
          trip: trip,
          savedPace: AppConfig.authEnabled
              ? () async => (await DiscoveryService().load()).travelStyle
              : null,
        ),
      ),
    );
    if (!mounted) return;
    setState(() {
      _itineraryVersion++;
      if (result != null) {
        _tab = 1;
        _notice =
            'Itinerary generated: ${result.items.length} '
            '${result.items.length == 1 ? 'stop' : 'stops'} saved.';
      }
    });
    _load();
  }

  Future<void> _edit() async {
    final saved = await Navigator.of(context).push<bool>(
      blurPopupRoute(
        (_) => TripEditScreen(service: widget.service, tripId: widget.tripId),
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
    final status = trip == null
        ? null
        : trip.status.isEmpty
        ? 'Draft'
        : '${trip.status[0].toUpperCase()}${trip.status.substring(1)}';
    // A pop-up, like Plan a trip, in two tabs so neither feels crowded.
    return PopupCard(
      eyebrow: status == null ? 'Trip' : 'Trip · $status',
      title: trip?.title ?? 'Your trip',
      subtitle: trip == null
          ? null
          : '${formatDayCount(tripDayCount(trip.startDate, trip.endDate))} · '
                '${formatDateRange(trip.startDate, trip.endDate)}',
      busy: _deleting,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (trip != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: _Tabs(
                index: _tab,
                onChanged: (i) => setState(() => _tab = i),
              ),
            ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
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
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFFF2620F),
                        ),
                      ),
                    ),
                  if (trip != null && _tab == 0) ..._overview(trip),
                  if (trip != null && _tab == 1)
                    ItineraryLocationsSection(
                      key: ValueKey('itinerary-${trip.id}-$_itineraryVersion'),
                      service: widget.service,
                      locations: _locations,
                      trip: trip,
                    ),
                ],
              ),
            ),
          ),
          if (trip != null) _footer(),
        ],
      ),
    );
  }

  List<Widget> _overview(Trip trip) {
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
      Row(
        children: [
          Expanded(
            child: _FactTile(
              icon: Icons.calendar_month_rounded,
              label: 'Dates',
              value: formatDayCount(tripDayCount(trip.startDate, trip.endDate)),
              detail: formatDateRange(trip.startDate, trip.endDate),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _FactTile(
              icon: Icons.payments_rounded,
              label: 'Budget',
              value: formatPeso(trip.budgetMax),
              detail: trip.budgetMin == trip.budgetMax
                  ? 'Fixed budget'
                  : trip.budgetMin == 0
                  ? 'Up to this'
                  : 'From ${formatPeso(trip.budgetMin)}',
              accent: const Color(0xFF16A34A),
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      _infoRow(
        'Getting around',
        transport?.label ?? 'Not set',
        transport?.icon ?? Icons.alt_route_rounded,
      ),
      const Divider(height: 24, color: Color(0xFFE9EEF5)),
      _infoRow(
        'Who is coming',
        group?.label ?? 'Not set',
        group?.icon ?? Icons.group_add_rounded,
      ),
      const Divider(height: 24, color: Color(0xFFE9EEF5)),
      const Text(
        'Vibes',
        style: TextStyle(
          fontWeight: FontWeight.w700,
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
                background: const Color(0xFFFFF3EA),
              ),
          ],
        ),
    ];
  }

  /// Plan with AI first; Edit and Delete beside each other below it.
  Widget _footer() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFEFF3F8))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            key: const ValueKey('trip-plan-ai'),
            onPressed: _deleting ? null : _plan,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFF2620F),
              foregroundColor: Colors.white,
              shape: const StadiumBorder(),
              minimumSize: const Size.fromHeight(50),
              textStyle: const TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            icon: const Icon(Icons.auto_awesome_rounded, size: 19),
            label: const Text('Plan with AI'),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey('trip-edit'),
                  onPressed: _deleting ? null : _edit,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.slateDark,
                    side: const BorderSide(color: Color(0xFFD5DEEA)),
                    shape: const StadiumBorder(),
                    minimumSize: const Size.fromHeight(46),
                  ),
                  icon: const Icon(Icons.edit_rounded, size: 17),
                  label: const Text('Edit trip'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey('trip-delete'),
                  onPressed: _deleting ? null : _delete,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFE11D48),
                    side: const BorderSide(color: Color(0xFFFBD0D9)),
                    shape: const StadiumBorder(),
                    minimumSize: const Size.fromHeight(46),
                  ),
                  icon: _deleting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Color(0xFFE11D48),
                          ),
                        )
                      : const Icon(Icons.delete_outline_rounded, size: 18),
                  label: Text(_deleting ? 'Deleting…' : 'Delete trip'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F8FC),
        borderRadius: BorderRadius.circular(18),
      ),
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
          // The largest allowed budget (₱9,999,999,999.99) otherwise wraps
          // mid-number on phones; shrink it onto one line instead.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: const TextStyle(
                fontFamily: 'Outfit',
                fontWeight: FontWeight.w900,
                fontSize: 22,
                color: AppTheme.slateDark,
              ),
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

/// Overview | Itinerary, as a soft segmented pill.
class _Tabs extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;

  const _Tabs({required this.index, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget tab(int i, String label, IconData icon) {
      final on = i == index;
      return Expanded(
        child: GestureDetector(
          key: ValueKey('trip-tab-$i'),
          onTap: () => onChanged(i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: on ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
              boxShadow: on
                  ? const [
                      BoxShadow(
                        color: Color(0x1A0F285A),
                        blurRadius: 10,
                        offset: Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 17,
                  color: on ? const Color(0xFFF2620F) : AppTheme.slateMuted,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: on ? AppTheme.slateDark : AppTheme.slateMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5FB),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          tab(0, 'Overview', Icons.info_outline_rounded),
          tab(1, 'Itinerary', Icons.map_rounded),
        ],
      ),
    );
  }
}
