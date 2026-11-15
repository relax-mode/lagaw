import 'package:flutter/material.dart';

import '../../models/preference_draft.dart';
import '../../models/trip.dart';
import '../../services/preference_service.dart';
import '../../services/trip_service.dart';
import '../../theme.dart';
import '../status_banner.dart';
import '../tactile_motion.dart';
import '../trip_card.dart' show chipOptionFor;
import 'budget_range_field.dart';
import 'choice_chips_field.dart';
import 'date_range_field.dart';
import 'describe_trip_card.dart';
import 'preference_review_sheet.dart';
import 'tactile_field_style.dart';
import 'tactile_text_field.dart';
import 'trip_form_validators.dart';

/// Values the backend stores for each chip; labels are display only.
const List<ChipOption> kTransportationModes = [
  ChipOption('walking', 'Walking', Icons.directions_walk_rounded),
  ChipOption('jeepney', 'Jeepney', Icons.directions_bus_rounded),
  ChipOption('taxi', 'Taxi / Grab', Icons.local_taxi_rounded),
  ChipOption('motorcycle', 'Motorcycle', Icons.two_wheeler_rounded),
  ChipOption('private_car', 'Private car', Icons.directions_car_rounded),
];

const List<ChipOption> kGroupTypes = [
  ChipOption('solo', 'Solo', Icons.person_rounded),
  ChipOption('couple', 'Couple', Icons.favorite_rounded),
  ChipOption('friends', 'Friends', Icons.groups_rounded),
  ChipOption('family', 'Family', Icons.family_restroom_rounded),
  ChipOption('students', 'Students', Icons.school_rounded),
];

/// Matches the location `vibe_tags` vocabulary.
const List<ChipOption> kPreferredTags = [
  ChipOption('cafe', 'Café', Icons.local_cafe_rounded),
  ChipOption('food', 'Food', Icons.restaurant_rounded),
  ChipOption('heritage', 'Heritage', Icons.account_balance_rounded),
  ChipOption('photography', 'Photography', Icons.photo_camera_rounded),
  ChipOption('nature', 'Nature', Icons.park_rounded),
  ChipOption('relaxing', 'Relaxing', Icons.spa_rounded),
  ChipOption('art', 'Art', Icons.palette_rounded),
  ChipOption('culture', 'Culture', Icons.theater_comedy_rounded),
  ChipOption('sunset', 'Sunset', Icons.wb_twilight_rounded),
  ChipOption('outdoors', 'Outdoors', Icons.hiking_rounded),
  ChipOption('sweet', 'Sweets', Icons.cake_rounded),
];

