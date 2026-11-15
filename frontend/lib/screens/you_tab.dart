import 'package:flutter/material.dart';

import '../auth/auth_session.dart';
import '../models/location.dart';
import '../models/onboarding_preferences.dart';
import '../services/onboarding_repository.dart';
import '../theme.dart';
import '../widgets/trip_form/trip_form.dart' show kPreferredTags;
import 'onboarding/first_run_gate.dart';
import 'spots/spots_view.dart';

/// "Roel.jr@x.com" → "Roel": a friendly name until profiles have one.
String displayNameFrom(String? email) {
  if (email == null || email.isEmpty) return 'Guest';
  final local = email.split('@').first;
  final word = local
      .split(RegExp(r'[._+\-0-9]+'))
      .firstWhere((w) => w.isNotEmpty, orElse: () => local);
  return '${word[0].toUpperCase()}${word.substring(1)}';
}

const _paceLabels = {'slow': 'Slow', 'moderate': 'Moderate', 'fast': 'Fast'};
const _orange = Color(0xFFF2620F);

/// "You": a profile hero (avatar with an edit pencil, name, counts and
/// interests) over the sky, the travel preferences in full, and the first
/// liked and saved places as Spots cards with See all. [home v3]
class YouTab extends StatefulWidget {
  final AuthSession? session;
  final int likedCount;
  final VoidCallback onOpenSaved;

  /// Liked and saved places; the first two show here.
  final List<LocationItem> picks;

  /// Lets the pick cards save, rate and pop up like on Spots.
  final PlaceActions? actions;

  /// Where preferences load from; null hides the preferences card.
  final OnboardingRepository Function()? preferences;

  /// Opens Spots when nothing is liked yet.
  final VoidCallback? onExplore;

  const YouTab({
    super.key,
    required this.session,
    required this.likedCount,
    required this.onOpenSaved,
    this.picks = const [],
    this.actions,
    this.preferences,
    this.onExplore,
  });

  @override
  State<YouTab> createState() => _YouTabState();
}

