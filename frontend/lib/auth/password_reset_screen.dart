import 'package:flutter/material.dart';

import '../theme.dart';
import 'auth_client.dart';
import 'auth_session.dart';

/// Supabase recovery links create a short-lived authenticated recovery session.
/// Only [AuthChange.passwordRecovery] may route to this screen; never present
/// a password update form after an ordinary sign-in. Do not expose link tokens.
class PasswordResetScreen extends StatefulWidget {
  final AuthSession session;

  const PasswordResetScreen({super.key, required this.session});

  @override
  State<PasswordResetScreen> createState() => _PasswordResetScreenState();
}

class _PasswordResetScreenState extends State<PasswordResetScreen> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _done = false;
  bool _showPassword = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Enter a new password.';
    if (value.length < 8) return 'Use at least 8 characters.';
    return null;
  }

  String? _validateConfirm(String? value) =>
      value == _password.text ? null : 'Passwords do not match.';

  Future<void> _updatePassword() async {
    if (_busy || _done || !_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.session.updatePassword(_password.text);
      if (!mounted) return;
      _password.clear();
      _confirm.clear();
      setState(() {
        _busy = false;
        _done = true;
      });
    } on AuthFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not update your password. Try again.';
      });
    }
  }

  Future<void> _finish() async {
    if (_busy) return;
    setState(() => _busy = true);
    // Ends the one-time recovery session. A fresh sign-in proves that the new
    // password works, rather than silently continuing as the reset user.
    await widget.session.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 768;
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppTheme.skyTop, AppTheme.skyMid, AppTheme.skyBottom],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: 20,
                vertical: isWide ? 32 : 20,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Card(
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: _done ? _success() : _form(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _success() => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Icon(
        Icons.check_circle_outline,
        size: 48,
        color: Color(0xFF15803D),
      ),
      const SizedBox(height: 12),
      const Text(
        'Password updated',
        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 24),
      ),
      const SizedBox(height: 8),
      const Text(
        'Your password has been changed. Sign in with the new password.',
      ),
      const SizedBox(height: 24),
      FilledButton(
        key: const ValueKey('reset-return-sign-in'),
        onPressed: _busy ? null : _finish,
        child: const Text('Return to sign in'),
      ),
    ],
  );

  Widget _form() => Form(
    key: _formKey,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Choose a new password',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 24),
        ),
        const SizedBox(height: 8),
        const Text('Enter a new password for your Lagaw account.'),
        const SizedBox(height: 20),
        if (_error != null) ...[
          Text(
            _error!,
            key: const ValueKey('reset-error'),
            style: const TextStyle(color: Color(0xFFB91C1C)),
          ),
          const SizedBox(height: 14),
        ],
        TextFormField(
          key: const ValueKey('reset-password'),
          controller: _password,
          enabled: !_busy,
          obscureText: !_showPassword,
          autofillHints: const [AutofillHints.newPassword],
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: 'New password',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              tooltip: _showPassword ? 'Hide password' : 'Show password',
              onPressed: () => setState(() => _showPassword = !_showPassword),
              icon: Icon(
                _showPassword ? Icons.visibility_off : Icons.visibility,
              ),
            ),
          ),
          validator: _validatePassword,
        ),
        const SizedBox(height: 14),
        TextFormField(
          key: const ValueKey('reset-confirm'),
          controller: _confirm,
          enabled: !_busy,
          obscureText: !_showPassword,
          autofillHints: const [AutofillHints.newPassword],
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _updatePassword(),
          decoration: const InputDecoration(
            labelText: 'Confirm new password',
            border: OutlineInputBorder(),
          ),
          validator: _validateConfirm,
        ),
        const SizedBox(height: 24),
        FilledButton(
          key: const ValueKey('reset-submit'),
          onPressed: _busy ? null : _updatePassword,
          child: Text(_busy ? 'Updating…' : 'Update password'),
        ),
        const SizedBox(height: 8),
        TextButton(
          key: const ValueKey('reset-cancel'),
          onPressed: _busy ? null : _finish,
          child: const Text('Cancel and sign in'),
        ),
      ],
    ),
  );
}
