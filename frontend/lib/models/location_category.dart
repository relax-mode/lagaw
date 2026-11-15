/// Reuse the catalogue's broad categories across filters, cards and itineraries.
String canonicalLocationCategory(String category) {
  final id = category.trim().toLowerCase();
  return switch (id) {
    'art_gallery' => 'gallery',
    'garden_farm_tourism' => 'park',
    'local_food' || 'seaside_dining' => 'restaurant',
    'cafe_meals' => 'cafe',
    'heritage_viewpoint' => 'heritage',
    'indoor_recreation' ||
    'childrens_play' ||
    'arcade_recreation' ||
    'evening_bowling' => 'recreation',
    'crafts_souvenirs' ||
    'shopping_leisure' ||
    'pasalubong_food' ||
    'bookstore_leisure' => 'shopping',
    'waterpark' || 'coastal_day_resort' => 'resort',
    _ => id,
  };
}

String locationCategoryTitle(String category) {
  final id = canonicalLocationCategory(category);
  return switch (id) {
    '' => 'Spot',
    'recreation' => 'Activities',
    'shopping' => 'Shopping',
    'resort' => 'Resort',
    _ => id
        .split(RegExp(r'[_\s]+'))
        .where((word) => word.isNotEmpty)
        .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
        .join(' '),
  };
}
