import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/onboarding_preferences.dart';
import '../../services/onboarding_repository.dart';
import '../../theme.dart';
import '../../widgets/status_banner.dart';
import '../../widgets/trip_form/trip_form.dart';

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

/// Travel preferences as one card over the blurred app: interests, budget
/// and travel style, then a review before saving. Uses [repository] for loading and
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
    final view = _view();
    final canClose = _canLeave || _loading || _loadError != null;
    final insets = MediaQuery.viewInsetsOf(context);
    return PopScope(
      canPop: canClose,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_saving) _back();
      },
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            // Tapping the blurred app closes the card when nothing is lost.
            Positioned.fill(
              child: GestureDetector(
                key: const ValueKey('onboarding-backdrop'),
                behavior: HitTestBehavior.opaque,
                onTap: canClose ? () => Navigator.of(context).maybePop() : null,
              ),
            ),
            SafeArea(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + insets.bottom),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: _Sheet(
                      header: questionIndex >= 0
                          ? _StepHeader(
                              index: questionIndex,
                              total: _questionSteps.length,
                            )
                          : _ArtHeader(
                              done: _step == OnboardingStep.done,
                              onClose: canClose
                                  ? () => Navigator.of(context).maybePop()
                                  : null,
                            ),
                      view: view,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  _StepView _view() {
    if (_loading) {
      return const _StepView(
        id: 'loading',
        title: 'One moment',
        body: 'Loading your preferences…',
        content: [
          Center(
            key: ValueKey('onboarding-loading'),
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: CircularProgressIndicator(color: _orange),
            ),
          ),
        ],
      );
    }
    if (_loadError != null) {
      return _StepView(
        id: 'error',
        title: 'Something went wrong',
        body: 'Your preferences didn’t load.',
        content: [
          StatusBanner(
            key: const ValueKey('onboarding-load-error'),
            tone: StatusTone.error,
            message: _loadError!,
            actionLabel: 'Retry',
            onAction: _load,
          ),
        ],
      );
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

  _StepView _welcome() => _StepView(
    id: 'welcome',
    title: 'Welcome to Lagaw!',
    body:
        'Three quick questions so we can suggest places in Bacolod that fit '
        'you. You can change them anytime.',
    content: const [
      _Bullet(Icons.interests_rounded, 'What you love to do'),
      _Bullet(Icons.payments_rounded, 'Your usual budget'),
      _Bullet(Icons.speed_rounded, 'How you like to pace your day'),
    ],
    footer: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PrimaryButton(
          key: const ValueKey('onboarding-start'),
          label: 'Get started',
          onTap: _next,
        ),
        if (widget.allowSkip)
          TextButton(
            key: const ValueKey('onboarding-skip'),
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.slateMuted,
              textStyle: const TextStyle(fontWeight: FontWeight.w700),
            ),
            child: const Text('Skip for now'),
          ),
      ],
    ),
  );

  _StepView _interests() => _StepView(
    id: 'interests',
    title: 'What do you love to do?',
    body: 'Pick at least one.',
    content: [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final option in kPreferredTags)
            if (kOnboardingTags.contains(option.value))
              _Chip(
                key: ValueKey('chip-${option.value}'),
                label: option.label,
                icon: option.icon,
                selected: _prefs.preferredTags.contains(option.value),
                onTap: () => setState(() {
                  final tags = [..._prefs.preferredTags];
                  tags.contains(option.value)
                      ? tags.remove(option.value)
                      : tags.add(option.value);
                  _prefs = _prefs.copyWith(preferredTags: tags);
                }),
              ),
        ],
      ),
      if (_showTagError && _prefs.preferredTags.isEmpty)
        const Padding(
          padding: EdgeInsets.only(top: 10),
          child: Text(
            'Choose at least one interest.',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFFDC2626),
            ),
          ),
        ),
    ],
    footer: _NavRow(onBack: _back, onNext: _next),
  );

  static final _amountFormatters = [
    FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
  ];

  Widget _amount({
    required String key,
    required String label,
    required String hint,
    required TextEditingController controller,
    required String? Function() error,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppTheme.slateMuted,
            ),
          ),
        ),
        TextFormField(
          key: ValueKey(key),
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: _amountFormatters,
          validator: (_) => error(),
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppTheme.slateDark,
          ),
          decoration: InputDecoration(
            hintText: hint,
            prefixText: '₱ ',
            filled: true,
            fillColor: const Color(0xFFF1F5FB),
            errorMaxLines: 3,
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
    );
  }

  _StepView _budget() => _StepView(
    id: 'budget',
    title: 'What’s your usual budget?',
    body:
        'Your typical spend per trip in pesos. Leave both empty if you’d '
        'rather not say.',
    content: [
      Form(
        key: _budgetForm,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _amount(
                key: 'onboarding-budget-min',
                label: 'Min',
                hint: '500',
                controller: _minController,
                error: () => validateBudgetRange(
                  _minController.text,
                  _maxController.text,
                ).minError,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _amount(
                key: 'onboarding-budget-max',
                label: 'Max',
                hint: '2,000',
                controller: _maxController,
                error: () => validateBudgetRange(
                  _minController.text,
                  _maxController.text,
                ).maxError,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 4),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          key: const ValueKey('onboarding-skip-budget'),
          onPressed: _skipBudget,
          style: TextButton.styleFrom(
            foregroundColor: AppTheme.primaryBlue,
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
          child: const Text('Skip, no budget preference'),
        ),
      ),
    ],
    footer: _NavRow(onBack: _back, onNext: _next),
  );

  _StepView _style() => _StepView(
    id: 'style',
    title: 'How do you like to travel?',
    body: 'Optional. Tap again to clear.',
    content: [
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
    footer: _NavRow(onBack: _back, onNext: _next),
  );

  _StepView _review() {
    final tagLabels = [
      for (final option in kPreferredTags)
        if (_prefs.preferredTags.contains(option.value)) option.label,
    ];
    return _StepView(
      id: 'review',
      title: 'Look good?',
      body: 'Check your answers before saving.',
      content: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F8FC),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              _ReviewRow(
                editKey: 'review-edit-interests',
                label: 'Interests',
                value: tagLabels.join(', '),
                onEdit: _saving ? null : () => _edit(OnboardingStep.interests),
              ),
              const Divider(height: 1, color: Color(0xFFE3E9F2)),
              _ReviewRow(
                editKey: 'review-edit-budget',
                label: 'Budget',
                value: _prefs.hasBudget
                    ? '₱${_peso(_prefs.budgetMin!)} – ₱${_peso(_prefs.budgetMax!)}'
                    : 'No preference',
                onEdit: _saving ? null : () => _edit(OnboardingStep.budget),
              ),
              const Divider(height: 1, color: Color(0xFFE3E9F2)),
              _ReviewRow(
                editKey: 'review-edit-style',
                label: 'Travel style',
                value: _styles[_prefs.travelStyle]?.label ?? 'No preference',
                onEdit: _saving ? null : () => _edit(OnboardingStep.style),
              ),
            ],
          ),
        ),
        if (_saveError != null) ...[
          const SizedBox(height: 14),
          StatusBanner(
            key: const ValueKey('onboarding-save-error'),
            tone: StatusTone.error,
            message: _saveError!,
          ),
        ],
      ],
      footer: _NavRow(
        onBack: _saving ? null : _back,
        onNext: _saving ? null : _save,
        nextKey: 'onboarding-save',
        nextLabel: _saveError != null ? 'Try again' : 'Save preferences',
        busy: _saving,
      ),
    );
  }

  _StepView _done() => _StepView(
    id: 'done',
    title: 'You’re all set!',
    body:
        'Your preferences are saved. We’ll use them to suggest places '
        'you’ll like.',
    footer: _PrimaryButton(
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
  );
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

const _orange = Color(0xFFF2620F);

/// Opens [flow] as a pop-up over the app, which blurs behind it like the
/// swipe menu and Spots cards. [home v3]
Future<T?> showPreferencesPopup<T>(BuildContext context, Widget flow) {
  final reduce = MediaQuery.disableAnimationsOf(context);
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.transparent,
    transitionDuration: Duration(milliseconds: reduce ? 150 : 380),
    pageBuilder: (context, animation, _) {
      final fade = CurvedAnimation(parent: animation, curve: Curves.easeOut);
      final rise = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return Stack(
        children: [
          Positioned.fill(
            child: FadeTransition(
              opacity: fade,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                child: const ColoredBox(color: Color(0x590A1830)),
              ),
            ),
          ),
          FadeTransition(
            opacity: fade,
            child: AnimatedBuilder(
              animation: rise,
              builder: (context, child) => reduce
                  ? child!
                  : Transform.translate(
                      offset: Offset(0, 28 * (1 - rise.value)),
                      child: Transform.scale(
                        scale: 0.94 + 0.06 * rise.value,
                        child: child,
                      ),
                    ),
              child: flow,
            ),
          ),
        ],
      );
    },
  );
}

