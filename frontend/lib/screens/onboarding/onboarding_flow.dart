import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/onboarding_preferences.dart';
import '../../services/onboarding_repository.dart';
import '../../theme.dart';
import '../../widgets/status_banner.dart';
import '../../widgets/trip_form/choice_chips_field.dart';
import '../../widgets/trip_form/tactile_text_field.dart';
import '../../widgets/trip_form/trip_form.dart';
import '../trip_page_scaffold.dart';

enum OnboardingStep { welcome, interests, budget, style, review, done }

const _questionSteps = [
  OnboardingStep.interests,
  OnboardingStep.budget,
  OnboardingStep.style,
  OnboardingStep.review,
];

const Map<String, ({String label, String blurb, IconData icon})> _styles = {
  'slow': (
    label: 'Slow',
    blurb: 'A few places, plenty of time at each.',
    icon: Icons.self_improvement_rounded,
  ),
  'moderate': (
    label: 'Moderate',
    blurb: 'A balanced day with time to wander.',
    icon: Icons.directions_walk_rounded,
  ),
  'fast': (
    label: 'Fast',
    blurb: 'See as much as possible.',
    icon: Icons.directions_run_rounded,
  ),
};

/// First-time travel preference onboarding: interests, budget and travel
/// style, then a review before saving. Uses [repository] for loading and
/// saving. Pops with the saved preferences, or replaces itself with
/// [next] (e.g. recommendations) after saving. [S4-01, S4-04]
class OnboardingFlow extends StatefulWidget {
  final OnboardingRepository repository;

  /// Shown after Done instead of popping.
  final WidgetBuilder? next;

  /// First-run only: offers "Skip for now" on the welcome step.
  final bool allowSkip;

  const OnboardingFlow({
    super.key,
    required this.repository,
    this.next,
    this.allowSkip = false,
  });

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  final _budgetForm = GlobalKey<FormState>();
  final _minController = TextEditingController();
  final _maxController = TextEditingController();

  OnboardingStep _step = OnboardingStep.welcome;
  OnboardingPreferences _prefs = OnboardingPreferences.empty;
  bool _loading = true;
  String? _loadError;
  bool _saving = false;
  String? _saveError;
  bool _showTagError = false;

