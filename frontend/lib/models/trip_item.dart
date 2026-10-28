import 'location.dart';

/// One manual itinerary stop: Trip → Itinerary Item → Location, as returned
/// by `GET /api/v1/trips/{id}/items`. [S3-34]
class TripItem {
  final String id;
  final String tripId;
  final String locationId;
  final int dayNumber;
  final int visitOrder;
  final LocationItem location;

  const TripItem({
    required this.id,
    required this.tripId,
    required this.locationId,
    required this.dayNumber,
    required this.visitOrder,
    required this.location,
  });

  factory TripItem.fromJson(Map<String, dynamic> json) => TripItem(
    id: json['id'] as String,
    tripId: json['trip_id'] as String,
    locationId: json['location_id'] as String,
    dayNumber: json['day_number'] as int,
    visitOrder: json['visit_order'] as int,
    location: LocationItem.fromJson(json['location'] as Map<String, dynamic>),
  );
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
