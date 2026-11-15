import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/location.dart';
import '../../models/onboarding_preferences.dart';
import '../../models/trip_plan.dart';
import '../../services/discovery_service.dart';
import '../../theme.dart';
import '../../widgets/destination_photo.dart';
import '../../widgets/popup_route.dart';
import '../../widgets/status_banner.dart';
import '../../widgets/trip_form/choice_chips_field.dart';
import '../../widgets/trip_form/trip_form.dart';
import '../home/home_view.dart' show HomeCategory;
import '../spots/spots_view.dart' show PlaceActions, openPlaceDetails;

/// Groups the cold-start API accepts, labelled like the trip form.
final List<ChipOption> kDiscoveryGroups = [
  for (final option in kGroupTypes)
    if (kPlannableGroups.contains(option.value)) option,
  const ChipOption('group', 'Big group', Icons.diversity_3_rounded),
];

/// Quick per-place spending ceilings; `custom` opens a field.
const List<ChipOption> kPerPlaceBudgets = [
  ChipOption('0.00', 'Free only', Icons.money_off_rounded),
  ChipOption('200.00', '₱200', Icons.payments_rounded),
  ChipOption('500.00', '₱500', Icons.payments_rounded),
  ChipOption('1000.00', '₱1,000', Icons.payments_rounded),
  ChipOption('custom', 'Custom', Icons.edit_rounded),
];

/// Opens "Picked for you" as a pop-up over the blurred app, like travel
/// preferences. [home v3]
Future<void> showPickedForYou(
  BuildContext context, {
  required DiscoveryService service,
  bool review = true,
  PlaceActions? actions,
  Future<void> Function(BuildContext context)? onEditPreferences,
}) {
  return Navigator.of(context).push(
    pickedForYouRoute(
      (_) => DiscoveryScreen(
        service: service,
        review: review,
        actions: actions,
        onEditPreferences: onEditPreferences,
      ),
    ),
  );
}

/// The pop-up route (shared with the other pop-up pages).
Route<void> pickedForYouRoute(WidgetBuilder builder) =>
    blurPopupRoute<void>(builder);

enum _Step { review, setup, results }

/// "Picked for you": cold-start recommendations from the user's saved
/// onboarding interests (#103), in one pop-up card with three steps:
/// review the preferences (or edit them), answer who is coming and the
/// per-place limit (asked, never assumed: the API needs both and the
/// profile budget has no per-visit meaning), then the top places in rank
/// order, each with a heart and a tap for details. [S4-04, home v3]
class DiscoveryScreen extends StatefulWidget {
  final DiscoveryService service;

  /// Start by reviewing the saved preferences (from You). Right after
  /// onboarding they were just reviewed, so it starts at the questions.
  final bool review;

  /// Hearts and details on the results; hidden without them.
  final PlaceActions? actions;

  /// Opens travel preferences for editing; the review reloads after.
  final Future<void> Function(BuildContext context)? onEditPreferences;

  const DiscoveryScreen({
    super.key,
    required this.service,
    this.review = false,
    this.actions,
    this.onEditPreferences,
  });