/// One step's words, controls and buttons.
class _StepView {
  final String id;
  final String title;
  final String body;
  final List<Widget> content;
  final Widget? footer;

  const _StepView({
    required this.id,
    required this.title,
    required this.body,
    this.content = const [],
    this.footer,
  });
}

/// The white card: a sky header, the step (cross-fading between steps,
/// scrolling if tall), and its buttons.
class _Sheet extends StatelessWidget {
  final Widget header;
  final _StepView view;

  const _Sheet({required this.header, required this.view});

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    final duration = Duration(milliseconds: reduce ? 0 : 260);
    return Container(
      key: const ValueKey('onboarding-card'),
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
          AnimatedSize(
            duration: duration,
            curve: Curves.easeInOutCubic,
            child: header,
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 8),
              child: AnimatedSize(
                duration: duration,
                curve: Curves.easeInOutCubic,
                alignment: Alignment.topCenter,
                child: AnimatedSwitcher(
                  duration: duration,
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  layoutBuilder: (current, previous) => Stack(
                    alignment: Alignment.topCenter,
                    children: [...previous, ?current],
                  ),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween(
                        begin: const Offset(0.04, 0),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: KeyedSubtree(
                    key: ValueKey(view.id),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          view.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 26,
                            height: 1.08,
                            letterSpacing: -0.6,
                            color: AppTheme.slateDark,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          view.body,
                          style: const TextStyle(
                            fontSize: 14.5,
                            height: 1.4,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.slateMuted,
                          ),
                        ),
                        if (view.content.isNotEmpty) const SizedBox(height: 18),
                        ...view.content,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (view.footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 18),
              child: view.footer,
            ),
        ],
      ),
    );
  }
}

