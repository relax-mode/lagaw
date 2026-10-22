import 'package:flutter/material.dart';

import '../../models/trip.dart';
import '../../services/trip_service.dart';
import '../../theme.dart';
import '../tactile_motion.dart';
import 'budget_range_field.dart';
import 'choice_chips_field.dart';
import 'date_range_field.dart';
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

  const TripForm({
    super.key,
    this.initial,
    required this.onSubmit,
    this.submitLabel = 'Save trip',
    this.isSubmitting = false,
    this.fieldErrors = const {},
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
      budgetMin: TripFormValidators.parseMoney(_budgetMin.text)!,
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
              accent: const Color(0xFF7C3AED),
              accentShadow: const Color(0xFF5B21B6),
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
              accent: const Color(0xFFEA580C),
              accentShadow: const Color(0xFF9A3412),
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

  Widget _section(int index, List<Widget> children) {
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
