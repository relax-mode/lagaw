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

/// Tappable summary card for one saved trip in the My Trips list. [S2-04]
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

    return TactilePressable(
      onTap: onTap,
      child: GlassContainer(
        borderRadius: 22,
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFFBBF24), Color(0xFFEA580C)],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0xFF9A3412),
                    offset: Offset(0, 3),
                    blurRadius: 0,
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '$days',
                    style: const TextStyle(
                      fontFamily: 'Outfit',
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                      height: 1,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    days == 1 ? 'day' : 'days',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 10,
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
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          trip.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'Outfit',
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            color: AppTheme.slateDark,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TripStatusPill(trip.status),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${formatDateRange(trip.startDate, trip.endDate)}  •  '
                    '${formatBudgetRange(trip.budgetMin, trip.budgetMax)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                      color: AppTheme.slateMuted,
                    ),
                  ),
                  if (transport != null || group != null) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (transport != null)
                          TripPill(
                            label: transport.label,
                            icon: transport.icon,
                          ),
                        if (group != null)
                          TripPill(
                            label: group.label,
                            icon: group.icon,
                            color: const Color(0xFF7C3AED),
                            background: const Color(0xFFF5F3FF),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right_rounded, color: AppTheme.slateMuted),
          ],
        ),
      ),
    );
  }
}
