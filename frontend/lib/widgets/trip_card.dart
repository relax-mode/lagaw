import 'package:flutter/material.dart';

import '../models/trip.dart';
import '../theme.dart';
import '../utils/trip_format.dart';
import 'tactile_motion.dart';
import 'trip_form/choice_chips_field.dart';
import 'trip_form/trip_form.dart';

/// Looks up the display option for a stored chip value, if any.
ChipOption? chipOptionFor(List<ChipOption> options, String? value) {
  for (final option in options) {
    if (option.value == value) return option;
  }
  return null;
}

/// Small rounded label used for status and trip facts.
class TripPill extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color color;
  final Color background;

  const TripPill({
    super.key,
    required this.label,
    this.icon,
    this.color = AppTheme.primaryBlue,
    this.background = const Color(0xFFEFF6FF),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Status pill: drafts are amber, everything else green.
class TripStatusPill extends StatelessWidget {
  final String status;

  const TripStatusPill(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    final isDraft = status == 'draft';
    return TripPill(
      label: status.isEmpty
          ? 'Draft'
          : '${status[0].toUpperCase()}${status.substring(1)}',
      icon: isDraft ? Icons.edit_note_rounded : Icons.check_circle_rounded,
      color: isDraft ? const Color(0xFFB45309) : const Color(0xFF15803D),
      background: isDraft ? const Color(0xFFFEF3C7) : const Color(0xFFDCFCE7),
    );
  }
}

const _months = [
  'JAN',
  'FEB',
  'MAR',
  'APR',
  'MAY',
  'JUN',
  'JUL',
  'AUG',
  'SEP',
  'OCT',
  'NOV',
  'DEC',
];

/// Tappable summary card for one saved trip in the My Trips list: a white
/// card with a sky date tile, matching the v3 Spots cards. [S2-04, home v3]
class TripCard extends StatelessWidget {
  final Trip trip;
  final VoidCallback onTap;

  const TripCard({super.key, required this.trip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final transport = chipOptionFor(
      kTransportationModes,
      trip.transportationMode,
    );
    final group = chipOptionFor(kGroupTypes, trip.groupType);
    final days = tripDayCount(trip.startDate, trip.endDate);
    final draft = trip.status == 'draft' || trip.status.isEmpty;
    final status = trip.status.isEmpty
        ? 'Draft'
        : '${trip.status[0].toUpperCase()}${trip.status.substring(1)}';

    Widget fact(IconData icon, String label) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5FB),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppTheme.primaryBlue),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: AppTheme.slateDark,
            ),
          ),
        ],
      ),
    );

    return TactilePressable(
      onTap: onTap,
      hoverLift: 2,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(
              color: Color(0x4D0F285A),
              blurRadius: 26,
              offset: Offset(0, 14),
              spreadRadius: -14,
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 64,
              height: 72,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppTheme.skyTop, AppTheme.skyMid],
                ),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _months[trip.startDate.month - 1],
                    style: const TextStyle(
                      fontSize: 11,
                      letterSpacing: 1,
                      fontWeight: FontWeight.w700,
                      color: Color(0xE6FFFFFF),
                    ),
                  ),
                  Text(
                    '${trip.startDate.day}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 26,
                      height: 1.05,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          trip.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 17,
                            color: AppTheme.slateDark,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: draft
                              ? const Color(0xFFFFF3EA)
                              : const Color(0xFFE8F8EE),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          status,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: draft
                                ? const Color(0xFFC2410C)
                                : const Color(0xFF15803D),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${formatDayCount(days)} · '
                    '${formatDateRange(trip.startDate, trip.endDate)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: AppTheme.slateMuted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      fact(
                        Icons.payments_outlined,
                        formatBudgetRange(trip.budgetMin, trip.budgetMax),
                      ),
                      if (transport != null)
                        fact(transport.icon, transport.label),
                      if (group != null) fact(group.icon, group.label),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
