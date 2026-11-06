import 'package:flutter/material.dart';

class LocationItem {
  final String id;
  final String name;
  final String description;
  final String category;
  final List<String> vibeTags;
  final String address;
  final String costRange;
  final String duration;
  final int matchScore;
  final String imageUrl;
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
    required this.matchScore,
    required this.imageUrl,
    required this.gradientColors,
  });

  /// Deserializes JSON from FastAPI GET /locations [S1-02 / S1-04]
  factory LocationItem.fromJson(Map<String, dynamic> json) {
    final minCost = (json['estimated_cost_min'] as num?)?.toInt();
    final maxCost = (json['estimated_cost_max'] as num?)?.toInt();
    String costText = 'Free';
    if (minCost != null && maxCost != null && maxCost > 0) {
      costText = '₱$minCost – ₱$maxCost';
    } else if (minCost != null && minCost > 0) {
      costText = '₱$minCost+';
    }
    final mins = json['typical_visit_duration'] as int? ?? 60;
    final rawImg = json['image_url']?.toString();
    final img = (rawImg != null && rawImg.isNotEmpty && rawImg != 'null')
        ? rawImg
        : 'https://images.unsplash.com/photo-1548625361-16800b352a94?auto=format&fit=crop&w=900&q=80';

    final cat = json['category']?.toString() ?? 'spot';
    final List<Color> gradients = switch (cat) {
      'cafe' => const [Color(0xFF78350F), Color(0xFFB45309)],
      'heritage' => const [Color(0xFF881337), Color(0xFFBE123C)],
      'park' => const [Color(0xFF14532D), Color(0xFF15803D)],
      'gallery' => const [Color(0xFF581C87), Color(0xFF7E22CE)],
      'restaurant' => const [Color(0xFF7C2D12), Color(0xFFC2410C)],
      _ => const [Color(0xFF1E293B), Color(0xFF334155)],
    };

    return LocationItem(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Unknown Spot',
      description: json['description']?.toString() ?? '',
      category: cat,
      vibeTags: (json['vibe_tags'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      address: json['address']?.toString() ?? 'Bacolod City',
      costRange: costText,
      duration: '$mins mins',
      matchScore: 92,
      imageUrl: img,
      gradientColors: gradients,
    );
  }
}

/// Seeded Bacolod locations matching Supabase table [S1-02]
const List<LocationItem> kBacolodLocations = [
  LocationItem(
    id: '1a3bca09-5532-5de6-8587-2440c4e5830d',
    name: 'San Sebastian Cathedral',
    description:
        'A historic coral-stone Catholic cathedral in the heart of downtown Bacolod.',
    category: 'heritage',
    vibeTags: ['heritage', 'photography', 'architecture'],
    address: 'Rizal St, Bacolod City',
    costRange: 'Free',
    duration: '45 mins',
    matchScore: 98,
    imageUrl:
        'https://images.unsplash.com/photo-1548625361-16800b352a94?auto=format&fit=crop&w=900&q=80',
    gradientColors: [Color(0xFF78350F), Color(0xFFC2410C)],
  ),
  LocationItem(
    id: 'f2ccf475-56ea-51a0-a003-70f66d9f852a',
    name: 'Calea Pastries & Coffee',
    description:
        'Iconic Bacolod pastry and dessert café famous for mudpie and imported chocolate cakes.',
    category: 'cafe',
    vibeTags: ['cafe', 'food', 'relaxing', 'sweet'],
    address: '15th Lacson St, Bacolod City',
    costRange: '₱150 – ₱350',
    duration: '60 mins',
    matchScore: 96,
    imageUrl:
        'https://images.unsplash.com/photo-1554118811-1e0d58224f24?auto=format&fit=crop&w=900&q=80',
    gradientColors: [Color(0xFF4C0519), Color(0xFF78350F)],
  ),
  LocationItem(
    id: 'd184610e-f8c9-584a-95a3-79809cd81c49',
    name: 'Orange Project',
    description:
        'A contemporary art gallery and creative hub within Mandalagan Art District.',
    category: 'gallery',
    vibeTags: ['photography', 'art', 'creative'],
    address: 'Art District, Mandalagan',
    costRange: '₱100 – ₱250',
    duration: '90 mins',
    matchScore: 95,
    imageUrl:
        'https://images.unsplash.com/photo-1518998053901-5348d3961a04?auto=format&fit=crop&w=900&q=80',
    gradientColors: [Color(0xFFEA580C), Color(0xFF9F1239)],
  ),
  LocationItem(
    id: 'af80a358-d1ad-529f-84b3-ff1e591e041f',
    name: 'Capitol Park and Lagoon',
    description:
        'Scenic public park surrounding a tranquil lagoon with twin water buffalo sculptures.',
    category: 'park',
    vibeTags: ['nature', 'relaxing', 'sunset'],
    address: 'Lacson St, Bacolod City',
    costRange: 'Free',
    duration: '60 mins',
    matchScore: 93,
    imageUrl:
        'https://images.unsplash.com/photo-1585938389612-a552a28d6914?auto=format&fit=crop&w=900&q=80',
    gradientColors: [Color(0xFF065F46), Color(0xFF155E75)],
  ),
  LocationItem(
    id: 'a752a30a-1859-503d-8a77-8cd59097ac1d',
    name: 'Cafetolyo Coffee Shop',
    description:
        'Cozy neighborhood coffee and light-refreshment stop ideal for slow afternoons.',
    category: 'cafe',
    vibeTags: ['cafe', 'food', 'relaxing'],
    address: 'Capitol Shopping Center, Bacolod',
    costRange: '₱120 – ₱280',
    duration: '60 mins',
    matchScore: 91,
    imageUrl:
        'https://images.unsplash.com/photo-1495474472287-4d71bcdd2085?auto=format&fit=crop&w=900&q=80',
    gradientColors: [Color(0xFF292524), Color(0xFF451A03)],
  ),
  LocationItem(
    id: '61bf94ab-6ec0-5ec3-8451-b575ee06169e',
    name: 'The Negros Museum',
    description:
        'Curated museum of Negros history, sugar heritage, folk toys, and local contemporary art.',
    category: 'museum',
    vibeTags: ['heritage', 'photography', 'culture'],
    address: 'Gatuslao St, Bacolod City',
    costRange: '₱100 – ₱150',
    duration: '75 mins',
    matchScore: 90,
    imageUrl:
        'https://images.unsplash.com/photo-1565060169194-19fabf63012c?auto=format&fit=crop&w=900&q=80',
    gradientColors: [Color(0xFF1E293B), Color(0xFF1E1B4B)],
  ),
  LocationItem(
    id: '4618dfae-4a30-5917-85f1-94f216cf5b97',
    name: 'Negros Occidental Provincial Capitol',
    description:
        'Beaux-Arts neoclassical seat of the provincial government overlooking the Lagoon.',
    category: 'landmark',
    vibeTags: ['heritage', 'photography', 'landmark'],
    address: 'North Capitol Rd, Bacolod City',
    costRange: 'Free',
    duration: '30 mins',
    matchScore: 89,
    imageUrl:
        'https://images.unsplash.com/photo-1513635269975-59663e0ac1ad?auto=format&fit=crop&w=900&q=80',
    gradientColors: [Color(0xFF0C4A6E), Color(0xFF1E3A8A)],
  ),
  LocationItem(
    id: 'b3783066-7484-5917-a09b-404974974880',
    name: 'Negros Forest Park',
    description:
        'Conservation center and wildlife sanctuary protecting endangered Negros endemic species.',
    category: 'park',
    vibeTags: ['nature', 'photography', 'wildlife'],
    address: 'South Capitol Rd, Bacolod City',
    costRange: '₱100 – ₱150',
    duration: '60 mins',
    matchScore: 87,
    imageUrl:
        'https://images.unsplash.com/photo-1448375240586-882707db888b?auto=format&fit=crop&w=900&q=80',
    gradientColors: [Color(0xFF14532D), Color(0xFF134E4A)],
  ),
  LocationItem(
    id: 'ee2c8f6e-7a15-5081-b8a3-b43d48d5a83c',
    name: 'Panaad Park and Sports Complex',
    description:
        'Lush eucalyptus-lined park showcasing replica pavilions from every Negros town.',
    category: 'park',
    vibeTags: ['nature', 'photography', 'outdoors'],
    address: 'Brgy. Mansilingan, Bacolod City',
    costRange: 'Free – ₱50',
    duration: '90 mins',
    matchScore: 86,
    imageUrl:
        'https://images.unsplash.com/photo-1519331379826-f10be5486c6f?auto=format&fit=crop&w=900&q=80',
    gradientColors: [Color(0xFF134E4A), Color(0xFF166534)],
  ),
  LocationItem(
    id: 'f52c28a6-cf76-5efa-b0a3-d04f8b15794c',
    name: 'Arima Restaurant',
    description:
        'Refined all-day dining at Park Inn serving elevated Negrense comfort classics.',
    category: 'restaurant',
    vibeTags: ['food', 'relaxing', 'dining'],
    address: 'SM City Bacolod Complex',
    costRange: '₱450 – ₱900',
    duration: '75 mins',
    matchScore: 84,
    imageUrl:
        'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?auto=format&fit=crop&w=900&q=80',
    gradientColors: [Color(0xFF881337), Color(0xFF78350F)],
  ),
];
