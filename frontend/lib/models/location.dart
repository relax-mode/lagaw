import 'package:flutter/material.dart';

/// One Bacolod destination from `GET /locations`. Unknown facts stay
/// unknown: no invented price, visit length, photo or match score. [S4-17]
class LocationItem {
  final String id;
  final String name;
  final String description;
  final String category;
  final List<String> vibeTags;
  final String address;

  /// Display text, e.g. "₱70 – ₱100", "Free" or "Price unknown".
  final String costRange;

  /// Display text, e.g. "45 mins" or "Visit length unknown".
  final String duration;

  /// Null when the place has no approved photo yet.
  final String? imageUrl;
  final List<Color> gradientColors;

  const LocationItem({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.vibeTags,
    required this.address,
    required this.costRange,
    required this.duration,
    required this.imageUrl,
    required this.gradientColors,
  });

  /// Deserializes JSON from FastAPI GET /locations [S1-02 / S1-04]
  factory LocationItem.fromJson(Map<String, dynamic> json) {
    final rawImg = json['image_url']?.toString();
    final cat = json['category']?.toString() ?? 'spot';
    return LocationItem(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Unknown Spot',
      description: json['description']?.toString() ?? '',
      category: cat,
      vibeTags:
          (json['vibe_tags'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      address: json['address']?.toString() ?? 'Bacolod City',
      costRange: formatCostRange(
        _number(json['estimated_cost_min']),
        _number(json['estimated_cost_max']),
      ),
      duration: formatVisitLength(_number(json['typical_visit_duration'])),
      imageUrl: rawImg != null && rawImg.isNotEmpty && rawImg != 'null'
          ? rawImg
          : null,
      gradientColors: categoryGradient(cat),
    );
  }
}

/// Costs may arrive as numbers or decimal strings.
num? _number(Object? value) =>
    value is num ? value : num.tryParse(value?.toString() ?? '');

String _peso(num value) => value == value.roundToDouble()
    ? '₱${value.round()}'
    : '₱${value.toStringAsFixed(2)}';

/// Per-person cost text. "Free" only when the API says the place costs
/// nothing; a missing upper bound is never treated as free. [S4-17]
String formatCostRange(num? min, num? max) {
  if (max == null) {
    return min != null && min > 0 ? 'From ${_peso(min)}' : 'Price unknown';
  }
  if (max == 0) return 'Free';
  if (min == null) return 'Up to ${_peso(max)}';
  if (min == max) return _peso(max);
  return '${_peso(min)} – ${_peso(max)}';
}

String formatVisitLength(num? minutes) => minutes == null || minutes <= 0
    ? 'Visit length unknown'
    : '${minutes.round()} mins';

/// Card colors per category; also the honest "no photo" backdrop.
List<Color> categoryGradient(String category) => switch (category) {
  'cafe' => const [Color(0xFF78350F), Color(0xFFB45309)],
  'heritage' => const [Color(0xFF881337), Color(0xFFBE123C)],
  'park' => const [Color(0xFF14532D), Color(0xFF15803D)],
  'gallery' => const [Color(0xFF581C87), Color(0xFF7E22CE)],
  'restaurant' => const [Color(0xFF7C2D12), Color(0xFFC2410C)],
  _ => const [Color(0xFF1E293B), Color(0xFF334155)],
};