String _formatBudget(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(2);

/// Reusable create/edit trip form. Pass [initial] to pre-fill for editing.
/// [fieldErrors] takes backend 422 messages keyed by API field name. [S2-04]
class TripForm extends StatefulWidget {
  final TripDraft? initial;
  final ValueChanged<TripDraft> onSubmit;
  final String submitLabel;
  final bool isSubmitting;
  final Map<String, String> fieldErrors;

  /// Backs the "Describe your trip" suggestions. [S3-06]
  final PreferenceService? preferenceService;

  /// Inside a pop-up card: sections are separated by dividers instead of
  /// being cards inside the card, so the form has room. [home v3]
  final bool flat;

  /// One small step at a time (Plan a trip): describe or skip, review the
  /// suggestions, basics, getting around, who's coming, then vibes.
  /// [home v3]
  final bool stepped;

  const TripForm({
    super.key,
    this.initial,
    required this.onSubmit,
    this.submitLabel = 'Save trip',
    this.isSubmitting = false,
    this.fieldErrors = const {},
    this.preferenceService,
    this.flat = false,
    this.stepped = false,
  });

  @override
  State<TripForm> createState() => TripFormState();
}

class TripFormState extends State<TripForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _budgetMin;
  late final TextEditingController _budgetMax;
  DateTimeRange? _dates;
  List<String> _transport = const [];
  List<String> _group = const [];
  List<String> _tags = const [];
  bool _triedSubmit = false;
  String? _suggestionNotice;

  late final PreferenceService _preferences =
      widget.preferenceService ?? PreferenceService();

  /// Reviews extracted suggestions; only vibes the user ticks are added, and
  /// nothing already chosen is removed. Saving still needs the Save button.
  Future<void> _reviewSuggestions(PreferenceDraft draft) async {
    if (widget.stepped) {
      // In steps, the review is the next page, not a sheet.
      setState(() {
        _pending = draft;
        _accepted = {
          for (final tag in draft.preferredTags)
            if (!_tags.contains(tag)) tag,
        };
        _step = _Step.review;
      });
      return;
    }
    final add = await showPreferenceReview(
      context,
      draft: draft,
      currentTags: _tags,
    );
    if (add == null || !mounted) return;
    _applySuggestions(draft, add);
  }

  /// Adds the accepted vibes; Who's coming and the budget from the
  /// description fill in only what is still empty.
  void _applySuggestions(PreferenceDraft draft, List<String> add) {
    final room = TripFormValidators.maxTags - _tags.length;
    final accepted = add.take(room).toList();
    final group = draft.groupType;
    final takeGroup =
        _group.isEmpty &&
        group != null &&
        kGroupTypes.any((o) => o.value == group);
    final takeBudget =
        _budgetMax.text.trim().isEmpty &&
        _budgetMin.text.trim().isEmpty &&
        draft.budgetMax != null;
    setState(() {
      _tags = [..._tags, ...accepted];
      if (takeGroup) _group = [group];
      if (takeBudget) {
        _budgetMin.text = _formatBudget(draft.budgetMin ?? 0);
        _budgetMax.text = _formatBudget(draft.budgetMax!);
      }
      final parts = [
        if (accepted.isNotEmpty)
          '${accepted.length} ${accepted.length == 1 ? 'vibe' : 'vibes'}',
        if (takeGroup) 'who’s coming',
        if (takeBudget) 'budget',
      ];
      _suggestionNotice = parts.isEmpty
          ? 'No changes applied.'
          : 'Added ${parts.join(', ')}. Check the form, then save.';
    });
  }

  // Steps (Plan a trip) ------------------------------------------------------

  _Step _step = _Step.describe;
  PreferenceDraft? _pending;
  Set<String> _accepted = {};
  bool _basicsTried = false;

  /// Anything typed or picked, so closing can ask before discarding it.
  bool get isDirty =>
      _title.text.trim().isNotEmpty ||
      _budgetMin.text.trim().isNotEmpty ||
      _budgetMax.text.trim().isNotEmpty ||
      _dates != null ||
      _transport.isNotEmpty ||
      _group.isNotEmpty ||
      _tags.isNotEmpty;

  static const _order = [
    _Step.basics,
    _Step.transport,
    _Step.group,
    _Step.vibes,
  ];

  void _go(_Step step) => setState(() => _step = step);

  /// Checks the basics before moving on.
  void _nextFromBasics() {
    setState(() {
      _basicsTried = true;
      _triedSubmit = true;
    });
    final fields = _formKey.currentState!.validate();
    final dates = TripFormValidators.dates(_dates?.start, _dates?.end) == null;
    if (fields && dates) _go(_Step.transport);
  }

  @override
  void didUpdateWidget(TripForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A server problem with an earlier step's field: go back to that step.
    if (widget.stepped &&
        widget.fieldErrors.isNotEmpty &&
        widget.fieldErrors != oldWidget.fieldErrors) {
      final keys = widget.fieldErrors.keys;
      _step =
          keys.any(
            (k) => const [
              'title',
              'start_date',
              'end_date',
              'budget_min',
              'budget_max',
            ].contains(k),
          )
          ? _Step.basics
          : keys.contains('transportation_mode')
          ? _Step.transport
          : keys.contains('group_type')
          ? _Step.group
          : _step;
    }
  }

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _title = TextEditingController(text: initial?.title ?? '');
    _budgetMin = TextEditingController(
      text: initial == null ? '' : _formatBudget(initial.budgetMin),
    );
    _budgetMax = TextEditingController(
      text: initial == null ? '' : _formatBudget(initial.budgetMax),
    );
    if (initial != null) {
      _dates = DateTimeRange(start: initial.startDate, end: initial.endDate);
      _transport = [?initial.transportationMode];
      _group = [?initial.groupType];
      _tags = List.of(initial.preferredTags);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _budgetMin.dispose();
    _budgetMax.dispose();
    super.dispose();
  }

  String? get _datesError {
    final server =
        widget.fieldErrors['start_date'] ?? widget.fieldErrors['end_date'];
    if (server != null) return server;
    if (!_triedSubmit) return null;
    return TripFormValidators.dates(_dates?.start, _dates?.end);
  }

  /// Validates and returns the draft, or null if something needs fixing.
  TripDraft? buildDraft() {
    setState(() => _triedSubmit = true);
    final fieldsValid = _formKey.currentState!.validate();
    final datesValid =
        TripFormValidators.dates(_dates?.start, _dates?.end) == null;
    if (!fieldsValid || !datesValid) return null;

    return TripDraft(
      title: _title.text.trim(),
      startDate: _dates!.start,
      endDate: _dates!.end,
      budgetMin: TripFormValidators.minOrZero(_budgetMin.text),
      budgetMax: TripFormValidators.parseMoney(_budgetMax.text)!,
      transportationMode: _transport.firstOrNull,
      groupType: _group.firstOrNull,
      preferredTags: _tags,
    );
  }

  void _submit() {
    final draft = buildDraft();
    if (draft != null) widget.onSubmit(draft);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.stepped) return _steppedBuild();
    final errors = widget.fieldErrors;
    final formError = errors[TripApiException.formErrorKey];

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (formError != null) ...[
            _FormErrorBanner(message: formError),
            const SizedBox(height: 16),
          ],
          _section(0, [
            DescribeTripCard(
              service: _preferences,
              enabled: !widget.isSubmitting,
              notice: _suggestionNotice,
              onSuggestions: _reviewSuggestions,
            ),
          ]),
          _section(0, divider: true, [
            TactileTextField(
              key: const ValueKey('trip-title'),
              label: 'Trip name',
              controller: _title,
              hintText: 'e.g. Weekend food crawl',
              maxLength: TripFormValidators.titleMaxLength,
              textInputAction: TextInputAction.next,
              validator: TripFormValidators.title,
              serverError: errors['title'],
            ),
            const SizedBox(height: 18),
            DateRangeField(
              value: _dates,
              errorText: _datesError,
              onChanged: (range) => setState(() => _dates = range),
            ),
          ]),
          _section(1, [
            BudgetRangeField(
              minController: _budgetMin,
              maxController: _budgetMax,
              minServerError: errors['budget_min'],
              maxServerError: errors['budget_max'],
            ),
          ]),
          _section(2, [
            TactileChipsField(
              label: 'Getting around',
              options: kTransportationModes,
              selected: _transport,
              errorText: errors['transportation_mode'],
              onChanged: (v) => setState(() => _transport = v),
            ),
            const SizedBox(height: 18),
            TactileChipsField(
              label: 'Who is coming',
              options: kGroupTypes,
              selected: _group,
              errorText: errors['group_type'],
              onChanged: (v) => setState(() => _group = v),
            ),
            const SizedBox(height: 18),
            TactileChipsField(
              label: 'Vibes you want',
              options: kPreferredTags,
              selected: _tags,
              multiSelect: true,
              maxSelected: TripFormValidators.maxTags,
              errorText: errors['preferred_tags'],
              onChanged: (v) => setState(() => _tags = v),
            ),
          ]),
          const SizedBox(height: 8),
          FadeSlideIn(
            index: 3,
            child: Vector3DButton(
              key: const ValueKey('trip-submit'),
              onTap: widget.isSubmitting ? null : _submit,
              backgroundColor: const Color(0xFFEA580C),
              shadowColor: const Color(0xFF9A3412),
              borderColor: const Color(0xFFFDBA74),
              borderRadius: 28,
              padding: const EdgeInsets.symmetric(vertical: 16),
              depth: 4.5,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (widget.isSubmitting) ...[
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Text(
                    widget.isSubmitting ? 'Saving…' : widget.submitLabel,
                    style: const TextStyle(
                      fontFamily: 'Outfit',
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      color: Colors.white,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _steppedBuild() {
    final errors = widget.fieldErrors;
    final formError = errors[TripApiException.formErrorKey];
    final index = _order.indexOf(_step);
    final (title, hint) = switch (_step) {
      _Step.describe => (
        'Describe your trip',
        'Optional. Lagaw suggests vibes and details you can review.',
      ),
      _Step.review => (
        'Review the suggestions',
        'Pick what to add. Nothing you already chose is removed.',
      ),
      _Step.basics => ('The basics', 'Name, dates and budget.'),
      _Step.transport => ('Getting around', 'Optional. Pick one.'),
      _Step.group => ('Who is coming', 'Optional. Pick one.'),
      _Step.vibes => ('Vibes you want', 'Optional. Pick as many as you like.'),
    };
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (index >= 0) ...[
            Row(
              key: const ValueKey('trip-steps'),
              children: [
                for (var i = 0; i < _order.length; i++) ...[
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
            key: const ValueKey('trip-step-title'),
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
          if (formError != null) ...[
            _FormErrorBanner(message: formError),
            const SizedBox(height: 16),
          ],
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: KeyedSubtree(key: ValueKey(_step), child: _stepBody(errors)),
          ),
          const SizedBox(height: 26),
          _stepButtons(),
        ],
      ),
    );
  }

  Widget _stepBody(Map<String, String> errors) {
    switch (_step) {
      case _Step.describe:
        return DescribeTripCard(
          service: _preferences,
          enabled: !widget.isSubmitting,
          notice: null,
          showHeader: false,
          onSuggestions: _reviewSuggestions,
        );
      case _Step.review:
        final draft = _pending!;
        final newTags = [
          for (final tag in draft.preferredTags)
            if (!_tags.contains(tag)) tag,
        ];
        String human(String v) => v == 'unspecified'
            ? 'Not mentioned'
            : v
                  .split('_')
                  .map(
                    (w) => w.isEmpty
                        ? w
                        : '${w[0].toUpperCase()}${w.substring(1)}',
                  )
                  .join(' ');
        final group = chipOptionFor(kGroupTypes, draft.groupType)?.label;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (newTags.isEmpty)
              const Text(
                'No new vibes to add.',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppTheme.slateMuted,
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final tag in newTags)
                    _ReviewChip(
                      key: ValueKey('review-tag-$tag'),
                      option:
                          chipOptionFor(kPreferredTags, tag) ??
                          ChipOption(tag, human(tag), Icons.tag),
                      selected: _accepted.contains(tag),
                      onTap: () => setState(
                        () => _accepted.contains(tag)
                            ? _accepted.remove(tag)
                            : _accepted.add(tag),
                      ),
                    ),
                ],
              ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F8FC),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                children: [
                  _reviewLine('Who is coming', group ?? 'Not mentioned'),
                  _reviewLine(
                    'Budget',
                    draft.budgetMax == null
                        ? 'Not mentioned'
                        : '₱${_formatBudget(draft.budgetMin ?? 0)} – ₱${_formatBudget(draft.budgetMax!)}',
                  ),
                  _reviewLine('Pace', human(draft.pace)),
                  _reviewLine('Time of day', human(draft.duration)),
                ],
              ),
            ),
          ],
        );
      case _Step.basics:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_suggestionNotice != null) ...[
              StatusBanner(
                key: const ValueKey('describe-trip-notice'),
                tone: StatusTone.success,
                message: _suggestionNotice!,
              ),
              const SizedBox(height: 16),
            ],
            TactileTextField(
              key: const ValueKey('trip-title'),
              label: 'Trip name',
              controller: _title,
              hintText: 'e.g. Weekend food crawl',
              maxLength: TripFormValidators.titleMaxLength,
              textInputAction: TextInputAction.next,
              validator: TripFormValidators.title,
              serverError: errors['title'],
            ),
            const SizedBox(height: 18),
            DateRangeField(
              value: _dates,
              errorText: _basicsTried ? _datesError : errors['start_date'],
              onChanged: (range) => setState(() => _dates = range),
            ),
            const SizedBox(height: 18),
            BudgetRangeField(
              minController: _budgetMin,
              maxController: _budgetMax,
              minServerError: errors['budget_min'],
              maxServerError: errors['budget_max'],
            ),
          ],
        );
      case _Step.transport:
        return TactileChipsField(
          label: 'How you’ll get around',
          options: kTransportationModes,
          selected: _transport,
          errorText: errors['transportation_mode'],
          onChanged: (v) => setState(() => _transport = v),
        );
      case _Step.group:
        return TactileChipsField(
          label: 'Who is coming',
          options: kGroupTypes,
          selected: _group,
          errorText: errors['group_type'],
          onChanged: (v) => setState(() => _group = v),
        );
      case _Step.vibes:
        return TactileChipsField(
          label: 'Vibes',
          options: kPreferredTags,
          selected: _tags,
          multiSelect: true,
          maxSelected: TripFormValidators.maxTags,
          errorText: errors['preferred_tags'],
          onChanged: (v) => setState(() => _tags = v),
        );
    }
  }

  Widget _reviewLine(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.slateMuted,
            ),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w800,
            color: AppTheme.slateDark,
          ),
        ),
      ],
    ),
  );

  Widget _stepButtons() {
    final busy = widget.isSubmitting;
    Widget back(VoidCallback? onTap, {String label = 'Back', String? key}) =>
        _StepButton(
          key: key == null ? null : ValueKey(key),
          label: label,
          filled: false,
          onTap: busy ? null : onTap,
        );
    Widget next(
      String label,
      VoidCallback? onTap, {
      String key = 'trip-next',
      bool spinner = false,
    }) => _StepButton(
      key: ValueKey(key),
      label: label,
      filled: true,
      busy: spinner,
      onTap: busy ? null : onTap,
    );
    final (left, right) = switch (_step) {
      _Step.describe => (
        null,
        back(() => _go(_Step.basics), label: 'Skip', key: 'trip-skip-describe'),
      ),
      _Step.review => (
        back(() => _go(_Step.describe)),
        next('Apply to form', () {
          _applySuggestions(_pending!, _accepted.toList());
          _go(_Step.basics);
        }, key: 'review-apply'),
      ),
      _Step.basics => (
        back(() => _go(_Step.describe)),
        next('Next', _nextFromBasics),
      ),
      _Step.transport => (
        back(() => _go(_Step.basics)),
        next('Next', () => _go(_Step.group)),
      ),
      _Step.group => (
        back(() => _go(_Step.transport)),
        next('Next', () => _go(_Step.vibes)),
      ),
      _Step.vibes => (
        back(() => _go(_Step.group)),
        next(
          busy ? 'Saving…' : widget.submitLabel,
          _submit,
          key: 'trip-submit',
          spinner: busy,
        ),
      ),
    };
    return Row(
      children: [
        if (left != null) ...[Expanded(child: left), const SizedBox(width: 10)],
        Expanded(flex: left == null ? 1 : 2, child: right),
      ],
    );
  }

  Widget _section(int index, List<Widget> children, {bool divider = false}) {
    if (widget.flat) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (index > 0 || divider)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Divider(height: 1, color: Color(0xFFE9EEF5)),
            ),
          ...children,
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: FadeSlideIn(
        index: index,
        child: GlassContainer(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );
  }
}

