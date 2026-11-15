import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme.dart';
import 'auth_session.dart';
import 'sign_in_screen.dart';

const _orange = Color(0xFFF2620F);

/// Remembers that the intro was seen, so later sign-outs open straight on
/// the welcome page.
const introSeenKey = 'lagaw.intro.seen';

/// Signed-out entry: four swipeable intro pages (Swipe your vibe first),
/// ending on a welcome page with Create account and Log in, which open the
/// email sign-in screen. [home v3]
class WelcomeFlow extends StatefulWidget {
  final AuthSession session;

  const WelcomeFlow({super.key, required this.session});

  @override
  State<WelcomeFlow> createState() => _WelcomeFlowState();
}

class _WelcomeFlowState extends State<WelcomeFlow> {
  /// null: the intro; true: create account; false: log in.
  bool? _signUp;
  int? _startPage;

  @override
  void initState() {
    super.initState();
    _loadSeen();
  }

  Future<void> _loadSeen() async {
    var seen = false;
    try {
      seen =
          (await SharedPreferences.getInstance()).getBool(introSeenKey) ??
          false;
    } on Object {
      // Not knowing just shows the intro again.
    }
    if (mounted) setState(() => _startPage = seen ? _pages.length - 1 : 0);
  }

  Future<void> _markSeen() async {
    try {
      await (await SharedPreferences.getInstance()).setBool(introSeenKey, true);
    } on Object {
      // Best effort.
    }
  }

  void _open(bool signUp) {
    _markSeen();
    setState(() => _signUp = signUp);
  }

  @override
  Widget build(BuildContext context) {
    final start = _startPage;
    return PopScope(
      canPop: _signUp == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _signUp = null);
      },
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 320),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, 0.04),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        ),
        child: _signUp != null
            ? SignInScreen(
                key: ValueKey('auth-${_signUp! ? 'up' : 'in'}'),
                session: widget.session,
                initialSignUp: _signUp!,
                onBack: () => setState(() => _signUp = null),
              )
            : start == null
            ? const _Sky(key: ValueKey('intro-loading'), child: SizedBox())
            : _Intro(
                key: const ValueKey('intro'),
                initialPage: start,
                onSeen: _markSeen,
                onCreateAccount: () => _open(true),
                onLogIn: () => _open(false),
              ),
      ),
    );
  }
}

/// One intro page: its picture, title and words.
class _Page {
  final String title;
  final String body;
  final Widget Function(Animation<double> loop) art;

  const _Page({required this.title, required this.body, required this.art});
}

final _pages = <_Page>[
  _Page(
    title: 'Swipe your vibe',
    body:
        'Swipe right on Bacolod spots you like and left to pass. Lagaw '
        'learns your taste with every swipe.',
    art: (loop) => _SwipeDemo(loop: loop),
  ),
  _Page(
    title: 'Find spots around Bacolod',
    body:
        'Cafés, heritage, parks and food in one place, each with real '
        'photos, prices and visit times.',
    art: (loop) => _FloatingChips(loop: loop),
  ),
  _Page(
    title: 'Plan a trip in seconds',
    body:
        'Tell Lagaw your dates and budget, and it fills in the stops for '
        'each day of your trip.',
    art: (loop) => _PlanDemo(loop: loop),
  ),
  _Page(
    title: 'Welcome to Lagaw',
    body: 'Maayong pag-abot! Create an account or log in to start.',
    art: (loop) => _WelcomeArt(loop: loop),
  ),
];

class _Intro extends StatefulWidget {
  final int initialPage;
  final VoidCallback onSeen;
  final VoidCallback onCreateAccount;
  final VoidCallback onLogIn;

  const _Intro({
    super.key,
    required this.initialPage,
    required this.onSeen,
    required this.onCreateAccount,
    required this.onLogIn,
  });

  @override
  State<_Intro> createState() => _IntroState();
}

class _IntroState extends State<_Intro> with SingleTickerProviderStateMixin {
  late final PageController _controller = PageController(
    initialPage: widget.initialPage,
  );
  late int _page = widget.initialPage;

