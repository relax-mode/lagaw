import 'package:flutter/material.dart';

import '../models/trip.dart';
import '../models/trip_plan.dart';
import '../services/trip_service.dart';
import '../theme.dart';
import '../utils/trip_format.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/destination_tile.dart';
import '../widgets/status_banner.dart';
import '../widgets/tactile_motion.dart';
import '../widgets/trip_card.dart';
import '../widgets/trip_form/choice_chips_field.dart';
import '../widgets/trip_form/trip_form.dart';
import 'trip_edit_screen.dart';
import 'trip_page_scaffold.dart';

const List<ChipOption> _durations = [
  ChipOption('full_day', 'Full day', Icons.wb_sunny_rounded),
  ChipOption('morning', 'Morning', Icons.wb_twilight_rounded),
  ChipOption('afternoon', 'Afternoon', Icons.light_mode_rounded),
  ChipOption('evening', 'Evening', Icons.nights_stay_rounded),
];

const List<ChipOption> _paces = [
  ChipOption('slow', 'Slow', Icons.self_improvement_rounded),
  ChipOption('moderate', 'Moderate', Icons.directions_walk_rounded),
  ChipOption('fast', 'Fast', Icons.directions_run_rounded),
];

const Map<String, String> _skipLabels = {
  'unknown_or_unsupported_opening_hours': 'unknown opening hours',
  'missing_duration_or_cost': 'missing visit time or cost',
  'pace_exceeds_visit_duration_limit': 'too long for the chosen pace',
};

/// Plan with AI for one saved trip: ranked recommendations (#53) with
/// like/dislike/save/rate (#52), then a generated, saved itinerary (#54).
/// Pops a [GenerationResult] after a plan is saved. [S3-11]
class TripPlannerScreen extends StatefulWidget {
  final TripService service;
  final Trip trip;

  const TripPlannerScreen({
    super.key,
    required this.service,
    required this.trip,
  });

  @override
  State<TripPlannerScreen> createState() => _TripPlannerScreenState();
}

class _TripPlannerScreenState extends State<TripPlannerScreen> {
  late Trip _trip = widget.trip;
  late int _party = switch (_trip.groupType) {
    'solo' => 1,
    'couple' => 2,
    'friends' => 3,
    'family' => 4,
    'group' => 5,
    _ => 2,
  };
  late int _visits = (tripDayCount(_trip.startDate, _trip.endDate) * 2).clamp(
    1,
    10,
  );
  String _duration = 'full_day';
  String _pace = 'moderate';

  RecommendationsPage? _recs;
  bool _loadingRecs = false;
  String? _recsError;

  final Set<String> _busy = {};
  final Set<String> _liked = {};
  final Set<String> _saved = {};
  final Map<String, int> _rated = {};
  String? _interactionError;

  bool _generating = false;
  String? _genError;
  bool _genStale = false;

  PlanOptions get _options => PlanOptions(
    partySize: _party,
    plannedVisits: _visits,
    duration: _duration,
    pace: _pace,
  );

  /// Problems with the saved trip that the APIs would reject (422).
  List<String> get _recommendIssues {
    final issues = <String>[];
    final group = _trip.groupType;
    if (group == null || !kPlannableGroups.contains(group)) {
      issues.add(
        'Set "Who is coming" to Solo, Couple, Friends or Family'
        '${group == 'students' ? ' (Students isn\'t supported for planning yet)' : ''}.',
      );
    }
    final unsupported = _trip.preferredTags
        .where((t) => !kPlannableTags.contains(t))
        .map((t) => chipOptionFor(kPreferredTags, t)?.label ?? t)
        .toList();
    if (unsupported.isNotEmpty) {
      issues.add(
        'Remove vibes AI can\'t plan with yet: ${unsupported.join(', ')}. '
        'Supported: Café, Food, Heritage, Photography, Nature, Relaxing.',
      );
    }
    return issues;
  }

  List<String> get _generateIssues => [
    ..._recommendIssues,
    if (_trip.transportationMode == null ||
        !kPlannableTransport.contains(_trip.transportationMode))
      'Choose how you\'ll get around so travel time can be planned.',
    if (tripDayCount(_trip.startDate, _trip.endDate) > 31)
      'Itineraries can be generated for trips of up to 31 days.',
  ];

