import 'package:flutter/material.dart';

import '../models/location.dart';
import '../theme.dart';
import 'trip_card.dart';

/// "heritage" → "Heritage"; locations store lowercase categories.
String categoryLabel(String category) => category.isEmpty
    ? 'Spot'
    : '${category[0].toUpperCase()}${category.substring(1)}';

IconData categoryIcon(String category) => switch (category) {
  'cafe' => Icons.local_cafe_rounded,
  'restaurant' => Icons.restaurant_rounded,
  'heritage' => Icons.account_balance_rounded,
  'museum' => Icons.museum_rounded,
  'gallery' => Icons.palette_rounded,
  'park' => Icons.park_rounded,
  'landmark' => Icons.location_city_rounded,
  _ => Icons.place_rounded,
};

/// Name, category and practical details of one Bacolod location, shared by
/// the itinerary list and the destination picker. [S3-34]
class DestinationTile extends StatelessWidget {
  final LocationItem location;

  /// Shown before the name, e.g. the visit order "1".
  final String? badge;
  final Widget? trailing;

  /// Extra lines under the details, e.g. a generated stop's schedule.
  final Widget? footer;
  final bool selected;

  const DestinationTile({
    super.key,
    required this.location,
    this.badge,
    this.trailing,
    this.footer,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final details = [
      location.costRange,
      location.duration,
    ].where((d) => d.isNotEmpty).join(' · ');

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFEFF6FF) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: selected ? AppTheme.primaryBlue : const Color(0xFFE2E8F0),
          width: selected ? 2 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: location.gradientColors),
              borderRadius: BorderRadius.circular(12),
            ),
            child: badge != null
                ? Text(
                    badge!,
                    style: const TextStyle(
                      fontFamily: 'Outfit',
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      color: Colors.white,
                    ),
                  )
                : Icon(
                    categoryIcon(location.category),
                    size: 18,
                    color: Colors.white,
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  location.name,
                  style: const TextStyle(
                    fontFamily: 'Outfit',
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    color: AppTheme.slateDark,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    TripPill(
                      label: categoryLabel(location.category),
                      icon: categoryIcon(location.category),
                      color: const Color(0xFFC2410C),
                      background: const Color(0xFFFFF7ED),
                    ),
                    Text(
                      location.address,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        color: AppTheme.slateMuted,
                      ),
                    ),
                  ],
                ),
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    details,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: AppTheme.slateMuted,
                    ),
                  ),
                ],
                if (footer != null) ...[const SizedBox(height: 6), footer!],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}