class _FormErrorBanner extends StatelessWidget {
  final String message;

  const _FormErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      tintColor: const Color(0xFFFFF1F2),
      borderColor: const Color(0xFFFECDD3),
      borderRadius: 18,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      boxShadow: const [
        BoxShadow(
          color: Color(0xFFFDA4AF),
          offset: Offset(0, 3),
          blurRadius: 0,
        ),
      ],
      child: Row(
        children: [
          const Icon(
            Icons.error_rounded,
            color: TactileFieldStyle.error,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppTheme.slateDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _Step { describe, review, basics, transport, group, vibes }

class _StepButton extends StatelessWidget {
  final String label;
  final bool filled;
  final bool busy;
  final VoidCallback? onTap;

  const _StepButton({
    super.key,
    required this.label,
    required this.filled,
    required this.onTap,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    const shape = StadiumBorder();
    const size = Size.fromHeight(52);
    const text = TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800);
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (busy) ...[
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 10),
        ],
        Flexible(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
    return filled
        ? FilledButton(
            onPressed: onTap,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFF2620F),
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFFF7A26F),
              disabledForegroundColor: Colors.white,
              shape: shape,
              minimumSize: size,
              textStyle: text,
            ),
            child: child,
          )
        : OutlinedButton(
            onPressed: onTap,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.slateDark,
              side: const BorderSide(color: Color(0xFFD5DEEA)),
              shape: shape,
              minimumSize: size,
              textStyle: text,
            ),
            child: child,
          );
  }
}

class _ReviewChip extends StatelessWidget {
  final ChipOption option;
  final bool selected;
  final VoidCallback onTap;

  const _ReviewChip({
    super.key,
    required this.option,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFF2620F) : TactileFieldStyle.fill,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? Icons.check_rounded : option.icon,
                size: 16,
                color: selected ? Colors.white : AppTheme.primaryBlue,
              ),
              const SizedBox(width: 6),
              Text(
                option.label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : AppTheme.slateDark,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