  Future<void> _editTrip() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            TripEditScreen(service: widget.service, tripId: _trip.id),
      ),
    );
    if (saved != true || !mounted) return;
    try {
      final trip = await widget.service.getTrip(_trip.id);
      if (mounted) setState(() => _trip = trip);
    } on TripApiException catch (e) {
      if (mounted) setState(() => _recsError = e.message);
    }
  }

  /// Keeps the current list on screen while refreshing.
  Future<void> _loadRecommendations() async {
    if (_loadingRecs || _recommendIssues.isNotEmpty) return;
    setState(() {
      _loadingRecs = true;
      _recsError = null;
    });
    try {
      final page = await widget.service.recommendTrip(_trip.id, _options);
      if (!mounted) return;
      setState(() {
        _recs = page;
        _loadingRecs = false;
      });
    } on TripApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingRecs = false;
        _recsError = e.message;
      });
    }
  }

  Future<void> _interact(
    TripRecommendation rec,
    InteractionType type, {
    int? rating,
  }) async {
    final id = rec.locationId;
    if (_busy.contains(id)) return;
    setState(() {
      _busy.add(id);
      _interactionError = null;
    });
    try {
      await widget.service.recordInteraction(
        id,
        type,
        rating: rating?.toDouble(),
      );
      if (!mounted) return;
      setState(() {
        _busy.remove(id);
        switch (type) {
          case InteractionType.rightSwipe:
            _liked.add(id);
          case InteractionType.save:
            _saved.add(id);
          case InteractionType.rating:
            _rated[id] = rating!;
          case InteractionType.leftSwipe:
            final recs = _recs;
            if (recs != null) {
              _recs = RecommendationsPage(
                items: recs.items.where((r) => r.locationId != id).toList(),
                emptyReason: recs.emptyReason,
                budgetMax: recs.budgetMax,
              );
            }
        }
      });
      // A dislike excludes the place and a rating changes the history the
      // ranking uses, so ask for fresh recommendations.
      if (type == InteractionType.leftSwipe || type == InteractionType.rating) {
        await _loadRecommendations();
      }
    } on TripApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy.remove(id);
        _interactionError = e.message;
      });
    }
  }

  Future<void> _dislike(TripRecommendation rec) async {
    final ok = await showTactileConfirmDialog(
      context,
      title: 'Not for you?',
      message:
          '"${rec.location.name}" won\'t be recommended to you again. This '
          'can\'t be undone.',
      confirmLabel: 'Not for me',
      icon: Icons.thumb_down_alt_rounded,
    );
    if (ok && mounted) await _interact(rec, InteractionType.leftSwipe);
  }

  Future<void> _rate(TripRecommendation rec) async {
    final stars = await showDialog<int>(
      context: context,
      builder: (context) => _RatingDialog(name: rec.location.name),
    );
    if (stars != null && mounted) {
      await _interact(rec, InteractionType.rating, rating: stars);
    }
  }

  Future<void> _generate({String? revision}) async {
    if (_generating || _generateIssues.isNotEmpty) return;
    setState(() {
      _generating = true;
      _genError = null;
      _genStale = false;
    });
    try {
      final result = await widget.service.generateItinerary(
        _trip.id,
        _options,
        expectedRevision: revision,
      );
      if (mounted) Navigator.of(context).pop(result);
    } on PlanApiException catch (e) {
      if (!mounted) return;
      setState(() => _generating = false);
      if (e.needsReplacementConfirmation) {
        final ok = await showTactileConfirmDialog(
          context,
          title: 'Replace this itinerary?',
          message:
              'Generating replaces every saved stop on this trip, including '
              'ones you added yourself. This can\'t be undone.',
          confirmLabel: 'Replace',
          icon: Icons.autorenew_rounded,
        );
        if (ok && mounted) await _generate(revision: e.revision);
        return;
      }
      setState(() {
        _genStale = e.isStaleConfirmation;
        _genError = [
          e.message,
          if (e.skipped.isNotEmpty) _skipSummary(e),
        ].join(' ');
      });
    } on TripApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _generating = false;
        _genError =
            '${e.message} Your saved plan is unchanged. If the plan was '
            'created anyway, it will show when you go back.';
      });
    }
  }

  String _skipSummary(PlanApiException e) {
    final counts = <String, int>{};
    for (final reason in e.skipped.values) {
      final label = _skipLabels[reason] ?? reason.replaceAll('_', ' ');
      counts[label] = (counts[label] ?? 0) + 1;
    }
    final parts = [
      for (final entry in counts.entries) '${entry.value} ${entry.key}',
    ];
    return 'Places skipped: ${parts.join(', ')}.';
  }

  @override
  Widget build(BuildContext context) {
    final recIssues = _recommendIssues;
    final genIssues = _generateIssues;
    return PopScope(
      canPop: !_generating,
      child: TripPageScaffold(
        title: 'plan with AI',
        subtitle: _trip.title,
        children: [
          if (genIssues.isNotEmpty) ...[
            _issuesCard(genIssues),
            const SizedBox(height: 14),
          ],
          FadeSlideIn(child: _optionsCard()),
          const SizedBox(height: 14),
          if (_genError != null) ...[
            StatusBanner(
              key: const ValueKey('plan-generate-error'),
              tone: StatusTone.error,
              message: _genError!,
              actionLabel: _genStale ? 'Try again' : null,
              onAction: _genStale ? () => _generate() : null,
            ),
            const SizedBox(height: 12),
          ],
          _actionButton(
            key: 'plan-generate',
            label: _generating ? 'Generating your plan…' : 'Generate itinerary',
            icon: Icons.auto_awesome_rounded,
            busy: _generating,
            color: const Color(0xFF7C3AED),
            shadow: const Color(0xFF5B21B6),
            onTap: genIssues.isEmpty && !_generating ? _generate : null,
          ),
          const SizedBox(height: 10),
          _actionButton(
            key: 'plan-recommend',
            label: _loadingRecs
                ? 'Finding places…'
                : (_recs == null
                      ? 'See recommendations'
                      : 'Refresh recommendations'),
            icon: Icons.travel_explore_rounded,
            busy: _loadingRecs,
            color: AppTheme.primaryBlue,
            shadow: const Color(0xFF1D4ED8),
            onTap: recIssues.isEmpty && !_loadingRecs
                ? _loadRecommendations
                : null,
          ),
          const SizedBox(height: 18),
          ..._recommendationList(),
        ],
      ),
    );
  }

  Widget _issuesCard(List<String> issues) {
    return GlassContainer(
      key: const ValueKey('plan-issues'),
      tintColor: const Color(0xFFFFF7ED),
      borderColor: const Color(0xFFFED7AA),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Update this trip to plan with AI',
            style: TextStyle(
              fontFamily: 'Outfit',
              fontWeight: FontWeight.w900,
              fontSize: 15,
              color: AppTheme.slateDark,
            ),
          ),
          const SizedBox(height: 6),
          for (final issue in issues)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '• $issue',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppTheme.slateDark,
                ),
              ),
            ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const ValueKey('plan-edit-trip'),
              onPressed: _editTrip,
              icon: const Icon(Icons.edit_rounded, size: 18),
              label: const Text('Edit trip'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _optionsCard() {
    final locked = _generating;
    return GlassContainer(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _stepper(
            key: 'plan-party',
            label: 'People going',
            hint: 'Used to split your trip budget per person.',
            value: _party,
            min: 1,
            max: 20,
            onChanged: locked ? null : (v) => setState(() => _party = v),
          ),
          const Divider(height: 24, color: Color(0xFFE2E8F0)),
          _stepper(
            key: 'plan-visits',
            label: 'Stops for the whole trip',
            hint: 'Total across all days, not per day.',
            value: _visits,
            min: 1,
            max: 30,
            onChanged: locked ? null : (v) => setState(() => _visits = v),
          ),
          const Divider(height: 24, color: Color(0xFFE2E8F0)),
          TactileChipsField(
            label: 'Time of day',
            options: _durations,
            selected: [_duration],
            optional: false,
            onChanged: (v) {
              if (!locked && v.isNotEmpty) setState(() => _duration = v.first);
            },
          ),
          const SizedBox(height: 14),
          TactileChipsField(
            label: 'Pace',
            options: _paces,
            selected: [_pace],
            optional: false,
            accent: const Color(0xFF7C3AED),
            accentShadow: const Color(0xFF5B21B6),
            onChanged: (v) {
              if (!locked && v.isNotEmpty) setState(() => _pace = v.first);
            },
          ),
        ],
      ),
    );
  }

  Widget _stepper({
    required String key,
    required String label,
    required String hint,
    required int value,
    required int min,
    required int max,
    required ValueChanged<int>? onChanged,
  }) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontFamily: 'Outfit',
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: AppTheme.slateDark,
                ),
              ),
              Text(
                hint,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  color: AppTheme.slateMuted,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          key: ValueKey('$key-minus'),
          tooltip: 'Fewer',
          onPressed: onChanged == null || value <= min
              ? null
              : () => onChanged(value - 1),
          icon: const Icon(Icons.remove_circle_outline_rounded),
        ),
        SizedBox(
          width: 28,
          child: Text(
            '$value',
            key: ValueKey('$key-value'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Outfit',
              fontWeight: FontWeight.w900,
              fontSize: 18,
              color: AppTheme.slateDark,
            ),
          ),
        ),
        IconButton(
          key: ValueKey('$key-plus'),
          tooltip: 'More',
          onPressed: onChanged == null || value >= max
              ? null
              : () => onChanged(value + 1),
          icon: const Icon(Icons.add_circle_outline_rounded),
        ),
      ],
    );
  }

  Widget _actionButton({
    required String key,
    required String label,
    required IconData icon,
    required bool busy,
    required Color color,
    required Color shadow,
    required VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    return Vector3DButton(
      key: ValueKey(key),
      onTap: onTap,
      backgroundColor: enabled || busy ? color : const Color(0xFF94A3B8),
      shadowColor: shadow,
      borderColor: Colors.white,
      borderRadius: 26,
      padding: const EdgeInsets.symmetric(vertical: 14),
      depth: 4,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (busy)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Colors.white,
              ),
            )
          else
            Icon(icon, color: Colors.white, size: 19),
          const SizedBox(width: 8),
          Text(
            label,
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

  List<Widget> _recommendationList() {
    final recs = _recs;
    return [
      if (_recsError != null) ...[
        StatusBanner(
          key: const ValueKey('plan-recs-error'),
          tone: StatusTone.error,
          message: _recsError!,
          actionLabel: 'Retry',
          onAction: _loadRecommendations,
        ),
        const SizedBox(height: 12),
      ],
      if (_interactionError != null) ...[
        StatusBanner(
          key: const ValueKey('plan-interaction-error'),
          tone: StatusTone.error,
          message: _interactionError!,
        ),
        const SizedBox(height: 12),
      ],
      if (recs != null && recs.items.isEmpty)
        const StatusBanner(
          key: ValueKey('plan-recs-empty'),
          tone: StatusTone.info,
          message:
              'No places match this trip\'s vibes, group and budget right now. '
              'Try other vibes or a larger budget.',
        ),
      if (recs != null && recs.items.isNotEmpty) ...[
        Text(
          'Recommended for this trip',
          style: const TextStyle(
            fontFamily: 'Outfit',
            fontWeight: FontWeight.w900,
            fontSize: 18,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 10),
        for (final rec in recs.items) ...[
          _recommendationCard(rec),
          const SizedBox(height: 10),
        ],
      ],
    ];
  }

  Widget _recommendationCard(TripRecommendation rec) {
    final id = rec.locationId;
    final busy = _busy.contains(id);
    return GlassContainer(
      key: ValueKey('rec-${rec.locationId}'),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DestinationTile(
            location: rec.location,
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${(rec.score * 100).round()}%',
                style: const TextStyle(
                  fontFamily: 'Outfit',
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF16A34A),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
            child: Text(
              rec.reason,
              style: const TextStyle(
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: AppTheme.slateMuted,
              ),
            ),
          ),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _chipButton(
                key: 'rec-like-$id',
                icon: _liked.contains(id)
                    ? Icons.thumb_up_alt_rounded
                    : Icons.thumb_up_alt_outlined,
                label: _liked.contains(id) ? 'Liked' : 'Like',
                onTap: busy || _liked.contains(id)
                    ? null
                    : () => _interact(rec, InteractionType.rightSwipe),
              ),
              _chipButton(
                key: 'rec-dislike-$id',
                icon: Icons.thumb_down_alt_outlined,
                label: 'Not for me',
                onTap: busy ? null : () => _dislike(rec),
              ),
              _chipButton(
                key: 'rec-save-$id',
                icon: _saved.contains(id)
                    ? Icons.bookmark_rounded
                    : Icons.bookmark_border_rounded,
                label: _saved.contains(id) ? 'Saved' : 'Save',
                onTap: busy || _saved.contains(id)
                    ? null
                    : () => _interact(rec, InteractionType.save),
              ),
              _chipButton(
                key: 'rec-rate-$id',
                icon: _rated.containsKey(id)
                    ? Icons.star_rounded
                    : Icons.star_border_rounded,
                label: _rated.containsKey(id) ? 'Rated ${_rated[id]}' : 'Rate',
                onTap: busy ? null : () => _rate(rec),
              ),
              if (busy)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chipButton({
    required String key,
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return TextButton.icon(
      key: ValueKey(key),
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        foregroundColor: AppTheme.primaryBlue,
      ),
    );
  }
}

class _RatingDialog extends StatefulWidget {
  final String name;

  const _RatingDialog({required this.name});

  @override
  State<_RatingDialog> createState() => _RatingDialogState();
}

class _RatingDialogState extends State<_RatingDialog> {
  int _stars = 0;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Rate ${widget.name}'),
      content: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 1; i <= 5; i++)
            IconButton(
              key: ValueKey('rating-star-$i'),
              tooltip: '$i star${i == 1 ? '' : 's'}',
              onPressed: () => setState(() => _stars = i),
              icon: Icon(
                i <= _stars ? Icons.star_rounded : Icons.star_border_rounded,
                color: const Color(0xFFF59E0B),
                size: 32,
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('rating-submit'),
          onPressed: _stars == 0
              ? null
              : () => Navigator.of(context).pop(_stars),
          child: const Text('Rate'),
        ),
      ],
    );
  }
}
