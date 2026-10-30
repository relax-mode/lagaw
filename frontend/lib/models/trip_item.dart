import 'location.dart';

/// One itinerary stop: Trip → Itinerary Item → Location, as returned by
/// `GET /api/v1/trips/{id}/items` or itinerary generation. [S3-34]
///
/// Generated stops (#54) also carry a schedule. All schedule fields are null
/// for manually added stops; null means unknown, never zero. [S3-11]
class TripItem {
  final String id;
  final String tripId;
  final String locationId;
  final int dayNumber;
  final int visitOrder;
  final LocationItem location;

  /// Local Asia/Manila wall-clock times as `HH:MM:SS`; not UTC.
  final String? arrivalTime;
  final String? departureTime;

  /// Minutes travelling to this stop from the previous one.
  final int? estimatedTravelTime;

  /// Party venue cost plus incoming travel, in PHP (already for the party).
  final double? estimatedCost;
  final double? recommendationScore;
  final String? recommendationReason;

  const TripItem({
    required this.id,
    required this.tripId,
    required this.locationId,
    required this.dayNumber,
    required this.visitOrder,
    required this.location,
    this.arrivalTime,
    this.departureTime,
    this.estimatedTravelTime,
    this.estimatedCost,
    this.recommendationScore,
    this.recommendationReason,
  });

  bool get isScheduled => arrivalTime != null && departureTime != null;

  factory TripItem.fromJson(Map<String, dynamic> json) => TripItem(
    id: json['id'] as String,
    tripId: json['trip_id'] as String,
    locationId: json['location_id'] as String,
    dayNumber: json['day_number'] as int,
    visitOrder: json['visit_order'] as int,
    location: LocationItem.fromJson(json['location'] as Map<String, dynamic>),
    arrivalTime: json['arrival_time'] as String?,
    departureTime: json['departure_time'] as String?,
    estimatedTravelTime: (json['estimated_travel_time'] as num?)?.toInt(),
    estimatedCost: parseOptionalMoney(json['estimated_cost']),
    recommendationScore: (json['recommendation_score'] as num?)?.toDouble(),
    recommendationReason: json['recommendation_reason'] as String?,
  );
}

/// Money arrives as a decimal string (or a number); null stays null.
double? parseOptionalMoney(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

class TripItemsPage {
  final List<TripItem> items;
  final int limit;
  final int offset;

  const TripItemsPage({
    required this.items,
    required this.limit,
    required this.offset,
  });

  factory TripItemsPage.fromJson(Map<String, dynamic> json) => TripItemsPage(
    items: [
      for (final item in json['items'] as List<dynamic>)
        TripItem.fromJson(item as Map<String, dynamic>),
    ],
    limit: json['limit'] as int,
    offset: json['offset'] as int,
  );
}
