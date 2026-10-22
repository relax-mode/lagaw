import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../utils/trip_format.dart';
import '../tactile_motion.dart';
import 'tactile_field_style.dart';

/// Tappable tile that opens the date range picker. [S2-04]
class DateRangeField extends StatelessWidget {
  final DateTimeRange? value;
  final ValueChanged<DateTimeRange> onChanged;
  final String? errorText;
  final DateTime? firstDate;

  const DateRangeField({
    super.key,
    required this.value,
    required this.onChanged,
    this.errorText,
    this.firstDate,
  });

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final first = firstDate ?? today;
    // Keep an existing (possibly past) trip editable without clamping it.
    final earliest = value != null && value!.start.isBefore(first)
        ? value!.start
        : first;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: earliest,
      lastDate: DateTime(today.year + 3, 12, 31),
      initialDateRange: value,
      helpText: 'When is your lagaw?',
      saveText: 'Done',
      confirmText: 'Done',
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final hasError = errorText != null;
    final days = value == null ? 0 : tripDayCount(value!.start, value!.end);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const TactileFieldLabel('Travel dates'),
        TactilePressable(
          key: const ValueKey('trip-dates'),
          hoverLift: 2,
          onTap: () => _pick(context),
          child: AnimatedContainer(
            duration: TactileMotion.hover,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(TactileFieldStyle.radius),
              border: Border.all(
                color: hasError
                    ? TactileFieldStyle.error
                    : TactileFieldStyle.border,
                width: 2,
              ),
              boxShadow: TactileFieldStyle.bevelShadow,
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.calendar_month_rounded,
                    size: 18,
                    color: AppTheme.primaryBlue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: value == null
                      ? const Text(
                          'Pick start and end dates',
                          style: TactileFieldStyle.hint,
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${formatShortDate(value!.start)} – ${formatShortDate(value!.end)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: AppTheme.slateDark,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              formatDayCount(days),
                              style: TactileFieldStyle.hint,
                            ),
                          ],
                        ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppTheme.slateMuted,
                ),
              ],
            ),
          ),
        ),
        TactileFieldError(errorText),
      ],
    );
  }
}