/// The app's sky with the sun, two Bacolod elements and the Lagaw logo:
/// the welcome and done steps. Still, so it never competes with the text.
class _ArtHeader extends StatelessWidget {
  final bool done;
  final VoidCallback? onClose;

  const _ArtHeader({required this.done, required this.onClose});

  @override
  Widget build(BuildContext context) {
    Widget element(String asset, double width) =>
        Image.asset('assets/elements/$asset.webp', width: width);
    return SizedBox(
      height: 168,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [AppTheme.skyTop, AppTheme.skyMid],
                ),
              ),
            ),
          ),
          Positioned(
            left: -60,
            top: -70,
            child: Container(
              width: 190,
              height: 190,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Color(0xFFFFE27A), Color(0x00FFC83D)],
                ),
              ),
            ),
          ),
          Positioned(
            left: -26,
            bottom: -14,
            child: Transform.rotate(
              angle: done ? 0.3 : -0.28,
              child: element(done ? 'piaya' : 'masskara', 112),
            ),
          ),
          Positioned(
            right: -30,
            bottom: -18,
            child: Transform.rotate(
              angle: done ? -0.1 : -0.32,
              child: Transform.flip(
                flipX: done,
                child: element(done ? 'carabao' : 'inasal', 128),
              ),
            ),
          ),
          Center(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x550A2A6B),
                        blurRadius: 24,
                        offset: Offset(0, 12),
                        spreadRadius: -8,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Image.asset(
                      'assets/brand/logo.png',
                      key: const ValueKey('onboarding-logo'),
                      width: 84,
                      height: 84,
                    ),
                  ),
                ),
                if (done)
                  Positioned(
                    right: -8,
                    bottom: -8,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF16A34A),
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        size: 18,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (onClose != null)
            Positioned(
              top: 12,
              right: 12,
              child: Semantics(
                button: true,
                label: 'Close',
                child: GestureDetector(
                  key: const ValueKey('onboarding-close'),
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
            ),
        ],
      ),
    );
  }
}

/// A slim strip of sky with the step count and four segments.
class _StepHeader extends StatelessWidget {
  final int index;
  final int total;

  const _StepHeader({required this.index, required this.total});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.skyTop, AppTheme.skyMid],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'TRAVEL PREFERENCES',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
              color: Color(0xD9FFFFFF),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Step ${index + 1} of $total',
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            key: const ValueKey('onboarding-progress'),
            children: [
              for (var i = 0; i < total; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 260),
                    height: 6,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(3),
                      color: i <= index
                          ? Colors.white
                          : const Color(0x59FFFFFF),
                    ),
                  ),
                ),
              ],
            ],
          ),
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
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFFEEF4FC),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 18, color: AppTheme.primaryBlue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 14.5,
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

/// An interest: a soft pill that turns orange when picked.
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
    final fg = selected ? Colors.white : AppTheme.slateDark;
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
                  color: fg,
                ),
              ),
            ],
          ),
        ),
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
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFFFF3EA) : const Color(0xFFF5F8FC),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? _orange : Colors.transparent,
              width: 1.6,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? _orange : Colors.white,
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: selected ? Colors.white : AppTheme.primaryBlue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15.5,
                        color: AppTheme.slateDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      blurb,
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                        color: AppTheme.slateMuted,
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 180),
                opacity: selected ? 1 : 0,
                child: const Icon(Icons.check_circle_rounded, color: _orange),
              ),
            ],
          ),
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
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                    color: AppTheme.slateMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
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
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.primaryBlue,
              textStyle: const TextStyle(fontWeight: FontWeight.w700),
            ),
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
        OutlinedButton(
          key: const ValueKey('onboarding-back'),
          onPressed: onBack,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.slateDark,
            shape: const StadiumBorder(),
            minimumSize: const Size(96, 50),
            side: const BorderSide(color: Color(0xFFD5DEEA)),
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          child: const Text('Back'),
        ),
        const SizedBox(width: 10),
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
    return FilledButton(
      onPressed: busy ? null : onTap,
      style: FilledButton.styleFrom(
        backgroundColor: _orange,
        foregroundColor: Colors.white,
        disabledBackgroundColor: const Color(0xFFF7A26F),
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
          Flexible(
            child: Text(
              busy ? 'Saving…' : label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
