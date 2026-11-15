import 'dart:async';

import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/status_banner.dart';
import 'auth_client.dart';
import 'auth_session.dart';

enum _Mode { signIn, signUp, resetRequest }

final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// Email/password log in and sign-up through Supabase Auth: a sky header
/// with the Lagaw logo and a white sheet holding the form. [S3-16, home v3]
///
/// With [reauthenticate], it is pushed over the current screen after a
/// session expired, and pops on success so unsaved forms underneath stay.
class SignInScreen extends StatefulWidget {
  final AuthSession session;
  final bool reauthenticate;

  /// Opens on Create account instead of Log in.
  final bool initialSignUp;

  /// Back to the welcome page (from the intro flow).
  final VoidCallback? onBack;

  const SignInScreen({
    super.key,
    required this.session,
    this.reauthenticate = false,
    this.initialSignUp = false,
    this.onBack,
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
  late _Mode _mode = widget.initialSignUp ? _Mode.signUp : _Mode.signIn;
  bool _busy = false;
  bool _showPassword = false;
  String? _error;
  String? _info;

  // Seconds left before another attempt after a rate limit, so repeated taps
  // don't spend more of Supabase's limit.
  int _cooldown = 0;
  Timer? _cooldownTimer;

  bool get _signingUp => _mode == _Mode.signUp;
  bool get _requestingReset => _mode == _Mode.resetRequest;
  bool get _canSubmit => !_busy && _cooldown == 0;

  void _startCooldown(Duration wait) {
    _cooldownTimer?.cancel();
    _cooldown = wait.inSeconds;
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _cooldown--);
      if (_cooldown <= 0) timer.cancel();
    });
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _switchMode() {
    setState(() {
      _mode = _signingUp || _requestingReset ? _Mode.signIn : _Mode.signUp;
      _formKey = GlobalKey<FormState>();
      _error = null;
      _info = null;
      _confirm.clear();
      // An email limit on sign-up must not block signing in instead.
      _cooldownTimer?.cancel();
      _cooldown = 0;
    });
  }

  void _showResetRequest() {
    setState(() {
      _mode = _Mode.resetRequest;
      _formKey = GlobalKey<FormState>();
      _error = null;
      _info = null;
      _password.clear();
      _confirm.clear();
    });
  }

