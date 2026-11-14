import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/onboarding_preferences.dart';
import '../../models/trip_plan.dart';
import '../../services/discovery_service.dart';
import '../../theme.dart';
import '../../widgets/destination_photo.dart';
import '../../widgets/status_banner.dart';
import '../../widgets/trip_form/choice_chips_field.dart';
import '../../widgets/trip_form/trip_form.dart';
import '../home/home_view.dart' show HomeCategory;

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
/// has no per-visit meaning. Nothing here is saved. Styled like the v3
/// home and Spots: sky, centered title, white cards, orange pills.
/// [S4-04, home v3]
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
    final pad = MediaQuery.paddingOf(context);
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppTheme.skyTop, AppTheme.skyMid, AppTheme.skyBottom],
            stops: [0.0, 0.48, 1.0],
          ),
        ),
        child: Stack(
          children: [
            const Positioned(top: -80, left: -80, child: _Sun()),
            // Still elements, so the page settles (and tests can settle).
            Positioned(
              top: pad.top + 64,
              left: -34,
              child: Transform.rotate(
                angle: -0.28,
                child: Image.asset('assets/elements/masskara.webp', width: 112),
              ),
            ),
            Positioned(
              top: pad.top + 92,
              right: -30,
              child: Transform.rotate(
                angle: 0.32,
                child: Image.asset('assets/elements/piaya.webp', width: 104),
              ),
            ),
            SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: _CircleButton(
                          key: const ValueKey('discovery-back'),
                          icon: Icons.arrow_back_rounded,
                          label: 'Back',
                          onTap: () => Navigator.of(context).maybePop(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Picked\nfor you',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 40,
                          height: 0.98,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -1.4,
                          color: Colors.white,
                          shadows: [
                            Shadow(
                              color: Color(0x40104AA0),
                              blurRadius: 22,
                              offset: Offset(0, 6),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Based on your travel preferences',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xEBFFFFFF),
                        ),
                      ),
                      const SizedBox(height: 22),
                      _setup(),
                      const SizedBox(height: 20),
                      ..._results(),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w800,
        color: AppTheme.slateDark,
      ),
    ),
  );

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

  Widget _setup() {
    final canSearch = _group != null && _budgetChoice != null && !_loading;
    return Container(
      key: const ValueKey('discovery-setup'),
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: _cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Two quick things',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 22,
              letterSpacing: -0.4,
              color: AppTheme.slateDark,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'So we can find places that fit this outing.',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppTheme.slateMuted,
            ),
          ),
          const SizedBox(height: 18),
          _label('Who’s coming?'),
          _chips(kDiscoveryGroups, _group, (v) => setState(() => _group = v)),
          const SizedBox(height: 18),
          _label('Max you’d spend per place, per person'),
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
            'Entrance fees and food at one place. Getting there isn’t '
            'included. Places with unknown prices are left out.',
            style: TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 12.5,
              height: 1.4,
              color: AppTheme.slateMuted,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const ValueKey('discovery-search'),
            onPressed: canSearch ? _search : null,
            style: FilledButton.styleFrom(
              backgroundColor: _orange,
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFFF9C4A3),
              disabledForegroundColor: Colors.white,
              shape: const StadiumBorder(),
              minimumSize: const Size.fromHeight(50),
              textStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
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
                ),
              ],
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
        padding: EdgeInsets.only(left: 4, bottom: 12),
        child: Text(
          'Your top places',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 22,
            letterSpacing: -0.5,
            color: AppTheme.slateDark,
          ),
        ),
      ),
      for (final item in page.items) ...[
        _RecommendationCard(item: item),
        const SizedBox(height: 12),
      ],
    ];
  }
}

const _orange = Color(0xFFF2620F);

final _cardDecoration = BoxDecoration(
  color: Colors.white,
  borderRadius: BorderRadius.circular(28),
  boxShadow: const [
    BoxShadow(
      color: Color(0x4D0F285A),
      blurRadius: 30,
      offset: Offset(0, 16),
      spreadRadius: -16,
    ),
  ],
);

class _Sun extends StatelessWidget {
  const _Sun();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      height: 240,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            Color(0xFFFFFBEB),
            Color(0xFFFEF08A),
            Color(0xFFF59E0B),
            Color(0x00F59E0B),
          ],
          stops: [0.0, 0.35, 0.7, 1.0],
        ),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _CircleButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xF5FFFFFF),
            boxShadow: [
              BoxShadow(
                color: Color(0x330F1B2D),
                blurRadius: 18,
                offset: Offset(0, 8),
                spreadRadius: -10,
              ),
            ],
          ),
          child: Icon(icon, size: 21, color: AppTheme.slateDark),
        ),
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

/// One recommendation: photo, name, category · price, why it fits, and
/// how well it matches.
class _RecommendationCard extends StatelessWidget {
  final TripRecommendation item;
  const _RecommendationCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final percent = (item.score * 100).round().clamp(0, 100);
    final place = item.location;
    return Container(
      key: ValueKey('discovery-${item.locationId}'),
      padding: const EdgeInsets.all(12),
      decoration: _cardDecoration.copyWith(
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: DestinationPhoto(
              location: place,
              width: 84,
              height: 96,
              compact: true,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        place.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16.5,
                          height: 1.15,
                          color: AppTheme.slateDark,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F8EE),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '$percent%',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF15803D),
                        ),
                      ),
                    ),
                  ],
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
                const SizedBox(height: 8),
                Text(
                  item.reason,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF334155),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
