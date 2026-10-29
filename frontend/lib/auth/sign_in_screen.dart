import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/bacolod_3d_badges.dart';
import '../widgets/tactile_motion.dart';
import '../widgets/status_banner.dart';
import 'auth_client.dart';
import 'auth_session.dart';

enum _Mode { signIn, signUp }

final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// Email/password sign-in and sign-up through Supabase Auth. [S3-16]
///
/// With [reauthenticate], it is pushed over the current screen after a
/// session expired, and pops on success so unsaved forms underneath stay.
class SignInScreen extends StatefulWidget {
  final AuthSession session;
  final bool reauthenticate;

  const SignInScreen({
    super.key,
    required this.session,
    this.reauthenticate = false,
  });

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  // Replaced on mode switch so old validation messages don't carry over.
  var _formKey = GlobalKey<FormState>();
  late final TextEditingController _email = TextEditingController(
    text: widget.reauthenticate ? widget.session.accountEmail ?? '' : '',
  );
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  _Mode _mode = _Mode.signIn;
  bool _busy = false;
  bool _showPassword = false;
  String? _error;
  String? _info;

  bool get _signingUp => _mode == _Mode.signUp;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _switchMode() {
    setState(() {
      _mode = _signingUp ? _Mode.signIn : _Mode.signUp;
      _formKey = GlobalKey<FormState>();
      _error = null;
      _info = null;
      _confirm.clear();
    });
  }

