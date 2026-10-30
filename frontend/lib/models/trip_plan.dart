import 'location.dart';
import 'trip_item.dart';

/// Values the recommendation/generation APIs accept for a saved trip. The
/// trip form offers more; trips using others must be edited first. [S3-11]
const Set<String> kPlannableGroups = {
  'solo',
  'couple',
  'family',
  'friends',
  'group',
};
const Set<String> kPlannableTags = {
  'cafe',
  'photography',
  'relaxing',
  'heritage',
  'food',
  'nature',
};
const Set<String> kPlannableTransport = {
  'walking',
  'jeepney',
  'taxi',
  'motorcycle',
  'private_car',
};

/// Choices for one recommendation/generation request. They are request
/// options only; Trip CRUD does not store them.
class PlanOptions {
  final int partySize;

  /// Total stops across the whole trip, not per day.
  final int plannedVisits;
  final int limit;
  final String duration;
  final String pace;

  const PlanOptions({
    required this.partySize,
    required this.plannedVisits,
    this.limit = 20,
    this.duration = 'full_day',
    this.pace = 'moderate',
  });

  /// `planned_visits <= limit` is required by generation.
  int get candidateLimit => limit < plannedVisits ? plannedVisits : limit;

  Map<String, dynamic> recommendationJson() => {
    'party_size': partySize,
    'planned_visits': plannedVisits,
    'limit': candidateLimit,
  };

  Map<String, dynamic> generationJson({String? expectedRevision}) => {
    'recommendations': recommendationJson(),
    'duration': duration,
    'pace': pace,
    'replace_existing': expectedRevision != null,
    'expected_revision': ?expectedRevision,
  };
}

/// One ranked suggestion from `POST /trips/{id}/recommendations`. Advisory
/// only: nothing is saved.
class TripRecommendation {
  final String locationId;
  final double score;
  final String reason;
  final LocationItem location;

  const TripRecommendation({
    required this.locationId,
    required this.score,
    required this.reason,
    required this.location,
  });

  factory TripRecommendation.fromJson(Map<String, dynamic> json) =>
      TripRecommendation(
        locationId: json['location_id'] as String,
        score: (json['recommendation_score'] as num).toDouble(),
        reason: json['recommendation_reason'] as String,
        location: LocationItem.fromJson(
          json['location'] as Map<String, dynamic>,
        ),
      );
}

class RecommendationsPage {
  final List<TripRecommendation> items;

  /// Why the list is empty (e.g. `no_compatible_locations`); null otherwise.
  final String? emptyReason;

  /// Per-person, per-visit budget the backend allocated from the trip total.
  final double? budgetMax;

  const RecommendationsPage({
    required this.items,
    this.emptyReason,
    this.budgetMax,
  });

  factory RecommendationsPage.fromJson(Map<String, dynamic> json) {
    final budget = json['budget'];
    return RecommendationsPage(
      items: [
        for (final item in json['items'] as List<dynamic>)
          TripRecommendation.fromJson(item as Map<String, dynamic>),
      ],
      emptyReason: json['empty_reason'] as String?,
      budgetMax: budget is Map<String, dynamic>
          ? parseOptionalMoney(budget['budget_max'])
          : null,
    );
  }
}

/// A saved generated itinerary from `POST /trips/{id}/generate-itinerary`.
class GenerationResult {
  final double? estimatedTotalCost;
  final String revision;
  final List<TripItem> items;

  const GenerationResult({
    required this.estimatedTotalCost,
    required this.revision,
    required this.items,
  });

  factory GenerationResult.fromJson(Map<String, dynamic> json) =>
      GenerationResult(
        estimatedTotalCost: parseOptionalMoney(json['estimated_total_cost']),
        revision: json['revision'] as String,
        items: [
          for (final item in json['items'] as List<dynamic>)
            TripItem.fromJson(item as Map<String, dynamic>),
        ],
      );
}

/// #52 interaction types.
enum InteractionType {
  leftSwipe('left_swipe'),
  rightSwipe('right_swipe'),
  save('save'),
  rating('rating');

  final String value;
  const InteractionType(this.value);
}
