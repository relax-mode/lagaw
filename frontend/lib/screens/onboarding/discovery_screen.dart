import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/onboarding_preferences.dart';
import '../../models/trip_plan.dart';
import '../../services/discovery_service.dart';
import '../../theme.dart';
import '../../widgets/destination_tile.dart';
import '../../widgets/status_banner.dart';
import '../../widgets/trip_form/choice_chips_field.dart';
import '../../widgets/trip_form/tactile_text_field.dart';
import '../../widgets/trip_form/trip_form.dart';
import '../trip_page_scaffold.dart';

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

/// "Picked for you": cold-start recommendations from the user's saved
/// onboarding interests (#103). Who is coming and the per-place limit are
/// asked, never assumed, because the API needs both and the profile budget
/// has no per-visit meaning. Nothing here is saved. [S4-04]
class DiscoveryScreen extends StatefulWidget {
  final DiscoveryService service;

  const DiscoveryScreen({super.key, required this.service});

  @override
  State<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends State<DiscoveryScreen> {
  final _customController = TextEditingController();
  String? _group;
  String? _budgetChoice;
  String? _customError;

  bool _loading = false;
  DiscoveryPage? _page;
  DiscoveryApiException? _error;

  /// Ignores responses from superseded searches.
  int _generation = 0;

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
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
      });
    } on DiscoveryApiException catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return TripPageScaffold(
      title: 'picked for you',
      subtitle: 'Based on your travel preferences',
      children: [_setup(), const SizedBox(height: 16), ..._results()],
    );
  }

  Widget _setup() {
    return GlassContainer(
      key: const ValueKey('discovery-setup'),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Two quick things to find your places',
            style: TextStyle(
              fontFamily: 'Outfit',
              fontWeight: FontWeight.w900,
              fontSize: 18,
              color: AppTheme.slateDark,
            ),
          ),
          const SizedBox(height: 16),
          TactileChipsField(
            label: 'Who’s coming?',
            optional: false,
            options: kDiscoveryGroups,
            selected: [?_group],
            onChanged: (values) =>
                setState(() => _group = values.isEmpty ? null : values.first),
          ),
          const SizedBox(height: 16),
          TactileChipsField(
            label: 'Max you’d spend per place, per person',
            optional: false,
            options: kPerPlaceBudgets,
            selected: [?_budgetChoice],
            onChanged: (values) => setState(() {
              _budgetChoice = values.isEmpty ? null : values.first;
              _customError = null;
            }),
          ),
          if (_budgetChoice == 'custom') ...[
            const SizedBox(height: 12),
            TactileTextField(
              key: const ValueKey('discovery-custom-budget'),
              label: 'Amount',
              controller: _customController,
              hintText: '750',
              prefixText: '₱ ',
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
              ],
              serverError: _customError,
            ),
          ],
          const SizedBox(height: 6),
          const Text(
            'Entrance fees and food at one place. Getting there isn’t '
            'included. Places with unknown prices are left out.',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 12,
              color: AppTheme.slateMuted,
            ),
          ),
          const SizedBox(height: 16),
          Opacity(
            opacity: _group != null && _budgetChoice != null ? 1 : 0.5,
            child: Vector3DButton(
              key: const ValueKey('discovery-search'),
              onTap: _group != null && _budgetChoice != null && !_loading
                  ? _search
                  : null,
              backgroundColor: AppTheme.primaryBlue,
              shadowColor: const Color(0xFF1D4ED8),
              borderRadius: 20,
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_loading) ...[
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
                  Text(
                    _loading
                        ? 'Finding places…'
                        : _page == null
                        ? 'Show my places'
                        : 'Update places',
                    style: const TextStyle(
                      fontFamily: 'Outfit',
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      color: Colors.white,
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

  List<Widget> _results() {
    final error = _error;
    if (error != null) {
      return [
        StatusBanner(
          key: const ValueKey('discovery-error'),
          tone: StatusTone.error,
          message: error.message,
          actionLabel: error.statusCode == 422
              ? null
              : error.preferencesChanged
              ? 'Reload'
              : 'Try again',
          onAction: _search,
        ),
        if (_page != null) ...[const SizedBox(height: 16), ..._list(_page!)],
      ];
    }
    final page = _page;
    if (page == null) return const [];
    return _list(page);
  }

  List<Widget> _list(DiscoveryPage page) {
    if (page.items.isEmpty) {
      return const [
        StatusBanner(
          key: ValueKey('discovery-empty'),
          tone: StatusTone.info,
          message:
              'No places match yet. Try a higher limit per place or another '
              'group.',
        ),
      ];
    }
    return [
      const Padding(
        padding: EdgeInsets.only(left: 4, bottom: 10),
        child: Text(
          'Your top places',
          style: TextStyle(
            fontFamily: 'Outfit',
            fontWeight: FontWeight.w900,
            fontSize: 18,
            color: Colors.white,
          ),
        ),
      ),
      for (final item in page.items) ...[
        _RecommendationCard(item: item),
        const SizedBox(height: 10),
      ],
    ];
  }
}

class _RecommendationCard extends StatelessWidget {
  final TripRecommendation item;
  const _RecommendationCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final percent = (item.score * 100).round().clamp(0, 100);
    return DestinationTile(
      key: ValueKey('discovery-${item.locationId}'),
      location: item.location,
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFF0FDF4),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          '$percent%',
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            color: Color(0xFF16A34A),
          ),
        ),
      ),
      footer: Text(
        item.reason,
        style: const TextStyle(
          fontStyle: FontStyle.italic,
          fontSize: 12,
          color: AppTheme.slateMuted,
        ),
      ),
    );
  }
}