  Future<void> _submit() async {
    if (!_canSubmit || !_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final email = _email.text.trim();
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      if (_requestingReset) {
        await widget.session.requestPasswordReset(email);
        if (!mounted) return;
        setState(() {
          _busy = false;
          _info =
              'If this email has a Lagaw account, a password reset '
              'link will arrive shortly. Check your inbox and spam folder.';
        });
        return;
      }
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
        final wait = e.retryAfter;
        if (wait != null) _startCooldown(wait);
        if (_requestingReset && e.retryAfter != null) {
          _info =
              'Please wait before requesting another reset email. '
              'Check your inbox and spam folder first.';
        } else if (e.needsConfirmation) {
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

  InputDecoration _decoration(String hint, {Widget? suffix}) => InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: const Color(0xFFF1F5FB),
    suffixIcon: suffix,
    errorMaxLines: 3,
    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: _orange, width: 1.6),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.2),
    ),
  );

  String get _submitLabel => _busy
      ? (_requestingReset
            ? 'Sending reset email…'
            : _signingUp
            ? 'Creating account…'
            : 'Logging in…')
      : _cooldown > 0
      ? 'Try again in ${_cooldown}s'
      : (_requestingReset
            ? 'Send reset link'
            : _signingUp
            ? 'Create account'
            : widget.reauthenticate
            ? 'Sign in'
            : 'Log in');

  @override
  Widget build(BuildContext context) {
    final title = widget.reauthenticate
        ? 'Sign in again'
        : _requestingReset
        ? 'Reset your password'
        : _signingUp
        ? 'Create your account'
        : 'Welcome back';
    final subtitle = widget.reauthenticate
        ? 'Your session expired. Your unsaved changes are kept.'
        : _requestingReset
        ? 'We will send a reset link to your email address.'
        : _signingUp
        ? 'Swipe, save and plan Bacolod trips with your own account.'
        : 'Log in to keep swiping, saving and planning your Bacolod trips.';

    void back() {
      if (_requestingReset) {
        _switchMode();
      } else if (widget.onBack != null) {
        widget.onBack!();
      } else {
        Navigator.of(context).maybePop();
      }
    }

    final canGoBack =
        _requestingReset ||
        widget.onBack != null ||
        (widget.reauthenticate && Navigator.of(context).canPop());

    return Scaffold(
      backgroundColor: Colors.white,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppTheme.skyTop, AppTheme.skyMid],
          ),
        ),
        child: Stack(
          children: [
            const _SkyArt(),
            SafeArea(
              bottom: false,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    children: [
                      SizedBox(
                        height: 52,
                        child: Row(
                          children: [
                            if (canGoBack)
                              TextButton.icon(
                                key: const ValueKey('auth-back'),
                                onPressed: _busy ? null : back,
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  textStyle: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                icon: const Icon(
                                  Icons.arrow_back_ios_new_rounded,
                                  size: 16,
                                ),
                                label: const Text('Back'),
                              ),
                          ],
                        ),
                      ),
                      // The logo, floating in the sky above the sheet.
                      Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 22),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x550A2A6B),
                                blurRadius: 26,
                                offset: Offset(0, 14),
                                spreadRadius: -8,
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: Image.asset(
                              'assets/brand/logo.png',
                              key: const ValueKey('auth-logo'),
                              width: 78,
                              height: 78,
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Container(
                          width: double.infinity,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(34),
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
                          child: SafeArea(
                            top: false,
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(
                                24,
                                30,
                                24,
                                24,
                              ),
                              child: _form(title, subtitle),
                            ),
                          ),
                        ),
                      ),
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

  Widget _form(String title, String subtitle) {
    return Form(
      key: _formKey,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 28,
                  letterSpacing: -0.6,
                  color: AppTheme.slateDark,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14.5,
                height: 1.4,
                fontWeight: FontWeight.w500,
                color: AppTheme.slateMuted,
              ),
            ),
            const SizedBox(height: 22),
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
              textInputAction: _requestingReset
                  ? TextInputAction.done
                  : TextInputAction.next,
              onFieldSubmitted: _requestingReset ? (_) => _submit() : null,
              decoration: _decoration('Email'),
              validator: _validateEmail,
            ),
            if (!_requestingReset) ...[
              const SizedBox(height: 12),
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
                onFieldSubmitted: _signingUp ? null : (_) => _submit(),
                decoration: _decoration(
                  'Password',
                  suffix: IconButton(
                    tooltip: _showPassword ? 'Hide password' : 'Show password',
                    icon: Icon(
                      _showPassword
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                      color: AppTheme.slateMuted,
                    ),
                    onPressed: () =>
                        setState(() => _showPassword = !_showPassword),
                  ),
                ),
                validator: _validatePassword,
              ),
              if (_signingUp) ...[
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('auth-confirm'),
                  controller: _confirm,
                  enabled: !_busy,
                  obscureText: !_showPassword,
                  autofillHints: const [AutofillHints.newPassword],
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  decoration: _decoration('Confirm password'),
                  validator: _validateConfirm,
                ),
              ],
            ],
            if (!_signingUp && !_requestingReset && !widget.reauthenticate)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: const ValueKey('auth-forgot-password'),
                  onPressed: _busy ? null : _showResetRequest,
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.primaryBlue,
                    textStyle: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: const Text('Forgot password?'),
                ),
              )
            else
              const SizedBox(height: 18),
            const SizedBox(height: 6),
            FilledButton(
              key: const ValueKey('auth-submit'),
              onPressed: _canSubmit ? _submit : null,
              style: FilledButton.styleFrom(
                backgroundColor: _orange,
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFF7A26F),
                disabledForegroundColor: Colors.white,
                shape: const StadiumBorder(),
                minimumSize: const Size.fromHeight(54),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
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
                  Flexible(child: Text(_submitLabel)),
                ],
              ),
            ),
            if (!widget.reauthenticate) ...[
              const SizedBox(height: 18),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    _requestingReset
                        ? 'Remembered it?'
                        : _signingUp
                        ? 'Already have an account?'
                        : 'Don’t have an account?',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.slateMuted,
                    ),
                  ),
                  TextButton(
                    key: const ValueKey('auth-switch-mode'),
                    onPressed: _busy ? null : _switchMode,
                    style: TextButton.styleFrom(
                      foregroundColor: _orange,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      textStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    child: Text(
                      _requestingReset || _signingUp ? 'Log in' : 'Sign up',
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

const _orange = Color(0xFFF2620F);

/// The sky behind the header: the sun and two Bacolod elements, still so
/// the form never competes with motion. [home v3]
class _SkyArt extends StatelessWidget {
  const _SkyArt();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            top: -90,
            left: -90,
            child: Container(
              width: 250,
              height: 250,
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
          Positioned(
            top: 92,
            left: -30,
            child: Transform.rotate(
              angle: -0.28,
              child: Image.asset('assets/elements/masskara.webp', width: 100),
            ),
          ),
          Positioned(
            top: 70,
            right: -34,
            child: Transform.rotate(
              angle: -0.35,
              child: Image.asset('assets/elements/inasal.webp', width: 116),
            ),
          ),
        ],
      ),
    );
  }
}