  /// Set when a step was opened from Review, so Next returns there.
  bool _editingFromReview = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _minController.dispose();
    _maxController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final prefs = await widget.repository.load();
      if (!mounted) return;
      setState(() {
        _prefs = OnboardingPreferences(
          // Drop anything outside the approved vocabulary.
          preferredTags: prefs.preferredTags
              .where(kOnboardingTags.contains)
              .toList(),
          budgetMin: prefs.budgetMin,
          budgetMax: prefs.budgetMax,
          travelStyle: kTravelStyles.contains(prefs.travelStyle)
              ? prefs.travelStyle
              : null,
        );
        _minController.text = prefs.budgetMin ?? '';
        _maxController.text = prefs.budgetMax ?? '';
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = 'Couldn’t load your preferences. Try again.';
      });
    }
  }

  void _goTo(OnboardingStep step) => setState(() {
    _step = step;
    _saveError = null;
  });

  void _next() {
    switch (_step) {
      case OnboardingStep.welcome:
        _goTo(OnboardingStep.interests);
      case OnboardingStep.interests:
        if (_prefs.preferredTags.isEmpty) {
          setState(() => _showTagError = true);
          return;
        }
        _advanceFrom(OnboardingStep.budget);
      case OnboardingStep.budget:
        if (!(_budgetForm.currentState?.validate() ?? false)) return;
        final range = validateBudgetRange(
          _minController.text,
          _maxController.text,
        );
        _prefs = _prefs.copyWith(
          budgetMin: () => range.min,
          budgetMax: () => range.max,
        );
        _advanceFrom(OnboardingStep.style);
      case OnboardingStep.style:
        _advanceFrom(OnboardingStep.review);
      case OnboardingStep.review:
      case OnboardingStep.done:
        break;
    }
  }

  void _advanceFrom(OnboardingStep next) {
    if (_editingFromReview) {
      _editingFromReview = false;
      _goTo(OnboardingStep.review);
    } else {
      _goTo(next);
    }
  }

  void _skipBudget() {
    _minController.clear();
    _maxController.clear();
    _budgetForm.currentState?.reset();
    _prefs = _prefs.copyWith(budgetMin: () => null, budgetMax: () => null);
    _advanceFrom(OnboardingStep.style);
  }

  void _back() {
    if (_editingFromReview) {
      _editingFromReview = false;
      _goTo(OnboardingStep.review);
      return;
    }
    final index = OnboardingStep.values.indexOf(_step);
    if (index > 0) _goTo(OnboardingStep.values[index - 1]);
  }

  void _edit(OnboardingStep step) {
    _editingFromReview = true;
    _goTo(step);
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final saved = await widget.repository.save(_prefs);
      if (!mounted) return;
      setState(() {
        _prefs = saved;
        _saving = false;
        _step = OnboardingStep.done;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = e is OnboardingSaveException
            ? e.message
            : 'Couldn’t save your preferences. Try again.';
      });
    }
  }

  bool get _canLeave =>
      !_saving &&
      (_step == OnboardingStep.welcome || _step == OnboardingStep.done);

  @override
  Widget build(BuildContext context) {
    final questionIndex = _questionSteps.indexOf(_step);
    return PopScope(
      canPop: _canLeave || _loading || _loadError != null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_saving) _back();
      },
      child: TripPageScaffold(
        title: 'travel preferences',
        subtitle: questionIndex >= 0
            ? 'Step ${questionIndex + 1} of ${_questionSteps.length}'
            : 'Tell us how you like to explore',
        children: [
          if (questionIndex >= 0) ...[
            _ProgressBar(value: (questionIndex + 1) / _questionSteps.length),
            const SizedBox(height: 16),
          ],
          ..._body(),
        ],
      ),
    );
  }

  List<Widget> _body() {
    if (_loading) {
      return const [
        GlassContainer(
          key: ValueKey('onboarding-loading'),
          padding: EdgeInsets.all(28),
          child: Column(
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 14),
              Text(
                'Loading your preferences…',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.slateMuted,
                ),
              ),
            ],
          ),
        ),
      ];
    }
    if (_loadError != null) {
      return [
        StatusBanner(
          key: const ValueKey('onboarding-load-error'),
          tone: StatusTone.error,
          message: _loadError!,
          actionLabel: 'Retry',
          onAction: _load,
        ),
      ];
    }
    return switch (_step) {
      OnboardingStep.welcome => _welcome(),
      OnboardingStep.interests => _interests(),
      OnboardingStep.budget => _budget(),
      OnboardingStep.style => _style(),
      OnboardingStep.review => _review(),
      OnboardingStep.done => _done(),
    };
  }

  List<Widget> _welcome() => [
    _Card(
      icon: Icons.waving_hand_rounded,
      title: 'Welcome to Lagaw!',
      body:
          'Answer three quick questions so we can suggest places in Bacolod '
          'that fit you. You can change them anytime.',
      children: const [
        _Bullet(Icons.interests_rounded, 'What you love to do'),
        _Bullet(Icons.payments_rounded, 'Your usual budget'),
        _Bullet(Icons.speed_rounded, 'How you like to pace your day'),
      ],
    ),
    const SizedBox(height: 16),
    _PrimaryButton(
      key: const ValueKey('onboarding-start'),
      label: 'Get started',
      onTap: _next,
    ),
    if (widget.allowSkip) ...[
      const SizedBox(height: 8),
      Center(
        child: TextButton(
          key: const ValueKey('onboarding-skip'),
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(foregroundColor: Colors.white),
          child: const Text('Skip for now'),
        ),
      ),
    ],
  ];

  List<Widget> _interests() => [
    _Card(
      icon: Icons.interests_rounded,
      title: 'What do you love to do?',
      body: 'Pick at least one.',
      children: [
        TactileChipsField(
          label: 'Interests',
          optional: false,
          multiSelect: true,
          options: [
            for (final option in kPreferredTags)
              if (kOnboardingTags.contains(option.value)) option,
          ],
          selected: _prefs.preferredTags,
          errorText: _showTagError && _prefs.preferredTags.isEmpty
              ? 'Choose at least one interest.'
              : null,
          onChanged: (tags) =>
              setState(() => _prefs = _prefs.copyWith(preferredTags: tags)),
        ),
      ],
    ),
    const SizedBox(height: 16),
    _NavRow(onBack: _back, onNext: _next),
  ];

  static final _amountFormatters = [
    FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
  ];

  List<Widget> _budget() => [
    _Card(
      icon: Icons.payments_rounded,
      title: 'What’s your usual budget?',
      body:
          'Your typical spend per trip in pesos. Leave both empty if you’d '
          'rather not say.',
      children: [
        Form(
          key: _budgetForm,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TactileTextField(
                  key: const ValueKey('onboarding-budget-min'),
                  label: 'Min',
                  optional: true,
                  controller: _minController,
                  hintText: '500',
                  prefixText: '₱ ',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: _amountFormatters,
                  validator: (_) => validateBudgetRange(
                    _minController.text,
                    _maxController.text,
                  ).minError,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TactileTextField(
                  key: const ValueKey('onboarding-budget-max'),
                  label: 'Max',
                  optional: true,
                  controller: _maxController,
                  hintText: '2,000',
                  prefixText: '₱ ',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: _amountFormatters,
                  validator: (_) => validateBudgetRange(
                    _minController.text,
                    _maxController.text,
                  ).maxError,
                ),
              ),
            ],
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: const ValueKey('onboarding-skip-budget'),
            onPressed: _skipBudget,
            child: const Text('Skip, no budget preference'),
          ),
        ),
      ],
    ),
    const SizedBox(height: 16),
    _NavRow(onBack: _back, onNext: _next),
  ];

  List<Widget> _style() => [
    _Card(
      icon: Icons.speed_rounded,
      title: 'How do you like to travel?',
      body: 'Optional. Tap again to clear.',
      children: [
        for (final entry in _styles.entries) ...[
          _StyleOption(
            key: ValueKey('style-${entry.key}'),
            label: entry.value.label,
            blurb: entry.value.blurb,
            icon: entry.value.icon,
            selected: _prefs.travelStyle == entry.key,
            onTap: () => setState(
              () => _prefs = _prefs.copyWith(
                travelStyle: () =>
                    _prefs.travelStyle == entry.key ? null : entry.key,
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    ),
    const SizedBox(height: 16),
    _NavRow(onBack: _back, onNext: _next),
  ];

  List<Widget> _review() {
    final tagLabels = [
      for (final option in kPreferredTags)
        if (_prefs.preferredTags.contains(option.value)) option.label,
    ];
    return [
      _Card(
        icon: Icons.fact_check_rounded,
        title: 'Look good?',
        body: 'Check your answers before saving.',
        children: [
          _ReviewRow(
            editKey: 'review-edit-interests',
            label: 'Interests',
            value: tagLabels.join(', '),
            onEdit: _saving ? null : () => _edit(OnboardingStep.interests),
          ),
          _ReviewRow(
            editKey: 'review-edit-budget',
            label: 'Budget',
            value: _prefs.hasBudget
                ? '₱${_peso(_prefs.budgetMin!)} – ₱${_peso(_prefs.budgetMax!)}'
                : 'No preference',
            onEdit: _saving ? null : () => _edit(OnboardingStep.budget),
          ),
          _ReviewRow(
            editKey: 'review-edit-style',
            label: 'Travel style',
            value: _styles[_prefs.travelStyle]?.label ?? 'No preference',
            onEdit: _saving ? null : () => _edit(OnboardingStep.style),
          ),
        ],
      ),
      if (_saveError != null) ...[
        const SizedBox(height: 14),
        StatusBanner(
          key: const ValueKey('onboarding-save-error'),
          tone: StatusTone.error,
          message: _saveError!,
        ),
      ],
      const SizedBox(height: 16),
      _NavRow(
        onBack: _saving ? null : _back,
        onNext: _saving ? null : _save,
        nextKey: 'onboarding-save',
        nextLabel: _saveError != null ? 'Try again' : 'Save preferences',
        busy: _saving,
      ),
    ];
  }

  List<Widget> _done() => [
    _Card(
      icon: Icons.check_circle_rounded,
      title: 'You’re all set!',
      body:
          'Your preferences are saved. We’ll use them to suggest places '
          'you’ll like.',
      children: const [],
    ),
    const SizedBox(height: 16),
    _PrimaryButton(
      key: const ValueKey('onboarding-finish'),
      label: widget.next == null ? 'Done' : 'See places for me',
      onTap: () {
        final next = widget.next;
        if (next == null) {
          Navigator.of(context).pop(_prefs);
        } else {
          Navigator.of(context)
              .pushReplacement(MaterialPageRoute<void>(builder: next));
        }
      },
    ),
  ];
}

/// "1500.00" → "1,500"; keeps centavos when present.
String _peso(String amount) {
  final parts = amount.split('.');
  final whole = parts[0].replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  final cents = parts.length > 1 ? parts[1] : '00';
  return cents == '00' ? whole : '$whole.$cents';
}

class _ProgressBar extends StatelessWidget {
  final double value;
  const _ProgressBar({required this.value});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: value),
        duration: const Duration(milliseconds: 250),
        builder: (context, v, _) => LinearProgressIndicator(
          key: const ValueKey('onboarding-progress'),
          value: v,
          minHeight: 8,
          backgroundColor: const Color(0x66FFFFFF),
          color: Colors.white,
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final List<Widget> children;

  const _Card({
    required this.icon,
    required this.title,
    required this.body,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: AppTheme.primaryBlue),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Outfit',
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                    color: AppTheme.slateDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: AppTheme.slateMuted,
            ),
          ),
          if (children.isNotEmpty) const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Bullet(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppTheme.primaryBlue),
          const SizedBox(width: 10),
          Text(
            text,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: AppTheme.slateDark,
            ),
          ),
        ],
      ),
    );
  }
}

