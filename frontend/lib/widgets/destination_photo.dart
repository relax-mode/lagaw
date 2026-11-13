import 'package:flutter/material.dart';

import '../models/location.dart';

/// A destination's real photo, or an honest stand-in: the category colors
/// with an icon and "No photo yet". Never a photo of somewhere else. Also
/// used while loading and when the image fails. [S4-17]
class DestinationPhoto extends StatelessWidget {
  final LocationItem location;
  final double? width;
  final double? height;

  /// Small thumbnails show only the icon.
  final bool compact;

  const DestinationPhoto({
    super.key,
    required this.location,
    this.width,
    this.height,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final url = location.imageUrl;
    if (url == null) return _placeholder(label: 'No photo yet');
    return Image.network(
      url,
      width: width,
      height: height,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : _placeholder(),
      errorBuilder: (_, _, _) => _placeholder(label: 'Photo unavailable'),
    );
  }

  Widget _placeholder({String? label}) {
    return Container(
      key: ValueKey('photo-placeholder-${location.id}'),
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: location.gradientColors,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _icon(location.category),
              color: const Color(0xCCFFFFFF),
              size: compact ? 28 : 40,
            ),
            if (label != null && !compact) ...[
              const SizedBox(height: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xDDFFFFFF),
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static IconData _icon(String category) => switch (category) {
    'cafe' => Icons.local_cafe_rounded,
    'heritage' => Icons.account_balance_rounded,
    'museum' => Icons.museum_rounded,
    'park' => Icons.park_rounded,
    'gallery' => Icons.palette_rounded,
    'restaurant' => Icons.restaurant_rounded,
    'landmark' => Icons.location_city_rounded,
    _ => Icons.place_rounded,
  };
}
