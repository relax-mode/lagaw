import 'package:flutter/material.dart';

import '../../theme.dart';
import 'tactile_field_style.dart';

/// One selectable chip: [value] is what the backend stores.
class ChipOption {
  final String value;
  final String label;
  final IconData icon;

  const ChipOption(this.value, this.label, this.icon);
}

/// Tactile chip picker styled like the category pills. Single select
/// toggles off when tapped again; multi select caps at [maxSelected]. [S2-04]
class TactileChipsField extends StatelessWidget {
  final String label;
  final List<ChipOption> options;
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;
  final bool multiSelect;
  final int? maxSelected;
  final bool optional;
  final String? errorText;
  final Color accent;
  final Color accentShadow;

  const TactileChipsField({
    super.key,
    required this.label,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.multiSelect = false,
    this.maxSelected,
    this.optional = true,
    this.errorText,
    this.accent = const Color(0xFFF2620F),
    this.accentShadow = const Color(0xFFC2410C),
  });

  void _toggle(String value) {
    if (!multiSelect) {
      onChanged(selected.contains(value) ? const [] : [value]);
      return;
    }
    if (selected.contains(value)) {
      onChanged(selected.where((v) => v != value).toList());
    } else if (maxSelected == null || selected.length < maxSelected!) {
      onChanged([...selected, value]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final atLimit = maxSelected != null && selected.length >= maxSelected!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TactileFieldLabel(label, optional: optional),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in options)
              _buildChip(option, selected.contains(option.value), atLimit),
          ],
        ),
        TactileFieldError(errorText),
      ],
    );
  }

  Widget _buildChip(ChipOption option, bool isSelected, bool atLimit) {
    final disabled = !isSelected && multiSelect && atLimit;
    return Semantics(
      selected: isSelected,
      button: true,
      child: Opacity(
        opacity: disabled ? 0.45 : 1,
        child: Vector3DButton(
          key: ValueKey('chip-${option.value}'),
          onTap: disabled ? null : () => _toggle(option.value),
          backgroundColor: isSelected ? accent : TactileFieldStyle.fill,
          shadowColor: isSelected ? accentShadow : TactileFieldStyle.fill,
          borderRadius: 999,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          depth: isSelected ? 3.5 : 2.5,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isSelected ? Icons.check_rounded : option.icon,
                size: 16,
                color: isSelected ? Colors.white : AppTheme.primaryBlue,
              ),
              const SizedBox(width: 6),
              Text(
                option.label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? Colors.white : AppTheme.slateDark,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
