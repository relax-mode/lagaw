import 'package:flutter/material.dart';

import '../../models/preference_draft.dart';
import '../../theme.dart';
import 'choice_chips_field.dart';
import 'trip_form.dart';

/// Lets the user confirm which suggested vibes to add. Resolves the tags to
/// add (possibly empty), or null when cancelled. Existing choices are never
/// removed; budget level, duration and pace are shown for reference only
/// because the Trip API has no fields for them. [S3-06]
Future<List<String>?> showPreferenceReview(
  BuildContext context, {
  required PreferenceDraft draft,
  required List<String> currentTags,
}) {
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x660F172A),
    builder: (_) =>
        PreferenceReviewSheet(draft: draft, currentTags: currentTags),
  );
}

String _humanize(String value) => value == 'unspecified'
    ? 'Not mentioned'
    : value
          .split('_')
          .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
          .join(' ');

class PreferenceReviewSheet extends StatefulWidget {
  final PreferenceDraft draft;
  final List<String> currentTags;

  const PreferenceReviewSheet({
    super.key,
    required this.draft,
    required this.currentTags,
  });

  @override
  State<PreferenceReviewSheet> createState() => _PreferenceReviewSheetState();
}

class _PreferenceReviewSheetState extends State<PreferenceReviewSheet> {
  late final List<String> _newTags = [
    for (final tag in widget.draft.preferredTags)
      if (!widget.currentTags.contains(tag)) tag,
  ];
  late final Set<String> _accepted = {..._newTags};

  ChipOption _option(String tag) => kPreferredTags.firstWhere(
    (o) => o.value == tag,
    orElse: () => ChipOption(tag, _humanize(tag), Icons.tag),
  );

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    final kept = [
      for (final tag in draft.preferredTags)
        if (widget.currentTags.contains(tag)) tag,
    ];
    final missing = [for (final field in draft.missingFields) _humanize(field)];

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
          maxWidth: 640,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: GlassContainer(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Review suggestions',
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                    color: AppTheme.slateDark,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Nothing changes until you apply, and nothing is saved '
                  'until you save the trip.',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                    color: AppTheme.slateMuted,
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      _heading('Vibes to add'),
                      if (_newTags.isEmpty)
                        _note(
                          draft.preferredTags.isEmpty
                              ? 'No vibes were found in your description.'
                              : 'Your trip already has every suggested vibe.',
                        ),
                      for (final tag in _newTags)
                        // Own Material so ink shows over the glass card.
                        Material(
                          type: MaterialType.transparency,
                          child: CheckboxListTile(
                            key: ValueKey('review-tag-$tag'),
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            value: _accepted.contains(tag),
                            secondary: Icon(_option(tag).icon),
                            title: Text(_option(tag).label),
                            onChanged: (on) => setState(
                              () => on == true
                                  ? _accepted.add(tag)
                                  : _accepted.remove(tag),
                            ),
                          ),
                        ),
                      if (kept.isNotEmpty)
                        _note(
                          'Already in your trip: '
                          '${kept.map((t) => _option(t).label).join(', ')}',
                        ),
                      const SizedBox(height: 10),
                      _heading('For reference (not saved)'),
                      _infoRow('Budget feel', _humanize(draft.budgetLevel)),
                      _infoRow('Time of day', _humanize(draft.duration)),
                      _infoRow('Pace', _humanize(draft.pace)),
                      const SizedBox(height: 6),
                      _note(
                        'Budget amounts are never guessed. Enter them in the '
                        'budget fields.',
                      ),
                      if (missing.isNotEmpty)
                        _note('Not mentioned: ${missing.join(', ')}'),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Vector3DButton(
                        key: const ValueKey('review-cancel'),
                        onTap: () => Navigator.of(context).pop(),
                        backgroundColor: Colors.white,
                        shadowColor: const Color(0xFFCBD5E1),
                        borderColor: const Color(0xFFE2E8F0),
                        borderRadius: 22,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        child: const Center(
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                              fontFamily: 'Outfit',
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                              color: AppTheme.slateDark,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Vector3DButton(
                        key: const ValueKey('review-apply'),
                        onTap: () => Navigator.of(context).pop([
                          for (final tag in _newTags)
                            if (_accepted.contains(tag)) tag,
                        ]),
                        backgroundColor: const Color(0xFF7C3AED),
                        shadowColor: const Color(0xFF5B21B6),
                        borderColor: const Color(0xFFC4B5FD),
                        borderRadius: 22,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        child: const Center(
                          child: Text(
                            'Apply to form',
                            style: TextStyle(
                              fontFamily: 'Outfit',
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(
      text,
      style: const TextStyle(
        fontFamily: 'Outfit',
        fontWeight: FontWeight.w800,
        fontSize: 13,
        color: AppTheme.slateMuted,
      ),
    ),
  );

  Widget _note(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Text(
      text,
      style: const TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 12.5,
        color: AppTheme.slateMuted,
      ),
    ),
  );

  Widget _infoRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: AppTheme.slateMuted,
            ),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: AppTheme.slateDark,
          ),
        ),
      ],
    ),
  );
}