  /// Drives every page's little looping demo.
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _loop
        ..stop()
        ..value = 0.3;
    } else if (!_loop.isAnimating) {
      _loop.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _loop.dispose();
    super.dispose();
  }

  bool get _last => _page == _pages.length - 1;

  void _go(int page) => _controller.animateToPage(
    page,
    duration: const Duration(milliseconds: 420),
    curve: Curves.easeInOutCubic,
  );

  @override
  Widget build(BuildContext context) {
    final page = _pages[_page];
    return _Sky(
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              children: [
                SizedBox(
                  height: 48,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: _last ? 0 : 1,
                      child: TextButton(
                        key: const ValueKey('intro-skip'),
                        onPressed: _last ? null : () => _go(_pages.length - 1),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          textStyle: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        child: const Text('Skip'),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    key: const ValueKey('intro-pages'),
                    controller: _controller,
                    itemCount: _pages.length,
                    onPageChanged: (i) {
                      setState(() => _page = i);
                      if (i == _pages.length - 1) widget.onSeen();
                    },
                    itemBuilder: (context, i) => Padding(
                      key: ValueKey('intro-page-$i'),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Center(child: _pages[i].art(_loop)),
                    ),
                  ),
                ),
                // The white panel, like the other v3 cards: words, dots and
                // the next step.
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(24, 26, 24, 18),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(32),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x330F285A),
                        blurRadius: 30,
                        offset: Offset(0, -6),
                        spreadRadius: -12,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 260),
                        child: Column(
                          key: ValueKey(_page),
                          children: [
                            Text(
                              page.title,
                              key: const ValueKey('intro-title'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 28,
                                height: 1.08,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.6,
                                color: AppTheme.slateDark,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              page.body,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 14.5,
                                height: 1.45,
                                fontWeight: FontWeight.w500,
                                color: AppTheme.slateMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      _Dots(count: _pages.length, index: _page),
                      const SizedBox(height: 18),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeInOutCubic,
                        child: _last
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _Pill(
                                    key: const ValueKey('intro-create-account'),
                                    label: 'Create account',
                                    filled: true,
                                    onTap: widget.onCreateAccount,
                                  ),
                                  const SizedBox(height: 10),
                                  _Pill(
                                    key: const ValueKey('intro-log-in'),
                                    label: 'Log in',
                                    filled: false,
                                    onTap: widget.onLogIn,
                                  ),
                                ],
                              )
                            : _Pill(
                                key: const ValueKey('intro-next'),
                                label: 'Next',
                                filled: true,
                                onTap: () => _go(_page + 1),
                              ),
                      ),
                    ],
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

/// The app's sky with its sun, as on every v3 page.
class _Sky extends StatelessWidget {
  final Widget child;

  const _Sky({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppTheme.skyTop, AppTheme.skyMid, AppTheme.skyBottom],
            stops: [0, 0.55, 1],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -90,
              left: -90,
              child: IgnorePointer(
                child: Container(
                  width: 260,
                  height: 260,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        Color(0xFFFFFBEB),
                        Color(0xFFFEF08A),
                        Color(0xFFF59E0B),
                        Color(0x00F59E0B),
                      ],
                      stops: [0, 0.35, 0.7, 1],
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fill(child: child),
          ],
        ),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  final int count;
  final int index;

  const _Dots({required this.count, required this.index});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Page ${index + 1} of $count',
      child: Row(
        key: const ValueKey('intro-dots'),
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == index ? 24 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: i == index ? _orange : const Color(0xFFD5DEEA),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final bool filled;
  final VoidCallback onTap;

  const _Pill({
    super.key,
    required this.label,
    required this.filled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const shape = StadiumBorder();
    const size = Size.fromHeight(52);
    const text = TextStyle(fontSize: 16, fontWeight: FontWeight.w800);
    return filled
        ? FilledButton(
            onPressed: onTap,
            style: FilledButton.styleFrom(
              backgroundColor: _orange,
              foregroundColor: Colors.white,
              shape: shape,
              minimumSize: size,
              textStyle: text,
            ),
            child: Text(label),
          )
        : OutlinedButton(
            onPressed: onTap,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.slateDark,
              side: const BorderSide(color: Color(0xFFD5DEEA), width: 1.5),
              shape: shape,
              minimumSize: size,
              textStyle: text,
            ),
            child: Text(label),
          );
  }
}

Widget _element(String asset, double width) =>
    Image.asset('assets/elements/$asset.webp', width: width);

double _bob(double t, double phase) => math.sin((t + phase) * 2 * math.pi) * 5;

/// Page 1: a little deck that likes a card, then the next one, on a loop.
class _SwipeDemo extends StatelessWidget {
  final Animation<double> loop;

  const _SwipeDemo({required this.loop});

  static const _cards = [
    ('San Sebastian Cathedral', 'heritage', Icons.account_balance_rounded),
    ('Calea Pastries & Coffee', 'cafe', Icons.local_cafe_rounded),
    ('Capitol Park and Lagoon', 'park', Icons.park_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: loop,
      builder: (context, _) {
        final t = loop.value;
        // 0–0.45 rest, 0.45–0.8 the top card flies right, 0.8–1 the next
        // one settles in.
        final fly = Curves.easeIn.transform(
          ((t - 0.45) / 0.35).clamp(0.0, 1.0),
        );
        final settle = Curves.easeOutCubic.transform(
          ((t - 0.8) / 0.2).clamp(0.0, 1.0),
        );
        return SizedBox(
          width: 250,
          height: 320,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Positioned(
                left: -70,
                top: 10,
                child: Transform.translate(
                  offset: Offset(0, _bob(t, 0)),
                  child: Transform.rotate(
                    angle: -0.3,
                    child: _element('masskara', 96),
                  ),
                ),
              ),
              Positioned(
                right: -66,
                bottom: 20,
                child: Transform.translate(
                  offset: Offset(0, _bob(t, 0.5)),
                  child: Transform.rotate(
                    angle: -0.35,
                    child: _element('inasal', 100),
                  ),
                ),
              ),
              _card(2, tilt: 8, lift: 26, scale: 0.88 + 0.03 * settle),
              _card(
                1,
                tilt: -5 + 5 * settle,
                lift: 13 - 13 * settle,
                scale: 0.94 + 0.06 * settle,
              ),
              if (fly < 1)
                Transform.translate(
                  offset: Offset(260 * fly, 30 * fly),
                  child: Transform.rotate(
                    angle: 0.35 * fly,
                    child: _card(0, stamp: ((t - 0.3) / 0.15).clamp(0.0, 1.0)),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _card(
    int i, {
    double tilt = 0,
    double lift = 0,
    double scale = 1,
    double stamp = 0,
  }) {
    final (name, category, icon) = _cards[i];
    final colors = _gradient(category);
    return Transform.translate(
      offset: Offset(0, -lift),
      child: Transform.rotate(
        angle: tilt * math.pi / 180,
        child: Transform.scale(
          scale: scale,
          child: Container(
            width: 220,
            height: 290,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: colors,
              ),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: const Color(0xCCFFFFFF), width: 3),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x4D0F285A),
                  blurRadius: 30,
                  offset: Offset(0, 16),
                  spreadRadius: -12,
                ),
              ],
            ),
            child: Stack(
              children: [
                Center(
                  child: Icon(icon, size: 54, color: const Color(0x66FFFFFF)),
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                    decoration: BoxDecoration(
                      color: const Color(0x38FFFFFF),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0x40FFFFFF)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 2,
                          style: const TextStyle(
                            fontSize: 16,
                            height: 1.1,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Container(
                              width: 34,
                              height: 30,
                              decoration: BoxDecoration(
                                color: const Color(0x33FFFFFF),
                                borderRadius: BorderRadius.circular(11),
                              ),
                              child: const Icon(
                                Icons.close_rounded,
                                size: 17,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Container(
                                height: 30,
                                decoration: BoxDecoration(
                                  color: _orange,
                                  borderRadius: BorderRadius.circular(11),
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.favorite_rounded,
                                      size: 15,
                                      color: Colors.white,
                                    ),
                                    SizedBox(width: 4),
                                    Text(
                                      'Like',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (stamp > 0)
                  Positioned(
                    top: 26,
                    left: 18,
                    child: Opacity(
                      opacity: stamp,
                      child: Transform.rotate(
                        angle: -0.24,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _orange, width: 2.5),
                          ),
                          child: const Text(
                            'LIKE',
                            style: TextStyle(
                              fontSize: 16,
                              letterSpacing: 1.4,
                              fontWeight: FontWeight.w900,
                              color: _orange,
                            ),
                          ),
                        ),
                      ),
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

List<Color> _gradient(String category) => switch (category) {
  'cafe' => const [Color(0xFF78350F), Color(0xFFB45309)],
  'heritage' => const [Color(0xFF881337), Color(0xFFBE123C)],
  'park' => const [Color(0xFF14532D), Color(0xFF15803D)],
  _ => const [Color(0xFF1E293B), Color(0xFF334155)],
};

/// Page 2: category pills floating around, like a mood board of Bacolod.
class _FloatingChips extends StatelessWidget {
  final Animation<double> loop;

  const _FloatingChips({required this.loop});

  // Staggered left/right rows so no two pills overlap.
  static const _chips = [
    (Icons.local_cafe_rounded, 'Cafés', -0.55, -0.9, -6.0),
    (Icons.account_balance_rounded, 'Heritage', 0.5, -0.68, 5.0),
    (Icons.park_rounded, 'Parks', -0.6, -0.4, 4.0),
    (Icons.restaurant_rounded, 'Food', 0.5, -0.14, -5.0),
    (Icons.palette_rounded, 'Art', -0.62, 0.12, -3.0),
    (Icons.location_city_rounded, 'Landmarks', 0.5, 0.4, 6.0),
    (Icons.cake_rounded, 'Sweets', -0.5, 0.68, 4.0),
  ];

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: loop,
      builder: (context, _) {
        final t = loop.value;
        return SizedBox(
          width: 320,
          height: 340,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Align(
                alignment: const Alignment(1.0, 1.05),
                child: Transform.translate(
                  offset: Offset(0, _bob(t, 0.3)),
                  child: Transform.rotate(
                    angle: 0.3,
                    child: _element('piaya', 78),
                  ),
                ),
              ),
              Align(
                alignment: const Alignment(1.08, -0.98),
                child: Transform.translate(
                  offset: Offset(0, _bob(t, 0.8)),
                  child: Transform.flip(
                    flipX: true,
                    child: _element('carabao', 70),
                  ),
                ),
              ),
              for (final (i, (icon, label, x, y, tilt)) in _chips.indexed)
                Align(
                  alignment: Alignment(x, y),
                  child: Transform.translate(
                    offset: Offset(0, _bob(t, i * 0.17)),
                    child: Transform.rotate(
                      angle: tilt * math.pi / 180,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 11,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xF5FFFFFF),
                          borderRadius: BorderRadius.circular(999),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x330F1B2D),
                              blurRadius: 20,
                              offset: Offset(0, 8),
                              spreadRadius: -8,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(icon, size: 19, color: _orange),
                            const SizedBox(width: 7),
                            Text(
                              label,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.slateDark,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Page 3: a day plan card whose stops tick in one by one.
class _PlanDemo extends StatelessWidget {
  final Animation<double> loop;

  const _PlanDemo({required this.loop});

  static const _stops = [
    ('9:00', 'Calea Pastries & Coffee', Icons.local_cafe_rounded),
    ('10:30', 'The Ruins', Icons.account_balance_rounded),
    ('1:00', 'Capitol Park and Lagoon', Icons.park_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: loop,
      builder: (context, _) {
        final t = loop.value;
        return SizedBox(
          width: 290,
          height: 320,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Positioned(
                right: -50,
                top: -6,
                child: Transform.translate(
                  offset: Offset(0, _bob(t, 0.2)),
                  child: Transform.rotate(
                    angle: 0.25,
                    child: _element('masskara', 84),
                  ),
                ),
              ),
              Positioned(
                left: -46,
                bottom: -4,
                child: Transform.translate(
                  offset: Offset(0, _bob(t, 0.7)),
                  child: _element('piaya', 76),
                ),
              ),
              Container(
                width: 270,
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x4D0F285A),
                      blurRadius: 30,
                      offset: Offset(0, 16),
                      spreadRadius: -12,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF3EA),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.auto_awesome_rounded,
                                size: 13,
                                color: _orange,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Planned for you',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFFC2410C),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Day 1 · Saturday',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.slateDark,
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (final (i, (time, name, icon)) in _stops.indexed)
                      _stop(
                        time,
                        name,
                        icon,
                        shown: ((t * 1.6 - i * 0.3) / 0.25).clamp(0.0, 1.0),
                        last: i == _stops.length - 1,
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _stop(
    String time,
    String name,
    IconData icon, {
    required double shown,
    required bool last,
  }) {
    return Opacity(
      opacity: 0.25 + 0.75 * shown,
      child: Transform.translate(
        offset: Offset(10 * (1 - shown), 0),
        child: Padding(
          padding: EdgeInsets.only(bottom: last ? 0 : 10),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppTheme.skyTop, AppTheme.skyMid],
                  ),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, size: 19, color: Colors.white),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      time,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.slateMuted,
                      ),
                    ),
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.slateDark,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.check_circle_rounded,
                size: 18,
                color: Color.lerp(
                  const Color(0xFFD5DEEA),
                  const Color(0xFF16A34A),
                  shown,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Page 4: the Lagaw logo with the four elements around it.
class _WelcomeArt extends StatelessWidget {
  final Animation<double> loop;

  const _WelcomeArt({required this.loop});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: loop,
      builder: (context, _) {
        final t = loop.value;
        Widget at(Alignment a, double phase, Widget child) => Align(
          alignment: a,
          child: Transform.translate(
            offset: Offset(0, _bob(t, phase)),
            child: child,
          ),
        );
        return SizedBox(
          width: 300,
          height: 300,
          child: Stack(
            children: [
              at(
                const Alignment(-1, -0.85),
                0,
                Transform.rotate(angle: -0.25, child: _element('masskara', 96)),
              ),
              at(
                const Alignment(1, -0.75),
                0.3,
                Transform.rotate(angle: -0.4, child: _element('inasal', 104)),
              ),
              at(
                const Alignment(-0.95, 0.9),
                0.6,
                Transform.rotate(angle: 0.3, child: _element('piaya', 84)),
              ),
              at(
                const Alignment(1, 0.85),
                0.15,
                Transform.flip(flipX: true, child: _element('carabao', 100)),
              ),
              Center(
                child: Container(
                  key: const ValueKey('intro-logo'),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(34),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x550A2A6B),
                        blurRadius: 34,
                        offset: Offset(0, 18),
                        spreadRadius: -10,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(34),
                    child: Image.asset(
                      'assets/brand/logo.png',
                      width: 124,
                      height: 124,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
