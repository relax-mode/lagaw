import 'package:flutter/foundation.dart';

import '../models/trip_plan.dart';
import 'trip_service.dart';

/// The signed-in user's discovery swipes, saves and ratings: restored from
/// `GET /api/v1/interactions` and extended by one `POST` per action (#52).
///
/// Events are append-only: there is no unsave or undo, a left swipe
/// permanently excludes a place from recommendations, and a write is never
/// retried automatically because a retry can record a duplicate. [S4-10]
class DiscoveryInteractions extends ChangeNotifier {
  final TripService _service;

  DiscoveryInteractions(this._service);

  final Set<String> _liked = {};
  final Set<String> _passed = {};
  final Set<String> _saved = {};
  final Map<String, double> _ratings = {};
  final Set<String> _busy = {};

  bool _loading = false;
  bool _loaded = false;
  String? _loadError;

  bool get loading => _loading;
  bool get loaded => _loaded;
  String? get loadError => _loadError;

  bool isSaved(String id) => _saved.contains(id);
  bool isBusy(String id) => _busy.contains(id);
  double? ratingFor(String id) => _ratings[id];

  /// Swiped either way, so the deck skips it.
  bool isSwiped(String id) => _liked.contains(id) || _passed.contains(id);

  /// Liked or saved, and never passed: the user's picks.
  Set<String> get picks => {..._liked, ..._saved}.difference(_passed);
  Set<String> get saved => Set.unmodifiable(_saved);

  /// Reads all history. A failure keeps what is already known.
  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    _loadError = null;
    notifyListeners();
    try {
      final events = await _service.listInteractions();
      _liked.clear();
      _passed.clear();
      _saved.clear();
      _ratings.clear();
      events.forEach(_apply);
      _loaded = true;
    } on TripApiException catch (e) {
      _loadError = e.message;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void _apply(InteractionEvent event) {
    final id = event.locationId;
    switch (event.type) {
      case InteractionType.rightSwipe:
        _liked.add(id);
      case InteractionType.leftSwipe:
        _passed.add(id);
      case InteractionType.save:
        _saved.add(id);
      case InteractionType.rating:
        if (event.rating != null) _ratings[id] = event.rating!;
    }
  }

  Future<void> swipe(String id, {required bool liked}) => _record(
    id,
    liked ? InteractionType.rightSwipe : InteractionType.leftSwipe,
  );

  /// Already-saved places are not saved again.
  Future<void> save(String id) async {
    if (_saved.contains(id)) return;
    await _record(id, InteractionType.save);
  }

  Future<void> rate(String id, int stars) =>
      _record(id, InteractionType.rating, rating: stars.toDouble());

  /// Sends one event. Throws [TripApiException] on failure; local state
  /// changes only after the server confirms.
  Future<void> _record(
    String id,
    InteractionType type, {
    double? rating,
  }) async {
    if (_busy.contains(id)) return;
    _busy.add(id);
    notifyListeners();
    try {
      await _service.recordInteraction(id, type, rating: rating);
      _apply(InteractionEvent(locationId: id, type: type, rating: rating));
    } finally {
      _busy.remove(id);
      notifyListeners();
    }
  }
}

/// User-facing text for a failed discovery write. A response that never
/// arrived may still have been recorded, so it says so instead of retrying.
String describeInteractionFailure(TripApiException e) => e.statusCode == null
    ? '${e.message} It may still have been recorded; reopen the app to check '
          'before trying again.'
    : e.message;