  @override
  State<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends State<DiscoveryScreen> {
  final _customController = TextEditingController();
  late _Step _step = widget.review ? _Step.review : _Step.setup;

  OnboardingPreferences? _prefs;
  bool _prefsLoading = false;
  String? _prefsError;

  String? _group;
  String? _budgetChoice;
  String? _customError;

  bool _loading = false;
  DiscoveryPage? _page;
  DiscoveryApiException? _error;

  /// Ignores responses from superseded searches.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    if (widget.review) _loadPrefs();
  }

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    setState(() {
      _prefsLoading = true;
      _prefsError = null;
    });
    try {
      final prefs = await widget.service.load();
      if (!mounted) return;
      setState(() {
        _prefs = prefs;
        _prefsLoading = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _prefsLoading = false;
        _prefsError = 'Couldn’t load your preferences.';
      });
    }
  }

  Future<void> _edit() async {
    final edit = widget.onEditPreferences;
    if (edit == null) return;
    await edit(context);
    if (mounted) _loadPrefs();
  }

  String? get _perVisitMax {
    if (_budgetChoice == null) return null;
    if (_budgetChoice != 'custom') return _budgetChoice;
    final parsed = parseBudgetAmount(_customController.text);
    return parsed.error == null ? parsed.value : null;
  }

  bool get _ready => _group != null && _perVisitMax != null;

  Future<void> _search() async {
    if (_budgetChoice == 'custom') {
      final parsed = parseBudgetAmount(_customController.text);
      setState(
        () => _customError =
            parsed.error ??
            (parsed.value == null ? 'Enter an amount in pesos.' : null),
      );
    }
    if (!_ready || _loading) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.service.recommend(
        DiscoveryRequest(groupType: _group!, perVisitBudgetMax: _perVisitMax!),
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _page = page;
        _loading = false;
        _step = _Step.results;
      });
    } on DiscoveryApiException catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = e;
        _loading = false;
        // Keep earlier results in view, with the error above them.
        if (_page != null) _step = _Step.results;
      });
    }
  }

  void _close() => Navigator.of(context).maybePop();

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.viewInsetsOf(context);
    final (title, subtitle) = switch (_step) {
      _Step.review => ('Your travel preferences', 'Look good?'),
      _Step.setup => ('Two quick things', 'So the places fit this outing.'),
      _Step.results => ('Your top places', 'Best match first.'),
    };
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _loading ? null : _close,
            ),
          ),
          SafeArea(
            child: Center(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + insets.bottom),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x660A1830),
                          blurRadius: 40,
                          offset: Offset(0, 22),
                          spreadRadius: -14,
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Header(
                          title: title,
                          subtitle: subtitle,
                          step: _step.index,
                          onClose: _loading ? null : _close,
                        ),
                        Flexible(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 240),
                            child: KeyedSubtree(
                              key: ValueKey(_step),
                              child: switch (_step) {
                                _Step.review => _reviewBody(),
                                _Step.setup => _setupBody(),
                                _Step.results => _resultsBody(),
                              },
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
                          child: _footer(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _scroll(List<Widget> children) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );

  // Review ------------------------------------------------------------------

  Widget _reviewBody() {
    final prefs = _prefs;
    if (_prefsLoading && prefs == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 36),
        child: Center(child: CircularProgressIndicator(color: _orange)),
      );
    }
    if (_prefsError != null) {
      return _scroll([
        StatusBanner(
          tone: StatusTone.error,
          message: _prefsError!,
          actionLabel: 'Retry',
          onAction: _loadPrefs,
        ),
      ]);
    }
    final tags = [
      for (final o in kPreferredTags)
        if (prefs?.preferredTags.contains(o.value) ?? false) o.label,
    ];
    String peso(String a) {
      final whole = a
          .split('.')
          .first
          .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
      return '₱$whole';
    }

    const paces = {'slow': 'Slow', 'moderate': 'Moderate', 'fast': 'Fast'};
    return _scroll([
      Container(
        key: const ValueKey('picked-review'),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F8FC),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            _ReviewLine(
              label: 'Interests',
              value: tags.isEmpty ? 'None yet' : tags.join(', '),
            ),
            const Divider(height: 1, color: Color(0xFFE3E9F2)),
            _ReviewLine(
              label: 'Budget',
              value: prefs?.hasBudget ?? false
                  ? '${peso(prefs!.budgetMin!)} – ${peso(prefs.budgetMax!)}'
                  : 'No preference',
            ),
            const Divider(height: 1, color: Color(0xFFE3E9F2)),
            _ReviewLine(
              label: 'Pace',
              value: paces[prefs?.travelStyle] ?? 'No preference',
            ),
          ],
        ),
      ),
    ]);
  }

  // Setup -------------------------------------------------------------------

  Widget _chips(
    List<ChipOption> options,
    String? selected,
    ValueChanged<String?> onChanged,
  ) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final o in options)
          _Chip(
            key: ValueKey('chip-${o.value}'),
            label: o.label,
            icon: o.icon,
            selected: selected == o.value,
            onTap: () => onChanged(selected == o.value ? null : o.value),
          ),
      ],
    );
  }

  Widget _question(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w800,
        color: AppTheme.slateDark,
      ),
    ),
  );

  Widget _setupBody() {
    return _scroll([
      Column(
        key: const ValueKey('discovery-setup'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _question('Who’s coming?'),
          _chips(kDiscoveryGroups, _group, (v) => setState(() => _group = v)),
          const SizedBox(height: 22),
          _question('Max you’d spend per place, per person'),
          _chips(
            kPerPlaceBudgets,
            _budgetChoice,
            (v) => setState(() {
              _budgetChoice = v;
              _customError = null;
            }),
          ),
          if (_budgetChoice == 'custom') ...[
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('discovery-custom-budget'),
              controller: _customController,
              onChanged: (_) => setState(() {}),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
              ],
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.slateDark,
              ),
              decoration: InputDecoration(
                hintText: '750',
                prefixText: '₱ ',
                errorText: _customError,
                filled: true,
                fillColor: const Color(0xFFF1F5FB),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: _orange, width: 1.6),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          const Text(
            'Entrance fees and food at one place; getting there isn’t '
            'included. Places with unknown prices are left out.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              fontWeight: FontWeight.w500,
              color: AppTheme.slateMuted,
            ),
          ),
          if (_error != null) ...[const SizedBox(height: 14), _errorBanner()],
        ],
      ),
    ]);
  }

  Widget _errorBanner() {
    final error = _error!;
    return StatusBanner(
      key: const ValueKey('discovery-error'),
      tone: StatusTone.error,
      message: error.message,
      actionLabel: error.statusCode == 422
          ? null
          : error.preferencesChanged
          ? 'Reload'
          : 'Try again',
      onAction: _search,
    );
  }

  // Results -----------------------------------------------------------------

  Widget _resultsBody() {
    final page = _page;
    if (page == null || page.items.isEmpty) {
      return _scroll([
        if (_error != null) ...[_errorBanner(), const SizedBox(height: 12)],
        const StatusBanner(
          key: ValueKey('discovery-empty'),
          tone: StatusTone.info,
          message:
              'No places match yet. Try a higher limit per place or another '
              'group.',
        ),
      ]);
    }
    final actions = widget.actions;
    Widget list() => Column(
      children: [
        for (final (i, item) in page.items.indexed) ...[
          if (i > 0) const SizedBox(height: 10),
          _PlaceRow(
            key: ValueKey('discovery-${item.locationId}'),
            rank: i + 1,
            place: item.location,
            actions: actions,
          ),
        ],
      ],
    );
    return _scroll([
      if (_error != null) ...[_errorBanner(), const SizedBox(height: 12)],
      if (actions?.changes != null)
        ListenableBuilder(
          listenable: actions!.changes!,
          builder: (context, _) => list(),
        )
      else
        list(),
    ]);
  }

  // Footer ------------------------------------------------------------------

  Widget _footer() {
    switch (_step) {
      case _Step.review:
        return Row(
          children: [
            if (widget.onEditPreferences != null) ...[
              Expanded(
                child: _Outline(
                  key: const ValueKey('picked-edit'),
                  label: 'Edit',
                  icon: Icons.edit_rounded,
                  onTap: _prefsLoading ? null : _edit,
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              flex: 2,
              child: _Filled(
                key: const ValueKey('picked-continue'),
                label: 'Looks good',
                onTap: _prefsLoading || _prefs == null
                    ? null
                    : () => setState(() => _step = _Step.setup),
              ),
            ),
          ],
        );
      case _Step.setup:
        return Row(
          children: [
            if (widget.review) ...[
              Expanded(
                child: _Outline(
                  key: const ValueKey('picked-back'),
                  label: 'Back',
                  onTap: _loading
                      ? null
                      : () => setState(() => _step = _Step.review),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              flex: 2,
              child: _Filled(
                key: const ValueKey('discovery-search'),
                label: _loading
                    ? 'Finding places…'
                    : _page == null
                    ? 'Show my places'
                    : 'Update places',
                busy: _loading,
                onTap: _group != null && _budgetChoice != null && !_loading
                    ? _search
                    : null,
              ),
            ),
          ],
        );
      case _Step.results:
        return Row(
          children: [
            Expanded(
              child: _Outline(
                key: const ValueKey('picked-change'),
                label: 'Change answers',
                onTap: () => setState(() => _step = _Step.setup),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _Filled(
                key: const ValueKey('picked-done'),
                label: 'Done',
                onTap: _close,
              ),
            ),
          ],
        );
    }
  }
}

const _orange = Color(0xFFF2620F);

class _Header extends StatelessWidget {
  final String title;
  final String subtitle;
  final int step;
  final VoidCallback? onClose;

  const _Header({
    required this.title,
    required this.subtitle,
    required this.step,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.skyTop, AppTheme.skyMid],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'PICKED FOR YOU',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                    color: Color(0xD9FFFFFF),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  key: const ValueKey('picked-title'),
                  style: const TextStyle(
                    fontSize: 21,
                    height: 1.15,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xE6FFFFFF),
                  ),
                ),
              ],
            ),
          ),
          if (onClose != null)
            Semantics(
              button: true,
              label: 'Close',
              child: GestureDetector(
                key: const ValueKey('picked-close'),
                onTap: onClose,
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xEBFFFFFF),
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    size: 19,
                    color: AppTheme.slateDark,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ReviewLine extends StatelessWidget {
  final String label;
  final String value;

  const _ReviewLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 82,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.slateMuted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppTheme.slateDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One top place: rank, square photo, name, category · price, and a heart.
/// Tapping it opens the full details.
class _PlaceRow extends StatelessWidget {
  final int rank;
  final LocationItem place;
  final PlaceActions? actions;

  const _PlaceRow({
    super.key,
    required this.rank,
    required this.place,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final a = actions;
    final liked = a?.isSaved(place.id) ?? false;
    final busy = a?.isBusy(place.id) ?? false;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: a == null
          ? null
          : () {
              final box = context.findRenderObject() as RenderBox?;
              if (box == null || !box.hasSize) return;
              openPlaceDetails(
                context,
                place: place,
                origin: box.localToGlobal(Offset.zero) & box.size,
                actions: a,
              );
            },
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F8FC),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              child: Text(
                '$rank',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.slateMuted,
                ),
              ),
            ),
            const SizedBox(width: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: DestinationPhoto(
                location: place,
                width: 58,
                height: 58,
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
                      fontSize: 15,
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
            if (a != null)
              Semantics(
                button: true,
                label: liked ? 'Liked' : 'Like ${place.name}',
                child: GestureDetector(
                  key: ValueKey('discovery-heart-${place.id}'),
                  onTap: busy ? null : () => a.onSave(place),
                  child: Container(
                    width: 42,
                    height: 42,
                    margin: const EdgeInsets.only(left: 6),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                    ),
                    child: Icon(
                      liked
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      size: 21,
                      color: _orange,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Filled extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool busy;

  const _Filled({
    super.key,
    required this.label,
    required this.onTap,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: _orange,
        foregroundColor: Colors.white,
        disabledBackgroundColor: const Color(0xFFF9C4A3),
        disabledForegroundColor: Colors.white,
        shape: const StadiumBorder(),
        minimumSize: const Size.fromHeight(50),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
      ),
      child: Row(
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
      ),
    );
  }
}

class _Outline extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;

  const _Outline({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.slateDark,
        side: const BorderSide(color: Color(0xFFD5DEEA)),
        shape: const StadiumBorder(),
        minimumSize: const Size.fromHeight(50),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 17), const SizedBox(width: 6)],
          Flexible(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

/// A choice: a soft pill that turns orange when picked, like onboarding.
class _Chip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _Chip({
    super.key,
    required this.label,
    required this.icon,
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
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? _orange : const Color(0xFFF1F5FB),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? Icons.check_rounded : icon,
                size: 17,
                color: selected ? Colors.white : AppTheme.primaryBlue,
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
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
