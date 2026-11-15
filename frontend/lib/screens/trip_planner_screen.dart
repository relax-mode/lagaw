import 'package:flutter/material.dart';

import '../models/trip.dart';
import '../models/trip_plan.dart';
import '../services/trip_service.dart';
import '../theme.dart';
import '../utils/trip_format.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/rating_dialog.dart';
import '../widgets/status_banner.dart';
import '../widgets/trip_card.dart';
import '../widgets/trip_form/choice_chips_field.dart';
import '../widgets/trip_form/trip_form.dart';
import 'trip_edit_screen.dart';
import '../widgets/destination_photo.dart';
import '../widgets/popup_route.dart';
import 'home/home_view.dart' show HomeCategory;

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

  /// The pace saved in travel preferences, used as the starting pace so
  /// what the user chose there is what Plan with AI shows. [home v3]
  final Future<String?> Function()? savedPace;

  const TripPlannerScreen({
    super.key,
    required this.service,
    required this.trip,
    this.savedPace,
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

  /// Set once the user picks a pace here; the saved pace then stays out.
  bool _paceTouched = false;

  @override
  void initState() {
    super.initState();
    _loadSavedPace();
  }

  Future<void> _loadSavedPace() async {
    final load = widget.savedPace;
    if (load == null) return;
    try {
      final pace = await load();
      if (!mounted || _paceTouched) return;
      if (_paces.any((p) => p.value == pace)) setState(() => _pace = pace!);
    } on Object {
      // Keep the default; not knowing must not block planning.
    }
  }

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
      blurPopupRoute(
        (_) => TripEditScreen(service: widget.service, tripId: _trip.id),
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
        _step = _PlanStep.recs;
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
      builder: (context) => RatingDialog(name: rec.location.name),
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

  _PlanStep _step = _PlanStep.people;

  @override
  Widget build(BuildContext context) {
    final genIssues = _generateIssues;
    final steps = [_PlanStep.people, _PlanStep.timing, _PlanStep.choose];
    final index = steps.indexOf(_step);
    final (title, hint) = switch (_step) {
      _PlanStep.people => (
        'Who and how many',
        'People going and stops for the whole trip.',
      ),
      _PlanStep.timing => (
        'Time and pace',
        'When you like to go, and how fast.',
      ),
      _PlanStep.choose => (
        'Ready to plan',
        'Let Lagaw build the itinerary, or look at places first.',
      ),
      _PlanStep.recs => (
        'Recommended places',
        'Like, save or rate them. Not for me hides a place for good.',
      ),
    };
    // A pop-up in small steps, like Plan a trip. [home v3]
    return PopScope(
      canPop: !_generating,
      child: PopupCard(
        eyebrow: 'Plan with AI',
        title: _trip.title,
        busy: _generating,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (index >= 0) ...[
                      Row(
                        children: [
                          for (var i = 0; i < steps.length; i++) ...[
                            if (i > 0) const SizedBox(width: 6),
                            Expanded(
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 240),
                                height: 6,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(3),
                                  color: i <= index
                                      ? const Color(0xFFF2620F)
                                      : const Color(0xFFE3E9F2),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 18),
                    ],
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 22,
                        height: 1.15,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.4,
                        color: AppTheme.slateDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hint,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.slateMuted,
                      ),
                    ),
                    const SizedBox(height: 20),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: KeyedSubtree(
                        key: ValueKey(_step),
                        child: switch (_step) {
                          _PlanStep.people => Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (genIssues.isNotEmpty) ...[
                                _issuesCard(genIssues),
                                const SizedBox(height: 18),
                              ],
                              _peopleBody(),
                            ],
                          ),
                          _PlanStep.timing => _timingBody(),
                          _PlanStep.choose => _chooseBody(genIssues),
                          _PlanStep.recs => Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: _recommendationList(),
                          ),
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(22, 10, 22, 18),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFEFF3F8))),
              ),
              child: _footer(genIssues),
            ),
          ],
        ),
      ),
    );
  }

  Widget _footer(List<String> genIssues) {
    Widget back(VoidCallback? onTap) => Expanded(
      child: OutlinedButton(
        key: const ValueKey('plan-back'),
        onPressed: _generating ? null : onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.slateDark,
          side: const BorderSide(color: Color(0xFFD5DEEA)),
          shape: const StadiumBorder(),
          minimumSize: const Size.fromHeight(50),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        child: const Text('Back'),
      ),
    );
    Widget next(VoidCallback onTap) => Expanded(
      flex: 2,
      child: FilledButton(
        key: const ValueKey('plan-next'),
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFFF2620F),
          shape: const StadiumBorder(),
          minimumSize: const Size.fromHeight(50),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
        child: const Text('Next'),
      ),
    );
    return switch (_step) {
      _PlanStep.people => Row(
        children: [next(() => setState(() => _step = _PlanStep.timing))],
      ),
      _PlanStep.timing => Row(
        children: [
          back(() => setState(() => _step = _PlanStep.people)),
          const SizedBox(width: 10),
          next(() => setState(() => _step = _PlanStep.choose)),
        ],
      ),
      _PlanStep.choose => Row(
        children: [back(() => setState(() => _step = _PlanStep.timing))],
      ),
      _PlanStep.recs => Row(
        children: [
          back(() => setState(() => _step = _PlanStep.choose)),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: _actionButton(
              key: 'plan-generate-from-recs',
              // Short, so it fits beside Back.
              label: _generating ? 'Generating…' : 'Generate plan',
              icon: Icons.auto_awesome_rounded,
              busy: _generating,
              filled: true,
              onTap: genIssues.isEmpty && !_generating ? _generate : null,
            ),
          ),
        ],
      ),
    };
  }

  Widget _peopleBody() {
    final locked = _generating;
    return Column(
      children: [
        _stepper(
          key: 'plan-party',
          label: 'People going',
          hint: 'Splits the trip budget per person.',
          value: _party,
          min: 1,
          max: 20,
          onChanged: locked ? null : (v) => setState(() => _party = v),
        ),
        const SizedBox(height: 12),
        _stepper(
          key: 'plan-visits',
          label: 'Stops for the whole trip',
          hint: 'Total across all days, not per day.',
          value: _visits,
          min: 1,
          max: 30,
          onChanged: locked ? null : (v) => setState(() => _visits = v),
        ),
      ],
    );
  }

  Widget _timingBody() {
    final locked = _generating;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TactileChipsField(
          label: 'Time of day',
          options: _durations,
          selected: [_duration],
          optional: false,
          onChanged: (v) {
            if (!locked && v.isNotEmpty) setState(() => _duration = v.first);
          },
        ),
        const SizedBox(height: 22),
        TactileChipsField(
          label: 'Pace',
          options: _paces,
          selected: [_pace],
          optional: false,
          onChanged: (v) {
            if (!locked && v.isNotEmpty) {
              setState(() {
                _pace = v.first;
                _paceTouched = true;
              });
            }
          },
        ),
      ],
    );
  }

  Widget _chooseBody(List<String> genIssues) {
    final recIssues = _recommendIssues;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (genIssues.isNotEmpty) ...[
          _issuesCard(genIssues),
          const SizedBox(height: 16),
        ],
        if (_genError != null) ...[
          StatusBanner(
            key: const ValueKey('plan-generate-error'),
            tone: StatusTone.error,
            message: _genError!,
            actionLabel: _genStale ? 'Try again' : null,
            onAction: _genStale ? () => _generate() : null,
          ),
          const SizedBox(height: 14),
        ],
        if (_recsError != null) ...[
          StatusBanner(
            key: const ValueKey('plan-recs-error'),
            tone: StatusTone.error,
            message: _recsError!,
            actionLabel: 'Retry',
            onAction: _loadRecommendations,
          ),
          const SizedBox(height: 14),
        ],
        _actionButton(
          key: 'plan-generate',
          label: _generating ? 'Generating your plan…' : 'Generate itinerary',
          icon: Icons.auto_awesome_rounded,
          busy: _generating,
          filled: true,
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
          filled: false,
          onTap: recIssues.isEmpty && !_loadingRecs && !_generating
              ? _loadRecommendations
              : null,
        ),
        if (_recs != null && !_loadingRecs) ...[
          const SizedBox(height: 6),
          TextButton(
            key: const ValueKey('plan-show-recs'),
            onPressed: () => setState(() => _step = _PlanStep.recs),
            child: const Text('Back to the recommendations'),
          ),
        ],
      ],
    );
  }

  Widget _issuesCard(List<String> issues) {
    return Container(
      key: const ValueKey('plan-issues'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF5EC),
        borderRadius: BorderRadius.circular(18),
      ),
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

  Widget _stepper({
    required String key,
    required String label,
    required String hint,
    required int value,
    required int min,
    required int max,
    required ValueChanged<int>? onChanged,
  }) {
    Widget round(String k, IconData icon, VoidCallback? onTap) => Material(
      color: onTap == null ? const Color(0xFFEFF3F8) : Colors.white,
      shape: const CircleBorder(),
      child: InkWell(
        key: ValueKey(k),
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(
            icon,
            size: 20,
            color: onTap == null ? AppTheme.slateMuted : AppTheme.slateDark,
          ),
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F8FC),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: AppTheme.slateDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hint,
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 12.5,
                    color: AppTheme.slateMuted,
                  ),
                ),
              ],
            ),
          ),
          round(
            '$key-minus',
            Icons.remove_rounded,
            onChanged == null || value <= min
                ? null
                : () => onChanged(value - 1),
          ),
          SizedBox(
            width: 38,
            child: Text(
              '$value',
              key: ValueKey('$key-value'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 19,
                color: AppTheme.slateDark,
              ),
            ),
          ),
          round(
            '$key-plus',
            Icons.add_rounded,
            onChanged == null || value >= max
                ? null
                : () => onChanged(value + 1),
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required String key,
    required String label,
    required IconData icon,
    required bool busy,
    required bool filled,
    required VoidCallback? onTap,
  }) {
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (busy)
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: filled ? Colors.white : const Color(0xFFF2620F),
            ),
          )
        else
          Icon(icon, size: 19),
        const SizedBox(width: 8),
        Flexible(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
    const text = TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800);
    return filled
        ? FilledButton(
            key: ValueKey(key),
            onPressed: onTap,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFF2620F),
              foregroundColor: Colors.white,
              disabledBackgroundColor: busy
                  ? const Color(0xFFF2620F)
                  : const Color(0xFFF9C4A3),
              disabledForegroundColor: Colors.white,
              shape: const StadiumBorder(),
              minimumSize: const Size.fromHeight(54),
              textStyle: text,
            ),
            child: content,
          )
        : OutlinedButton(
            key: ValueKey(key),
            onPressed: onTap,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.slateDark,
              side: const BorderSide(color: Color(0xFFD5DEEA)),
              shape: const StadiumBorder(),
              minimumSize: const Size.fromHeight(54),
              textStyle: text,
            ),
            child: content,
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
      if (recs != null)
        for (final rec in recs.items) ...[
          _recommendationCard(rec),
          const SizedBox(height: 12),
        ],
    ];
  }

  /// A recommended place: photo, name, category · price, then four clear
  /// actions. Ranking scores and reasons stay out of view. [home v3]
  Widget _recommendationCard(TripRecommendation rec) {
    final id = rec.locationId;
    final busy = _busy.contains(id);
    final place = rec.location;
    final liked = _liked.contains(id);
    final saved = _saved.contains(id);
    final rated = _rated[id];
    return Container(
      key: ValueKey('rec-${rec.locationId}'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F8FC),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: DestinationPhoto(
                  location: place,
                  width: 64,
                  height: 64,
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
                        fontSize: 15.5,
                        height: 1.15,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.slateDark,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${HomeCategory.labelFor(place.category)} · ${place.costRange}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.slateMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (busy)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _recAction(
                key: 'rec-dislike-$id',
                icon: Icons.close_rounded,
                label: 'Not for me',
                color: const Color(0xFFE11D48),
                onTap: busy ? null : () => _dislike(rec),
              ),
              const SizedBox(width: 6),
              _recAction(
                key: 'rec-like-$id',
                icon: liked
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                label: liked ? 'Liked' : 'Like',
                color: const Color(0xFFF2620F),
                active: liked,
                onTap: busy || liked
                    ? null
                    : () => _interact(rec, InteractionType.rightSwipe),
              ),
              const SizedBox(width: 6),
              _recAction(
                key: 'rec-save-$id',
                icon: saved
                    ? Icons.bookmark_rounded
                    : Icons.bookmark_border_rounded,
                label: saved ? 'Saved' : 'Save',
                color: AppTheme.primaryBlue,
                active: saved,
                onTap: busy || saved
                    ? null
                    : () => _interact(rec, InteractionType.save),
              ),
              const SizedBox(width: 6),
              _recAction(
                key: 'rec-rate-$id',
                icon: rated != null
                    ? Icons.star_rounded
                    : Icons.star_border_rounded,
                label: rated != null ? 'Rated $rated' : 'Rate',
                color: const Color(0xFFE0A100),
                active: rated != null,
                onTap: busy ? null : () => _rate(rec),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _recAction({
    required String key,
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onTap,
    bool active = false,
  }) {
    return Expanded(
      child: Material(
        color: active ? color.withValues(alpha: 0.12) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          key: ValueKey(key),
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Column(
              children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: active ? color : AppTheme.slateDark,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _PlanStep { people, timing, choose, recs }