class _YouTabState extends State<YouTab> {
  OnboardingPreferences? _prefs;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = widget.preferences?.call();
    if (repo == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final prefs = await repo.load();
      if (!mounted) return;
      setState(() {
        _prefs = prefs;
        _loading = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Couldn’t load your preferences.';
      });
    }
  }

  Future<void> _openPreferences() async {
    await openTravelPreferences(context);
    if (mounted) _load();
  }

  void _editPhoto() {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          key: ValueKey('you-photo-soon'),
          behavior: SnackBarBehavior.floating,
          // Above the floating nav bar.
          margin: EdgeInsets.fromLTRB(16, 0, 16, 104),
          content: Text('Changing your photo is coming soon.'),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final email = widget.session?.accountEmail;
    final tags = [
      for (final o in kPreferredTags)
        if (_prefs?.preferredTags.contains(o.value) ?? false) o,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 6),
        Center(child: _avatar(email)),
        const SizedBox(height: 14),
        // Long names shrink to one line instead of running into the art.
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            displayNameFrom(email),
            key: const ValueKey('you-name'),
            maxLines: 1,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 34,
              height: 1.05,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
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
        ),
        const SizedBox(height: 4),
        Text(
          email ?? 'Not signed in',
          key: const ValueKey('you-email'),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xEBFFFFFF),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          widget.likedCount == 1
              ? '1 place liked and saved'
              : '${widget.likedCount} places liked and saved',
          key: const ValueKey('you-liked-count'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Color(0xD9FFFFFF),
          ),
        ),
        if (tags.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final t in tags) _tagChip(t.icon, t.label, onSky: true),
            ],
          ),
        ],
        if (widget.preferences != null) ...[
          const SizedBox(height: 22),
          _preferencesCard(),
        ],
        const SizedBox(height: 26),
        _picksHeader(),
        const SizedBox(height: 12),
        _picks(),
        if (widget.session != null) ...[
          const SizedBox(height: 26),
          Center(
            child: TextButton.icon(
              key: const ValueKey('you-sign-out'),
              onPressed: () => widget.session!.signOut(),
              style: TextButton.styleFrom(
                backgroundColor: const Color(0x33FFFFFF),
                foregroundColor: Colors.white,
                shape: const StadiumBorder(),
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 18),
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: const Text('Sign out'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _avatar(String? email) {
    return SizedBox(
      width: 132,
      height: 132,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 132,
            height: 132,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 5),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFF9A3D), _orange],
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x550A2A6B),
                  blurRadius: 30,
                  offset: Offset(0, 16),
                  spreadRadius: -10,
                ),
              ],
            ),
            child: Text(
              email == null || email.isEmpty ? '?' : email[0].toUpperCase(),
              style: const TextStyle(
                fontSize: 52,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
          Positioned(
            right: 2,
            bottom: 4,
            child: Semantics(
              button: true,
              label: 'Change photo',
              child: GestureDetector(
                key: const ValueKey('you-edit-photo'),
                onTap: _editPhoto,
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    border: Border.all(
                      color: const Color(0xFFEEF4FC),
                      width: 2,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x330F1B2D),
                        blurRadius: 12,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.edit_rounded,
                    size: 18,
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

  Widget _tagChip(IconData icon, String label, {bool onSky = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: onSky ? const Color(0xF5FFFFFF) : const Color(0xFFF1F5FB),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: _orange),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppTheme.slateDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        boxShadow: const [
          BoxShadow(
            color: Color(0x4D0F285A),
            blurRadius: 30,
            offset: Offset(0, 16),
            spreadRadius: -16,
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _preferencesCard() {
    final prefs = _prefs;
    final Widget body;
    if (_loading && prefs == null) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Center(child: CircularProgressIndicator(color: _orange)),
      );
    } else if (_error != null) {
      body = Row(
        children: [
          Expanded(
            child: Text(
              _error!,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: AppTheme.slateMuted,
              ),
            ),
          ),
          TextButton(
            key: const ValueKey('you-preferences-retry'),
            onPressed: _load,
            child: const Text('Retry'),
          ),
        ],
      );
    } else if (prefs == null || prefs.isUnset) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Answer three quick questions so we can suggest places in '
            'Bacolod that fit you.',
            style: TextStyle(
              fontSize: 14,
              height: 1.4,
              fontWeight: FontWeight.w500,
              color: AppTheme.slateMuted,
            ),
          ),
          const SizedBox(height: 14),
          FilledButton(
            key: const ValueKey('you-take-preferences'),
            onPressed: _openPreferences,
            style: FilledButton.styleFrom(
              backgroundColor: _orange,
              shape: const StadiumBorder(),
              minimumSize: const Size.fromHeight(48),
              textStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            child: const Text('Take travel preferences'),
          ),
        ],
      );
    } else {
      final tags = [
        for (final o in kPreferredTags)
          if (prefs.preferredTags.contains(o.value)) o,
      ];
      body = Column(
        key: const ValueKey('you-preferences-summary'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label('Interests'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final t in tags) _tagChip(t.icon, t.label)],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _fact(
                  Icons.payments_outlined,
                  'Budget',
                  prefs.hasBudget
                      ? '₱${_peso(prefs.budgetMin!)} – ₱${_peso(prefs.budgetMax!)}'
                      : 'No preference',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _fact(
                  Icons.speed_rounded,
                  'Pace',
                  _paceLabels[prefs.travelStyle] ?? 'No preference',
                ),
              ),
            ],
          ),
        ],
      );
    }
    final set = prefs != null && !prefs.isUnset;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Travel preferences',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                    color: AppTheme.slateDark,
                  ),
                ),
              ),
              if (set)
                TextButton.icon(
                  key: const ValueKey('you-preferences'),
                  onPressed: _openPreferences,
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.primaryBlue,
                    textStyle: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  icon: const Icon(Icons.edit_rounded, size: 16),
                  label: const Text('Edit'),
                ),
            ],
          ),
          const SizedBox(height: 10),
          body,
        ],
      ),
    );
  }

  Widget _label(String text) => Text(
    text,
    style: const TextStyle(
      fontSize: 12.5,
      fontWeight: FontWeight.w600,
      color: AppTheme.slateMuted,
    ),
  );

  Widget _fact(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F8FC),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppTheme.primaryBlue),
          const SizedBox(height: 6),
          _label(label),
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppTheme.slateDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _picksHeader() {
    return Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Liked and saved',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                  color: Colors.white,
                ),
              ),
              Text(
                'Places you picked around Bacolod',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xE6FFFFFF),
                ),
              ),
            ],
          ),
        ),
        if (widget.likedCount > 0)
          TextButton(
            key: const ValueKey('you-saved'),
            onPressed: widget.onOpenSaved,
            style: TextButton.styleFrom(
              backgroundColor: const Color(0xF5FFFFFF),
              foregroundColor: AppTheme.slateDark,
              shape: const StadiumBorder(),
              minimumSize: const Size(0, 38),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              textStyle: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            child: Text('See all ${widget.likedCount}'),
          ),
      ],
    );
  }

  Widget _picks() {
    final actions = widget.actions;
    final shown = widget.picks.take(2).toList();
    if (shown.isEmpty || actions == null) {
      if (widget.likedCount > 0) return const SizedBox.shrink();
      return _card(
        child: Column(
          children: [
            const Text(
              'Nothing liked yet. Heart a spot or swipe right on one and it '
              'shows up here.',
              key: ValueKey('you-picks-empty'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                fontWeight: FontWeight.w500,
                color: AppTheme.slateMuted,
              ),
            ),
            if (widget.onExplore != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                key: const ValueKey('you-explore'),
                onPressed: widget.onExplore,
                style: OutlinedButton.styleFrom(
                  shape: const StadiumBorder(),
                  minimumSize: const Size(0, 44),
                ),
                child: const Text('Explore spots'),
              ),
            ],
          ],
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, box) {
        final half = (box.maxWidth - 12) / 2;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (i, place) in shown.indexed) ...[
              if (i > 0) const SizedBox(width: 12),
              PlacePickCard(
                key: ValueKey('you-pick-${place.id}'),
                place: place,
                width: half,
                actions: actions,
              ),
            ],
          ],
        );
      },
    );
  }
}

String _peso(String amount) {
  final parts = amount.split('.');
  final whole = parts[0].replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  final cents = parts.length > 1 ? parts[1] : '00';
  return cents == '00' ? whole : '$whole.$cents';
}
