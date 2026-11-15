import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/preference_draft.dart';
import '../../services/preference_service.dart';
import '../../theme.dart';
import '../status_banner.dart';
import 'tactile_field_style.dart';

/// "Describe your trip" box at the top of the trip form. Sends the text to
/// the backend extraction endpoint and hands the suggestions back for
/// review. It never edits the form itself, so a failure leaves every
/// entered value untouched. [S3-06]
class DescribeTripCard extends StatefulWidget {
  final PreferenceService service;
  final ValueChanged<PreferenceDraft> onSuggestions;

  /// False while the trip itself is being saved.
  final bool enabled;

  /// Shown after suggestions were applied, e.g. "Added 2 vibes…".
  final String? notice;

  const DescribeTripCard({
    super.key,
    required this.service,
    required this.onSuggestions,
    this.enabled = true,
    this.notice,
  });

  @override
  State<DescribeTripCard> createState() => _DescribeTripCardState();
}

class _DescribeTripCardState extends State<DescribeTripCard> {
  final _prompt = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _prompt.dispose();
    super.dispose();
  }

  Future<void> _suggest() async {
    if (_loading) return;
    final prompt = _prompt.text.trim();
    if (prompt.isEmpty) {
      setState(() => _error = 'Describe your trip first.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final draft = await widget.service.extract(prompt);
      if (!mounted) return;
      setState(() => _loading = false);
      widget.onSuggestions(draft);
    } on PreferenceApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSuggest = widget.enabled && !_loading;
    return Column(
      key: const ValueKey('describe-trip'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Row(
          children: [
            Icon(
              Icons.auto_awesome_rounded,
              color: Color(0xFFF2620F),
              size: 20,
            ),
            SizedBox(width: 8),
            Text(
              'Describe your trip',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 17,
                color: AppTheme.slateDark,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Optional. Get suggested vibes, then review them before anything '
          'changes. Or just fill in the form below.',
          style: TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 13.5,
            height: 1.4,
            color: AppTheme.slateMuted,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          key: const ValueKey('describe-trip-prompt'),
          controller: _prompt,
          enabled: !_loading,
          minLines: 2,
          maxLines: 4,
          inputFormatters: [
            LengthLimitingTextInputFormatter(PreferenceService.maxPromptLength),
          ],
          // Same type and field style as the rest of the form.
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppTheme.slateDark,
          ),
          decoration: TactileFieldStyle.decoration(
            hintText:
                'e.g. A slow, relaxing afternoon with coffee and photography',
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          StatusBanner(
            key: const ValueKey('describe-trip-error'),
            tone: StatusTone.error,
            message: _error!,
          ),
        ] else if (widget.notice != null) ...[
          const SizedBox(height: 10),
          StatusBanner(
            key: const ValueKey('describe-trip-notice'),
            tone: StatusTone.success,
            message: widget.notice!,
          ),
        ],
        const SizedBox(height: 12),
        Vector3DButton(
          key: const ValueKey('describe-trip-suggest'),
          onTap: canSuggest ? _suggest : null,
          backgroundColor: canSuggest
              ? AppTheme.primaryBlue
              : const Color(0xFF93B4F5),
          shadowColor: AppTheme.primaryBlue,
          borderRadius: 999,
          padding: const EdgeInsets.symmetric(vertical: 14),
          depth: 3.5,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_loading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: Colors.white,
                  ),
                )
              else
                const Icon(
                  Icons.auto_awesome_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              const SizedBox(width: 8),
              Text(
                _loading ? 'Reading your description…' : 'Suggest preferences',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