  Future<void> _submit() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final email = _email.text.trim();
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      if (_signingUp) {
        final signedIn = await widget.session.signUp(email, _password.text);
        if (!mounted) return;
        if (!signedIn) {
          setState(() {
            _busy = false;
            _mode = _Mode.signIn;
            _password.clear();
            _confirm.clear();
            _info =
                'Account created. Check $email for a confirmation link, then '
                'sign in.';
          });
          return;
        }
      } else {
        await widget.session.signIn(email, _password.text);
      }
      if (!mounted) return;
      if (widget.reauthenticate) {
        Navigator.of(context).pop(true);
      } else {
        setState(() => _busy = false);
      }
    } on AuthFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        if (e.needsConfirmation) {
          _info = e.message;
        } else {
          _error = e.message;
        }
      });
    }
  }

  String? _validateEmail(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Enter your email.';
    if (!_emailPattern.hasMatch(text)) return 'Enter a valid email address.';
    return null;
  }

  String? _validatePassword(String? value) {
    final text = value ?? '';
    if (text.isEmpty) return 'Enter your password.';
    if (_signingUp && text.length < 8) {
      return 'Use at least 8 characters.';
    }
    return null;
  }

  String? _validateConfirm(String? value) =>
      value == _password.text ? null : 'Passwords do not match.';

  InputDecoration _decoration(String label, {Widget? suffix}) =>
      InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Colors.white,
        suffixIcon: suffix,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      );

  @override
  Widget build(BuildContext context) {
    final title = widget.reauthenticate
        ? 'Sign in again'
        : _signingUp
        ? 'Create your account'
        : 'Welcome to Lagaw';
    final subtitle = widget.reauthenticate
        ? 'Your session expired. Your unsaved changes are kept.'
        : _signingUp
        ? 'Plan Bacolod trips that stay with your account.'
        : 'Sign in to plan and save your Bacolod trips.';

    final isWide = MediaQuery.sizeOf(context).width >= 768;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: widget.reauthenticate
          ? AppBar(
              backgroundColor: Colors.transparent,
              foregroundColor: Colors.white,
              elevation: 0,
            )
          : null,
      body: _SkyBackdrop(
        isWide: isWide,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: 20,
                vertical: isWide ? 32 : 20,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FadeSlideIn(child: _Wordmark(isWide: isWide)),
                    SizedBox(height: isWide ? 26 : 20),
                    FadeSlideIn(
                      index: 1,
                      child: GlassContainer(
                        padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
                        child: Form(
                          key: _formKey,
                          child: AutofillGroup(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Semantics(
                                  header: true,
                                  child: Text(
                                    title,
                                    style: const TextStyle(
                                      fontFamily: 'Outfit',
                                      fontWeight: FontWeight.w900,
                                      fontSize: 24,
                                      color: AppTheme.slateDark,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  subtitle,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.slateMuted,
                                  ),
                                ),
                                const SizedBox(height: 18),
                                if (_error != null) ...[
                                  StatusBanner(
                                    key: const ValueKey('auth-error'),
                                    tone: StatusTone.error,
                                    message: _error!,
                                  ),
                                  const SizedBox(height: 14),
                                ],
                                if (_info != null) ...[
                                  StatusBanner(
                                    key: const ValueKey('auth-info'),
                                    tone: StatusTone.info,
                                    message: _info!,
                                  ),
                                  const SizedBox(height: 14),
                                ],
                                TextFormField(
                                  key: const ValueKey('auth-email'),
                                  controller: _email,
                                  enabled: !_busy,
                                  keyboardType: TextInputType.emailAddress,
                                  autofillHints: const [AutofillHints.email],
                                  textInputAction: TextInputAction.next,
                                  decoration: _decoration('Email'),
                                  validator: _validateEmail,
                                ),
                                const SizedBox(height: 14),
                                TextFormField(
                                  key: const ValueKey('auth-password'),
                                  controller: _password,
                                  enabled: !_busy,
                                  obscureText: !_showPassword,
                                  autofillHints: [
                                    _signingUp
                                        ? AutofillHints.newPassword
                                        : AutofillHints.password,
                                  ],
                                  textInputAction: _signingUp
                                      ? TextInputAction.next
                                      : TextInputAction.done,
                                  onFieldSubmitted: _signingUp
                                      ? null
                                      : (_) => _submit(),
                                  decoration: _decoration(
                                    'Password',
                                    suffix: IconButton(
                                      tooltip: _showPassword
                                          ? 'Hide password'
                                          : 'Show password',
                                      icon: Icon(
                                        _showPassword
                                            ? Icons.visibility_off_rounded
                                            : Icons.visibility_rounded,
                                      ),
                                      onPressed: () => setState(
                                        () => _showPassword = !_showPassword,
                                      ),
                                    ),
                                  ),
                                  validator: _validatePassword,
                                ),
                                if (_signingUp) ...[
                                  const SizedBox(height: 14),
                                  TextFormField(
                                    key: const ValueKey('auth-confirm'),
                                    controller: _confirm,
                                    enabled: !_busy,
                                    obscureText: !_showPassword,
                                    autofillHints: const [
                                      AutofillHints.newPassword,
                                    ],
                                    textInputAction: TextInputAction.done,
                                    onFieldSubmitted: (_) => _submit(),
                                    decoration: _decoration('Confirm password'),
                                    validator: _validateConfirm,
                                  ),
                                ],
                                const SizedBox(height: 20),
                                Vector3DButton(
                                  key: const ValueKey('auth-submit'),
                                  onTap: _busy ? null : _submit,
                                  backgroundColor: const Color(0xFFEA580C),
                                  shadowColor: const Color(0xFF9A3412),
                                  borderColor: const Color(0xFFFDBA74),
                                  borderRadius: 26,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 15,
                                  ),
                                  depth: 4,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      if (_busy) ...[
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
                                        _busy
                                            ? (_signingUp
                                                  ? 'Creating account…'
                                                  : 'Signing in…')
                                            : (_signingUp
                                                  ? 'Create account'
                                                  : 'Sign in'),
                                        style: const TextStyle(
                                          fontFamily: 'Outfit',
                                          fontWeight: FontWeight.w900,
                                          fontSize: 16,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (!widget.reauthenticate) ...[
                                  const SizedBox(height: 10),
                                  TextButton(
                                    key: const ValueKey('auth-switch-mode'),
                                    onPressed: _busy ? null : _switchMode,
                                    child: Text(
                                      _signingUp
                                          ? 'Already have an account? Sign in'
                                          : 'New to Lagaw? Create an account',
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const FadeSlideIn(index: 2, child: _FeatureRow()),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The app's sky: gradient, glowing sun and scattered 3D Bacolod badges,
/// matching the home screen. Decorations ignore taps. [S3-16]
class _SkyBackdrop extends StatelessWidget {
  final bool isWide;
  final Widget child;

  const _SkyBackdrop({required this.isWide, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppTheme.skyTop, AppTheme.skyMid, AppTheme.skyBottom],
          stops: [0.0, 0.5, 1.0],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: isWide ? -110 : -80,
            left: isWide ? -110 : -80,
            child: IgnorePointer(
              child: Container(
                width: isWide ? 360 : 260,
                height: isWide ? 360 : 260,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    radius: 0.8,
                    colors: [
                      Color(0xFFFFFBEB),
                      Color(0xFFFEF08A),
                      Color(0xFFF59E0B),
                      Color(0x00F59E0B),
                    ],
                    stops: [0.0, 0.35, 0.7, 1.0],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x66F59E0B),
                      blurRadius: 110,
                      spreadRadius: 40,
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Soft clouds drifting across the sky.
          ..._clouds(),
          if (isWide) ...const [
            Positioned(
              top: 150,
              left: 40,
              child: IgnorePointer(child: Cathedral3DBadge(size: 130)),
            ),
            Positioned(
              bottom: 90,
              left: 56,
              child: IgnorePointer(child: Inasal3DBadge(size: 125)),
            ),
            Positioned(
              top: 70,
              right: 48,
              child: IgnorePointer(child: MassKara3DBadge(size: 140)),
            ),
            Positioned(
              top: 330,
              right: 70,
              child: IgnorePointer(child: Piaya3DBadge(size: 110)),
            ),
            Positioned(
              bottom: 70,
              right: 40,
              child: IgnorePointer(child: Coffee3DBadge(size: 120)),
            ),
          ] else ...const [
            Positioned(
              top: 56,
              right: -10,
              child: IgnorePointer(child: MassKara3DBadge(size: 70)),
            ),
            Positioned(
              bottom: 150,
              left: -14,
              child: IgnorePointer(child: Piaya3DBadge(size: 62)),
            ),
            Positioned(
              bottom: 40,
              right: -10,
              child: IgnorePointer(child: Coffee3DBadge(size: 70)),
            ),
          ],
          child,
        ],
      ),
    );
  }

  /// Placed by fraction of the screen so they stay off the wordmark at any
  /// size; translucent, so they can pass behind the card.
  List<Widget> _clouds() => [
    for (final (alignment, width) in [
      (const Alignment(-0.6, 0.3), isWide ? 160.0 : 100.0),
      (const Alignment(0.6, -0.42), isWide ? 120.0 : 80.0),
    ])
      Align(
        alignment: alignment,
        child: IgnorePointer(
          child: Container(
            width: width,
            height: width * 0.32,
            decoration: BoxDecoration(
              color: const Color(0x55FFFFFF),
              borderRadius: BorderRadius.circular(width),
            ),
          ),
        ),
      ),
  ];
}

/// "lagaw." wordmark with the amber dot, as on the home hero.
class _Wordmark extends StatelessWidget {
  final bool isWide;

  const _Wordmark({required this.isWide});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              'lagaw',
              style: TextStyle(
                fontFamily: 'Outfit',
                fontSize: isWide ? 60 : 48,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: -1.6,
                height: 1.0,
                shadows: const [
                  Shadow(
                    color: Color(0x33000000),
                    blurRadius: 14,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 3),
            Container(
              width: isWide ? 9 : 7.5,
              height: isWide ? 9 : 7.5,
              decoration: const BoxDecoration(
                color: Color(0xFFF59E0B),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x66F59E0B),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'Swipe your vibe and tour Bacolod your way.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13.5,
            color: Color(0xEEFFFFFF),
            fontWeight: FontWeight.w600,
            height: 1.35,
            shadows: [Shadow(color: Color(0x33000000), blurRadius: 8)],
          ),
        ),
      ],
    );
  }
}

/// Small pills under the card hinting at what an account unlocks.
class _FeatureRow extends StatelessWidget {
  const _FeatureRow();

  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.luggage_rounded, 'Saved trips'),
      (Icons.auto_awesome_rounded, 'AI vibe picks'),
      (Icons.map_rounded, 'Day-by-day stops'),
    ];
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (icon, label) in items)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
              boxShadow: const [
                BoxShadow(
                  color: Color(0xFFCBD5E1),
                  offset: Offset(0, 3),
                  blurRadius: 0,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 15, color: const Color(0xFFEA580C)),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: const TextStyle(
                    fontFamily: 'Outfit',
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                    color: AppTheme.slateDark,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