class _StyleOption extends StatelessWidget {
  final String label;
  final String blurb;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _StyleOption({
    super.key,
    required this.label,
    required this.blurb,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: Vector3DButton(
        onTap: onTap,
        backgroundColor: selected ? AppTheme.primaryBlue : Colors.white,
        shadowColor: selected
            ? const Color(0xFF1D4ED8)
            : const Color(0xFFCBD5E1),
        borderColor: selected ? Colors.white : const Color(0xFFE2E8F0),
        borderRadius: 18,
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(icon, color: selected ? Colors.white : AppTheme.primaryBlue),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      color: selected ? Colors.white : AppTheme.slateDark,
                    ),
                  ),
                  Text(
                    blurb,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                      color: selected
                          ? const Color(0xE6FFFFFF)
                          : AppTheme.slateMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle_rounded, color: Colors.white),
          ],
        ),
      ),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  final String editKey;
  final String label;
  final String value;
  final VoidCallback? onEdit;

  const _ReviewRow({
    required this.editKey,
    required this.label,
    required this.value,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                    color: AppTheme.slateMuted,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontFamily: 'Outfit',
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: AppTheme.slateDark,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            key: ValueKey(editKey),
            onPressed: onEdit,
            child: const Text('Edit'),
          ),
        ],
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  final VoidCallback? onBack;
  final VoidCallback? onNext;
  final String nextKey;
  final String nextLabel;
  final bool busy;

  const _NavRow({
    required this.onBack,
    required this.onNext,
    this.nextKey = 'onboarding-next',
    this.nextLabel = 'Next',
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Vector3DButton(
          key: const ValueKey('onboarding-back'),
          onTap: onBack,
          backgroundColor: Colors.white,
          shadowColor: const Color(0xFFCBD5E1),
          borderColor: const Color(0xFFE2E8F0),
          borderRadius: 20,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: const Text(
            'Back',
            style: TextStyle(
              fontFamily: 'Outfit',
              fontWeight: FontWeight.w900,
              color: AppTheme.slateDark,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _PrimaryButton(
            key: ValueKey(nextKey),
            label: nextLabel,
            onTap: onNext,
            busy: busy,
          ),
        ),
      ],
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool busy;

  const _PrimaryButton({
    super.key,
    required this.label,
    required this.onTap,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    return Vector3DButton(
      onTap: onTap,
      backgroundColor: AppTheme.primaryBlue,
      shadowColor: const Color(0xFF1D4ED8),
      borderRadius: 20,
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (busy) ...[
            const SizedBox(
              key: ValueKey('onboarding-saving'),
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
            busy ? 'Saving…' : label,
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
