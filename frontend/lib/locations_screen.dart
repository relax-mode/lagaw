import 'package:flutter/material.dart';
import 'config.dart';
import 'models/location.dart';
import 'screens/trip_create_screen.dart';
import 'screens/trips_tab.dart';
import 'services/api_service.dart';
import 'services/trip_service.dart';
import 'theme.dart';
import 'widgets/bacolod_3d_badges.dart';
import 'widgets/tactile_motion.dart';

enum AppTab { explore, swipe, spots, trips }

enum ApiViewState { live, loading, empty, error }

class LocationsScreen extends StatefulWidget {
  /// Injectable for tests; defaults to the live trip API. [S2-04]
  final TripService? tripService;

  const LocationsScreen({super.key, this.tripService});

  @override
  State<LocationsScreen> createState() => _LocationsScreenState();
}

class _LocationsScreenState extends State<LocationsScreen> {
  AppTab _activeTab = AppTab.explore;
  String _selectedCategory = 'all';
  int _featuredIndex = 0;
  String _searchQuery = '';
  bool _showOnlySaved = false;

  // Swipe Deck State
  int _swipeIndex = 0;
  double _dragOffset = 0.0;
  final Set<String> _savedIds = {
    '1a3bca09-5532-5de6-8587-2440c4e5',
    'f2ccf475-56ea-51a0-a003-70f66d9f85',
  };

  // [S1-04] Live API Fetching & State
  final ApiService _apiService = ApiService();
  late final TripService _tripService = widget.tripService ?? TripService();
  List<LocationItem> _locations = [];
  String _errorMessage = '';
  ApiViewState _apiState = ApiViewState.loading;

  @override
  void initState() {
    super.initState();
    _fetchLocations();
  }

  @override
  void dispose() {
    _apiService.dispose();
    if (widget.tripService == null) _tripService.dispose();
    super.dispose();
  }

  Future<void> _fetchLocations() async {
    setState(() {
      _apiState = ApiViewState.loading;
      _errorMessage = '';
    });

    try {
      final fetched = await _apiService.fetchLocations();
      if (!mounted) return;
      setState(() {
        if (fetched.isEmpty) {
          _apiState = ApiViewState.empty;
          _locations = [];
        } else {
          _locations = fetched;
          _apiState = ApiViewState.live;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _apiState = ApiViewState.error;
      });
    }
  }

  void _useFallbackLocations() {
    setState(() {
      _locations = List.of(kBacolodLocations);
      _apiState = ApiViewState.live;
    });
  }

  /// Opens trip creation; lands on My Trips once a trip is saved. [S2-04]
  Future<void> _planTrip() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => TripCreateScreen(service: _tripService)),
    );
    if (created == true && mounted) {
      setState(() {
        _showOnlySaved = false;
        _activeTab = AppTab.trips;
      });
    }
  }

  List<LocationItem> get _availableLocations {
    if (_apiState == ApiViewState.empty) return const [];
    return _locations.isNotEmpty ? _locations : kBacolodLocations;
  }

  static const List<Map<String, String>> _categories = [
    {'id': 'all', 'label': 'All Spots'},
    {'id': 'cafe', 'label': 'Cafés'},
    {'id': 'heritage', 'label': 'Heritage'},
    {'id': 'park', 'label': 'Parks'},
    {'id': 'gallery', 'label': 'Art & Gallery'},
    {'id': 'restaurant', 'label': 'Dining'},
  ];

  static const Map<String, ({Color bg, Color shadow, Color border, IconData icon})> _categoryThemes = {
    'all': (
      bg: Color(0xFFEA580C), // Sunset Inasal Orange
      shadow: Color(0xFF9A3412),
      border: Color(0xFFFDBA74),
      icon: Icons.explore_rounded,
    ),
    'cafe': (
      bg: Color(0xFFB45309), // Toasted Kape Mocha
      shadow: Color(0xFF78350F),
      border: Color(0xFFFCD34D),
      icon: Icons.coffee_rounded,
    ),
    'heritage': (
      bg: Color(0xFFE11D48), // Cathedral & MassKara Ruby
      shadow: Color(0xFF9F1239),
      border: Color(0xFFFDA4AF),
      icon: Icons.account_balance_rounded,
    ),
    'park': (
      bg: Color(0xFF16A34A), // Sugar Cane Emerald Lime
      shadow: Color(0xFF15803D),
      border: Color(0xFF86EFAC),
      icon: Icons.park_rounded,
    ),
    'gallery': (
      bg: Color(0xFFA855F7), // Ube Piaya Purple
      shadow: Color(0xFF7E22CE),
      border: Color(0xFFD8B4FE),
      icon: Icons.palette_rounded,
    ),
    'restaurant': (
      bg: Color(0xFFF59E0B), // Golden Annatto Roast
      shadow: Color(0xFFB45309),
      border: Color(0xFFFDE047),
      icon: Icons.restaurant_rounded,
    ),
  };

  List<LocationItem> get _filteredLocations {
    if (_apiState == ApiViewState.empty) return const [];
    return _availableLocations.where((loc) {
      if (_showOnlySaved && !_savedIds.contains(loc.id)) {
        return false;
      }
      final matchesCat =
          _selectedCategory == 'all' || loc.category == _selectedCategory;
      final q = _searchQuery.toLowerCase();
      final matchesSearch = q.isEmpty ||
          loc.name.toLowerCase().contains(q) ||
          loc.description.toLowerCase().contains(q) ||
          loc.vibeTags.any((t) => t.toLowerCase().contains(q));
      return matchesCat && matchesSearch;
    }).toList();
  }

  LocationItem _getCarouselItem(int offset) {
    final list =
        _filteredLocations.isNotEmpty ? _filteredLocations : _availableLocations;
    if (list.isEmpty) return kBacolodLocations.first;
    final rawIndex = (_featuredIndex + offset) % list.length;
    final idx = (rawIndex + list.length) % list.length;
    return list[idx];
  }

  void _toggleSave(String id) {
    setState(() {
      if (_savedIds.contains(id)) {
        _savedIds.remove(id);
      } else {
        _savedIds.add(id);
      }
    });
  }

  void _handleSwipe(bool liked) {
    if (_swipeIndex >= _availableLocations.length) return;
    final current = _availableLocations[_swipeIndex];
    setState(() {
      if (liked) {
        _savedIds.add(current.id);
      }
      _swipeIndex++;
      _dragOffset = 0.0;
    });
  }

  void _viewSavedLocations() {
    setState(() {
      _showOnlySaved = true;
      _selectedCategory = 'all';
      _searchQuery = '';
      _activeTab = AppTab.spots;
    });
  }

  // Derive predicted traveler persona from user's liked spots tags
  String get _predictedPersona {
    final likedSpots =
        _availableLocations.where((s) => _savedIds.contains(s.id)).toList();
    if (likedSpots.isEmpty) return 'Curious Bacolod Traveler';

    final tagCounts = <String, int>{};
    for (final spot in likedSpots) {
      for (final tag in spot.vibeTags) {
        tagCounts[tag] = (tagCounts[tag] ?? 0) + 1;
      }
    }

    final topTags = tagCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final topKey = topTags.isNotEmpty ? topTags.first.key : '';
    switch (topKey) {
      case 'cafe':
      case 'sweet':
        return 'Café & Pastry Connoisseur';
      case 'heritage':
      case 'architecture':
        return 'Historic Sugar Heritage Explorer';
      case 'nature':
      case 'relaxing':
        return 'Scenic Nature & Slow Traveler';
      case 'art':
      case 'creative':
        return 'Art & Creative District Hunter';
      case 'food':
      case 'dining':
        return 'Negrense Culinary Enthusiast';
      default:
        return 'Bacolod City Explorer';
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth >= 768;
    final contentMaxWidth = isWide ? 1040.0 : 430.0;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppTheme.skyTop,
              AppTheme.skyMid,
              AppTheme.skyBottom,
            ],
            stops: [0.0, 0.48, 1.0],
          ),
        ),
        child: Stack(
          children: [
            // 1. Large Flexible Sun Glowing on the Top-Left Screen Edge
            Positioned(
              top: isWide ? -100 : -70,
              left: isWide ? -100 : -70,
              child: IgnorePointer(
                child: Container(
                  width: isWide ? 340 : 250,
                  height: isWide ? 340 : 250,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      center: Alignment.center,
                      radius: 0.8,
                      colors: [
                        Color(0xFFFFFBEB),
                        Color(0xFFFEF08A),
                        Color(0xFFF59E0B),
                        Color(0x00F59E0B),
                      ],
                      stops: [0.0, 0.35, 0.7, 1.0],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x66F59E0B),
                        blurRadius: 110,
                        spreadRadius: 40,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // 2. Scattered 3D Bacolod Badges around the Screen (Non-overlapping, decorative)
            if (isWide) ...[
              // San Sebastian Cathedral (Upper left landmark)
              const Positioned(
                top: 160,
                left: 32,
                child: IgnorePointer(
                  child: Cathedral3DBadge(size: 125),
                ),
              ),
              // Bacolod Chicken Inasal on a Stick (Lower left savory classic)
              const Positioned(
                top: 460,
                left: 28,
                child: IgnorePointer(
                  child: Inasal3DBadge(size: 130),
                ),
              ),
              // MassKara Festival Smiling Mask (Upper right festive icon)
              const Positioned(
                top: 80,
                right: 36,
                child: IgnorePointer(
                  child: MassKara3DBadge(size: 135),
                ),
              ),
              // Purple Ube Piaya Badge (Mid right sweet delicacy)
              const Positioned(
                top: 310,
                right: 32,
                child: IgnorePointer(
                  child: Piaya3DBadge(size: 115),
                ),
              ),
              // Iced Bacolod Kape Cup (Lower right coffee culture)
              const Positioned(
                bottom: 70,
                right: 42,
                child: IgnorePointer(
                  child: Coffee3DBadge(size: 120),
                ),
              ),
            ] else ...[
              // Mobile festive ambient accents (non-blocking edge accents)
              const Positioned(
                top: 72,
                right: -8,
                child: IgnorePointer(
                  child: MassKara3DBadge(size: 68),
                ),
              ),
              const Positioned(
                top: 290,
                left: -12,
                child: IgnorePointer(
                  child: Piaya3DBadge(size: 60),
                ),
              ),
              const Positioned(
                bottom: 120,
                right: -10,
                child: IgnorePointer(
                  child: Inasal3DBadge(size: 66),
                ),
              ),
            ],

            // 3. Main Center Content Container
            SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: contentMaxWidth),
                  child: Stack(
                    children: [
                      Column(
                        children: [
                          const SizedBox(height: 8),
                          AnimatedSize(
                            duration: TactileMotion.tab,
                            curve: TactileMotion.curve,
                            alignment: Alignment.topCenter,
                            child: _activeTab == AppTab.explore
                                ? Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: _buildLagawHero(isWide: isWide),
                                  )
                                : const SizedBox(width: double.infinity),
                          ),
                          _buildTopGlassHeader(isWide: isWide),
                          Expanded(
                            child: SingleChildScrollView(
                              padding: EdgeInsets.fromLTRB(
                                isWide ? 32 : 20,
                                14,
                                isWide ? 32 : 20,
                                isWide ? 40 : 110,
                              ),
                              child: TactilePageSwitcher(
                                pageKey: (_activeTab, _showOnlySaved),
                                child: _buildActiveTabContent(isWide: isWide),
                              ),
                            ),
                          ),
                        ],
                      ),

                      // Bottom Floating Glass Dock (Mobile only)
                      if (!isWide)
                        Positioned(
                          left: 20,
                          right: 20,
                          bottom: 16,
                          child: _buildBottomGlassDock(),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Top Lagaw Hero Brand Title (Minimal & Fun Bold Lowercase)
  Widget _buildLagawHero({required bool isWide}) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isWide ? 32 : 20,
        vertical: isWide ? 4 : 2,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                'lagaw',
                style: TextStyle(
                  fontFamily: 'Outfit',
                  fontFamilyFallback: const [
                    'Plus Jakarta Sans',
                    'Fredoka',
                    'system-ui',
                    'sans-serif',
                  ],
                  fontSize: isWide ? 54 : 42,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: -1.6,
                  height: 1.0,
                  shadows: const [
                    Shadow(
                      color: Color(0x33000000),
                      blurRadius: 14,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 3),
              Container(
                width: isWide ? 8 : 6.5,
                height: isWide ? 8 : 6.5,
                decoration: const BoxDecoration(
                  color: Color(0xFFF59E0B),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x66F59E0B),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          const Text(
            'Swipe your vibe, skip the generic lists,\nand tour Bacolod your way.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              color: Color(0xEEFFFFFF),
              fontWeight: FontWeight.w500,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  /// Top 3D Vector Header (Crisp solid card with 3D tactile buttons)
  Widget _buildTopGlassHeader({required bool isWide}) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isWide ? 32 : 20),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(36),
          border: Border.all(color: const Color(0xFFE2E8F0), width: 2.2),
          boxShadow: const [
            BoxShadow(
              color: Color(0xFFCBD5E1),
              offset: Offset(0, 4.5),
              blurRadius: 0, // Sharp 3D tactile bevel
            ),
            BoxShadow(
              color: Color(0x180F172A),
              offset: Offset(0, 8),
              blurRadius: 16,
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            // 3D Avatar Badge
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFFBBF24), Color(0xFFF59E0B), Color(0xFFEA580C)],
                ),
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0xFFB45309),
                    offset: Offset(0, 2.5),
                    blurRadius: 0,
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: const Text(
                'R',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  fontFamily: 'Outfit',
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.location_on, size: 12, color: Color(0xFF0284C7)),
                      SizedBox(width: 3),
                      Flexible(
                        child: Text(
                          'Bacolod City • 28° Sunny',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.slateMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    isWide ? 'Bacolod City — City of Smiles' : 'Maayong Aga, Roel!',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.slateDark,
                      fontFamily: 'Outfit',
                    ),
                  ),
                ],
              ),
            ),

            // Web Navigation Bar in Header (Home & Spots Directory)
            if (isWide) ...[
              _buildWebNavButton(
                icon: Icons.explore_rounded,
                label: 'Home',
                tab: AppTab.explore,
              ),
              const SizedBox(width: 8),
              _buildWebNavButton(
                icon: Icons.layers_rounded,
                label: 'Spots Directory',
                tab: AppTab.spots,
                onTapOverride: () {
                  setState(() {
                    _showOnlySaved = false;
                    _selectedCategory = 'all';
                    _activeTab = AppTab.spots;
                  });
                },
              ),
              const SizedBox(width: 8),
              _buildWebNavButton(
                icon: Icons.luggage_rounded,
                label: 'My Trips',
                tab: AppTab.trips,
                // Icon-only until there is room for a third label. [S2-04]
                iconOnly: MediaQuery.of(context).size.width < 1040,
              ),
              const SizedBox(width: 8),
            ],

            // 3D Swipe Deck Icon Button
            Vector3DButton(
              onTap: () => setState(() => _activeTab = AppTab.swipe),
              backgroundColor: _activeTab == AppTab.swipe
                  ? const Color(0xFFF59E0B)
                  : const Color(0xFFFFFBEB),
              shadowColor: _activeTab == AppTab.swipe
                  ? const Color(0xFFB45309)
                  : const Color(0xFFFDE68A),
              borderColor: _activeTab == AppTab.swipe
                  ? const Color(0xFFFDE68A)
                  : const Color(0xFFFEF3C7),
              borderRadius: 18,
              padding: const EdgeInsets.all(8),
              depth: 3.0,
              child: Icon(
                Icons.style_rounded,
                size: 18,
                color: _activeTab == AppTab.swipe
                    ? Colors.white
                    : const Color(0xFFB45309),
              ),
            ),
            const SizedBox(width: 8),

            // 3D Search Button
            Vector3DButton(
              onTap: () {
                setState(() {
                  _showOnlySaved = false;
                  _activeTab = AppTab.spots;
                });
              },
              backgroundColor: const Color(0xFFF8FAFC),
              shadowColor: const Color(0xFFCBD5E1),
              borderColor: const Color(0xFFE2E8F0),
              borderRadius: 18,
              padding: const EdgeInsets.all(8),
              depth: 3.0,
              child: const Icon(
                Icons.search_rounded,
                size: 18,
                color: AppTheme.slateDark,
              ),
            ),
            const SizedBox(width: 8),

            // 3D Saved Heart Button
            TactilePressable(
              onTap: _viewSavedLocations,
              child: Tooltip(
                message: 'View Itinerary (${_savedIds.length})',
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: _showOnlySaved && _activeTab == AppTab.spots
                            ? const Color(0xFFE11D48)
                            : const Color(0xFFFFF1F2),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _showOnlySaved && _activeTab == AppTab.spots
                              ? const Color(0xFF9F1239)
                              : const Color(0xFFFECDD3),
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _showOnlySaved && _activeTab == AppTab.spots
                                ? const Color(0xFF9F1239)
                                : const Color(0xFFFDA4AF),
                            offset: const Offset(0, 3),
                            blurRadius: 0,
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.favorite,
                        size: 18,
                        color: _showOnlySaved && _activeTab == AppTab.spots
                            ? Colors.white
                            : const Color(0xFFE11D48),
                      ),
                    ),
                    Positioned(
                      top: -5,
                      right: -5,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.slateDark,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        child: Text(
                          '${_savedIds.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebNavButton({
    required IconData icon,
    required String label,
    required AppTab tab,
    VoidCallback? onTapOverride,
    bool iconOnly = false,
  }) {
    final isActive = _activeTab == tab && !_showOnlySaved;
    final button = Vector3DButton(
      onTap: onTapOverride ??
          () => setState(() {
                _showOnlySaved = false;
                _activeTab = tab;
              }),
      backgroundColor: isActive
          ? (tab == AppTab.explore ? const Color(0xFF0F172A) : const Color(0xFF2563EB))
          : const Color(0xFFF8FAFC),
      shadowColor: isActive
          ? (tab == AppTab.explore ? const Color(0xFF020617) : const Color(0xFF1D4ED8))
          : const Color(0xFFCBD5E1),
      borderColor: isActive
          ? (tab == AppTab.explore ? const Color(0xFF334155) : const Color(0xFF60A5FA))
          : const Color(0xFFE2E8F0),
      borderRadius: 20,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      depth: 3.0,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 15,
            color: isActive ? Colors.white : AppTheme.slateDark,
          ),
          if (!iconOnly) ...[
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w900,
                color: isActive ? Colors.white : AppTheme.slateDark,
                fontFamily: 'Outfit',
              ),
            ),
          ],
        ],
      ),
    );
    return iconOnly ? Tooltip(message: label, child: button) : button;
  }

  Widget _buildActiveTabContent({required bool isWide}) {
    switch (_activeTab) {
      case AppTab.explore:
        return _buildLandingTab(isWide: isWide);
      case AppTab.swipe:
        return _buildSwipeTab(isWide: isWide);
      case AppTab.spots:
        return _buildSpotsDirectoryTab(isWide: isWide);
      case AppTab.trips:
        return TripsTab(service: _tripService, isWide: isWide);
    }
  }

  // ===========================================================================
  // TAB 1: LANDING & 3-CARD FANNED EXPLORER
  // ===========================================================================
  Widget _buildLandingTab({required bool isWide}) {
    final leftSpot = _getCarouselItem(-1);
    final centerSpot = _getCarouselItem(0);
    final rightSpot = _getCarouselItem(1);

    return Column(
      children: [
        const SizedBox(height: 4),

        // Frosted Glass Category Pills
        _buildCategoryPills(),
        const SizedBox(height: 18),

        if (isWide)
          // Wide Web Layout: Side-by-Side Carousel + Bento Dashboard
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left: 3-Card Fanned Carousel + CTA
              Expanded(
                flex: 5,
                child: Column(
                  children: [
                    SizedBox(
                      height: 280,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Transform.translate(
                            offset: const Offset(-88, 12),
                            child: Transform.rotate(
                              angle: -0.20,
                              child: TactilePressable(
                                onTap: () => setState(() => _featuredIndex--),
                                child: _buildSideFanCard(leftSpot),
                              ),
                            ),
                          ),
                          Transform.translate(
                            offset: const Offset(88, 12),
                            child: Transform.rotate(
                              angle: 0.20,
                              child: TactilePressable(
                                onTap: () => setState(() => _featuredIndex++),
                                child: _buildSideFanCard(rightSpot),
                              ),
                            ),
                          ),
                          TactilePageSwitcher(
                            pageKey: centerSpot.id,
                            child: _buildCenterFanCard(centerSpot),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Vector3DButton(
                      onTap: () => setState(() => _activeTab = AppTab.swipe),
                      backgroundColor: const Color(0xFFEA580C), // Inasal Sunset Orange
                      shadowColor: const Color(0xFF9A3412),
                      borderColor: const Color(0xFFFDBA74),
                      borderRadius: 28,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      depth: 4.5,
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Start Matching Spots',
                            style: TextStyle(
                              fontFamily: 'Outfit',
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                              color: Colors.white,
                              letterSpacing: 0.3,
                            ),
                          ),
                          SizedBox(width: 8),
                          Icon(Icons.style_rounded, size: 18, color: Colors.white),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildPlanTripButton(),
                  ],
                ),
              ),
              const SizedBox(width: 24),

              // Right: Bento Stats & Spot Directory Spotlight
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildBentoStats(isWide: true),
                    const SizedBox(height: 16),
                    TactilePressable(
                      onTap: () {
                        setState(() {
                          _showOnlySaved = false;
                          _selectedCategory = 'all';
                          _searchQuery = '';
                          _activeTab = AppTab.spots;
                        });
                      },
                      child: GlassContainer(
                        borderRadius: 20,
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Explore All Spots',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w900,
                                    color: AppTheme.slateDark,
                                  ),
                                ),
                                Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 18,
                                  color: AppTheme.primaryBlue,
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Browse categories, search Bacolod landmarks, and view all curated spots.',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.slateMuted,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                '#heritage',
                                '#cafes',
                                '#parks',
                                '#galleries',
                                '#dining',
                              ].map((tag) {
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0x30FFFFFF),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: const Color(0x50FFFFFF),
                                    ),
                                  ),
                                  child: Text(
                                    tag,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.slateDark,
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          )
        else ...[
          // Mobile Layout: Stacked 3-Card Carousel + CTA + Bento Stats
          SizedBox(
            height: 268,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Transform.translate(
                  offset: const Offset(-78, 12),
                  child: Transform.rotate(
                    angle: -0.20,
                    child: TactilePressable(
                      onTap: () => setState(() => _featuredIndex--),
                      child: _buildSideFanCard(leftSpot),
                    ),
                  ),
                ),
                Transform.translate(
                  offset: const Offset(78, 12),
                  child: Transform.rotate(
                    angle: 0.20,
                    child: TactilePressable(
                      onTap: () => setState(() => _featuredIndex++),
                      child: _buildSideFanCard(rightSpot),
                    ),
                  ),
                ),
                TactilePageSwitcher(
                  pageKey: centerSpot.id,
                  child: _buildCenterFanCard(centerSpot),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Vector3DButton(
            onTap: () => setState(() => _activeTab = AppTab.swipe),
            backgroundColor: const Color(0xFFEA580C),
            shadowColor: const Color(0xFF9A3412),
            borderColor: const Color(0xFFFDBA74),
            borderRadius: 28,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
            depth: 4.0,
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Start Matching Spots',
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    color: Colors.white,
                  ),
                ),
                SizedBox(width: 8),
                Icon(Icons.style_rounded, size: 16, color: Colors.white),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _buildPlanTripButton(),
          const SizedBox(height: 14),
          _buildBentoStats(isWide: false),
        ],
      ],
    );
  }

  /// Secondary Home CTA into trip creation. [S2-04]
  Widget _buildPlanTripButton() {
    return Vector3DButton(
      key: const ValueKey('home-plan-trip'),
      onTap: _planTrip,
      backgroundColor: Colors.white,
      shadowColor: const Color(0xFFCBD5E1),
      borderColor: const Color(0xFFE2E8F0),
      borderRadius: 28,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      depth: 3.5,
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.luggage_rounded, size: 17, color: Color(0xFFEA580C)),
          SizedBox(width: 8),
          Text(
            'Plan a Trip',
            style: TextStyle(
              fontFamily: 'Outfit',
              fontWeight: FontWeight.w900,
              fontSize: 14,
              color: AppTheme.slateDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryPills() {
    final gutter = MediaQuery.of(context).size.width >= 768 ? 32.0 : 20.0;
    // The row stays 44px tall, but painting may spill past it so the pills'
    // bevel shadows and hover/press motion are not sliced, and pills scroll
    // out to the screen edge instead of being hard-cut at the page gutter.
    return SizedBox(
      height: 44,
      child: ClipRect(
        clipper: _BleedClipper(horizontal: gutter, vertical: 16),
        child: ListView.separated(
          clipBehavior: Clip.none,
          scrollDirection: Axis.horizontal,
          itemCount: _categories.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final cat = _categories[index];
            final catId = cat['id']!;
            final isSelected = _selectedCategory == catId;
            final theme = _categoryThemes[catId] ?? _categoryThemes['all']!;

            return Vector3DButton(
              onTap: () {
                setState(() {
                  _selectedCategory = catId;
                  _featuredIndex = 0;
                });
              },
              backgroundColor: isSelected ? theme.bg : Colors.white,
              shadowColor: isSelected ? theme.shadow : const Color(0xFFCBD5E1),
              borderColor: isSelected ? Colors.white : const Color(0xFFE2E8F0),
              borderRadius: 24,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              depth: isSelected ? 3.5 : 2.5,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    theme.icon,
                    size: 16,
                    color: isSelected ? Colors.white : theme.bg,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    cat['label']!,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: isSelected ? FontWeight.w900 : FontWeight.w800,
                      fontFamily: 'Outfit',
                      color: isSelected ? Colors.white : AppTheme.slateDark,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildBentoStats({required bool isWide}) {
    return Row(
      children: [
        Expanded(
          child: TactilePressable(
            onTap: () {
              setState(() {
                _showOnlySaved = false;
                _selectedCategory = 'all';
                _searchQuery = '';
                _activeTab = AppTab.spots;
              });
            },
            child: GlassContainer(
              borderRadius: 20,
              padding: const EdgeInsets.all(12),
              tintColor: const Color(0xB3FFFFFF),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          'Bacolod Spots',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.slateMuted,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.explore_outlined,
                        size: 16,
                        color: Color(0xFF0284C7),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_availableLocations.length}',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.slateDark,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Active Destinations',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.slateMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TactilePressable(
            onTap: _viewSavedLocations,
            child: GlassContainer(
              borderRadius: 20,
              padding: const EdgeInsets.all(12),
              tintColor: const Color(0xB3FFFFFF),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          'Trip Matches',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.slateMuted,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.favorite,
                        size: 16,
                        color: Color(0xFFF43F5E),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_savedIds.length}',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.slateDark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: _availableLocations.isEmpty
                          ? 0.1
                          : (_savedIds.length / _availableLocations.length)
                              .clamp(0.1, 1.0),
                      minHeight: 6,
                      backgroundColor: const Color(0xFFE2E8F0),
                      color: const Color(0xFF10B981),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSideFanCard(LocationItem spot) {
    return GlassContainer(
      borderRadius: 24,
      padding: const EdgeInsets.all(8),
      tintColor: const Color(0x66FFFFFF),
      child: SizedBox(
        width: 138,
        height: 196,
        child: Column(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(
                      spot.imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          Container(color: spot.gradientColors.first),
                    ),
                    Container(color: const Color(0x44000000)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              spot.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AppTheme.slateDark,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCenterFanCard(LocationItem spot) {
    final isSaved = _savedIds.contains(spot.id);

    return GlassContainer(
      borderRadius: 28,
      padding: const EdgeInsets.all(10),
      tintColor: const Color(0xD9FFFFFF),
      borderColor: Colors.white,
      child: SizedBox(
        width: 196,
        height: 236,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(
                      spot.imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: spot.gradientColors),
                        ),
                      ),
                    ),
                    Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x22000000), Color(0xCC000000)],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 10,
                      left: 10,
                      right: 10,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0x55FFFFFF),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              spot.category.toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          TactilePressable(
                            onTap: () => _toggleSave(spot.id),
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 260),
                              switchInCurve: Curves.elasticOut,
                              transitionBuilder: (child, animation) =>
                                  ScaleTransition(scale: animation, child: child),
                              child: KeyedSubtree(
                                key: ValueKey(isSaved),
                                child: Icon(
                                  isSaved ? Icons.favorite : Icons.favorite_border,
                                  size: 18,
                                  color: isSaved
                                      ? const Color(0xFFF43F5E)
                                      : Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      bottom: 10,
                      left: 10,
                      right: 10,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            spot.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              height: 1.15,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${spot.duration} • ${spot.costRange}',
                            style: const TextStyle(
                              color: Color(0xDDFFFFFF),
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (spot.vibeTags.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(right: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0F2FE),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '#${spot.vibeTags.first}',
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF075985),
                      ),
                    ),
                  ),
                Text(
                  '${spot.matchScore}%',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF047857),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // TAB 2: TINDER-STYLE INTERACTIVE SWIPE DECK WITH DRAG ANIMATION
  // ===========================================================================
  Widget _buildSwipeTab({required bool isWide}) {
    // Deck Complete State -> Show Fun Cohesive Itinerary Screen
    if (_swipeIndex >= _availableLocations.length) {
      return _buildItineraryCompletionView(isWide: isWide);
    }

    final spot = _availableLocations[_swipeIndex];

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: isWide ? 460 : 430),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Swipe Your Vibe',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'Drag right to like • Drag left to pass',
                      style: TextStyle(fontSize: 12, color: Colors.white),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0x40FFFFFF),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_swipeIndex + 1} / ${_availableLocations.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Interactive Dragging Card with Like / Nope Stamps
            GestureDetector(
              onPanUpdate: (details) {
                setState(() {
                  _dragOffset += details.delta.dx;
                });
              },
              onPanEnd: (details) {
                if (_dragOffset > 90 || details.velocity.pixelsPerSecond.dx > 400) {
                  _handleSwipe(true);
                } else if (_dragOffset < -90 ||
                    details.velocity.pixelsPerSecond.dx < -400) {
                  _handleSwipe(false);
                } else {
                  setState(() {
                    _dragOffset = 0.0;
                  });
                }
              },
              child: Transform.translate(
                offset: Offset(_dragOffset, 0),
                child: Transform.rotate(
                  angle: _dragOffset * 0.0009,
                  child: Stack(
                    children: [
                      GlassContainer(
                        borderRadius: 28,
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(22),
                              child: SizedBox(
                                height: isWide ? 260 : 230,
                                width: double.infinity,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Image.network(
                                      spot.imageUrl,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => Container(
                                          color: spot.gradientColors.first),
                                    ),
                                    Container(
                                      decoration: const BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [
                                            Color(0x22000000),
                                            Color(0xCC000000)
                                          ],
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      top: 12,
                                      left: 12,
                                      right: 12,
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0x55FFFFFF),
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                            child: Text(
                                              spot.category.toUpperCase(),
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 10,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF10B981),
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                            child: Text(
                                              '${spot.matchScore}% Match',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 10,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Positioned(
                                      bottom: 12,
                                      left: 12,
                                      right: 12,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            spot.name,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 20,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            spot.address,
                                            style: const TextStyle(
                                              color: Color(0xEEFFFFFF),
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              spot.description,
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppTheme.slateDark,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Budget: ${spot.costRange}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF047857),
                                  ),
                                ),
                                Text(
                                  'Typical visit: ${spot.duration}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF0369A1),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // Centered Swipe Feedback Indicator (Noticeable yet clean & balanced)
                      if (_dragOffset.abs() > 15)
                        Positioned.fill(
                          child: Center(
                            child: Opacity(
                              opacity: ((_dragOffset.abs() - 15) / 80).clamp(0.0, 0.92),
                              child: Transform.scale(
                                scale: (0.88 + (_dragOffset.abs() / 320)).clamp(0.88, 1.12),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 22,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _dragOffset > 0
                                        ? const Color(0xEE10B981)
                                        : const Color(0xEEF43F5E),
                                    borderRadius: BorderRadius.circular(28),
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 2.5,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: _dragOffset > 0
                                            ? const Color(0x5510B981)
                                            : const Color(0x55F43F5E),
                                        blurRadius: 20,
                                        spreadRadius: 2,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        _dragOffset > 0
                                            ? Icons.favorite_rounded
                                            : Icons.close_rounded,
                                        color: Colors.white,
                                        size: 26,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        _dragOffset > 0 ? 'LIKE' : 'PASS',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 18,
                                          letterSpacing: 1.4,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),

            // Action Buttons (3D Vector Illustration style)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Vector3DButton(
                  onTap: () => _handleSwipe(false),
                  backgroundColor: Colors.white,
                  shadowColor: const Color(0xFFFDA4AF),
                  borderColor: const Color(0xFFF43F5E),
                  borderRadius: 34,
                  padding: const EdgeInsets.all(16),
                  depth: 5.0,
                  child: const Icon(
                    Icons.close_rounded,
                    size: 32,
                    color: Color(0xFFF43F5E),
                  ),
                ),
                const SizedBox(width: 28),
                Vector3DButton(
                  onTap: () => _handleSwipe(true),
                  backgroundColor: const Color(0xFF10B981),
                  shadowColor: const Color(0xFF047857),
                  borderColor: const Color(0xFF6EE7B7),
                  borderRadius: 34,
                  padding: const EdgeInsets.all(16),
                  depth: 5.0,
                  child: const Icon(
                    Icons.favorite_rounded,
                    size: 32,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Itinerary Completion View when all 10 cards are swiped
  Widget _buildItineraryCompletionView({required bool isWide}) {
    final matchedSpots =
        _availableLocations.where((loc) => _savedIds.contains(loc.id)).toList();

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: isWide ? 520 : 400),
        child: Column(
          children: [
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 24,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: const MassKara3DBadge(size: 68),
            ),
            const SizedBox(height: 16),
            const Text(
              'Deck Completed!',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0x40FFFFFF),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white70),
              ),
              child: Text(
                'Predicted Vibe: $_predictedPersona',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'You selected ${matchedSpots.length} destinations for your customized Bacolod trip.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Colors.white70),
            ),
            const SizedBox(height: 20),

            // Glassmorphic Itinerary Preview
            GlassContainer(
              borderRadius: 24,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Your Trip Itinerary',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.slateDark,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDBEAFE),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${matchedSpots.length} Spots',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.primaryBlue,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (matchedSpots.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: Text(
                          'No spots saved yet. Swipe again to like destinations!',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.slateMuted,
                          ),
                        ),
                      ),
                    )
                  else
                    ...matchedSpots.take(4).map((s) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.check_circle_rounded,
                              size: 16,
                              color: Color(0xFF10B981),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                s.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.slateDark,
                                ),
                              ),
                            ),
                            Text(
                              s.costRange,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppTheme.slateMuted,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  if (matchedSpots.length > 4)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '+ ${matchedSpots.length - 4} more spots saved',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primaryBlue,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Buttons
            Vector3DButton(
              onTap: _viewSavedLocations,
              backgroundColor: const Color(0xFF2563EB),
              shadowColor: const Color(0xFF1D4ED8),
              borderColor: const Color(0xFF60A5FA),
              borderRadius: 28,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              depth: 4.5,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.map_rounded, size: 18, color: Colors.white),
                  SizedBox(width: 8),
                  Text(
                    'View Your Itinerary',
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _swipeIndex = 0;
                  _dragOffset = 0.0;
                });
              },
              icon: const Icon(Icons.refresh_rounded, size: 16, color: Colors.white),
              label: const Text(
                'Restart Swipe Deck',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // TAB 3: [S1-03 & S1-04] LOCATIONS DIRECTORY + 4 STATES
  // ===========================================================================
  Widget _buildSpotsDirectoryTab({required bool isWide}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      _showOnlySaved ? 'Your Itinerary' : 'Explore Bacolod',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        fontFamily: 'Outfit',
                      ),
                    ),
                    if (_showOnlySaved) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF43F5E),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${_filteredLocations.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  _showOnlySaved
                      ? 'Destinations curated for your customized Bacolod trip'
                      : 'Showing ${_filteredLocations.length} destinations',
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                ),
              ],
            ),
            Row(
              children: [
                if (_showOnlySaved)
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _showOnlySaved = false;
                        _selectedCategory = 'all';
                        _searchQuery = '';
                      });
                    },
                    icon: const Icon(Icons.arrow_back_rounded,
                        size: 14, color: Colors.white),
                    label: const Text(
                      'All Spots',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                PopupMenuButton<ApiViewState>(
                  initialValue: _apiState,
                  onSelected: (st) {
                    if (st == ApiViewState.live) {
                      _fetchLocations();
                    } else {
                      setState(() => _apiState = st);
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: ApiViewState.live,
                      child: Text('Live API (${_availableLocations.length})'),
                    ),
                    const PopupMenuItem(
                      value: ApiViewState.loading,
                      child: Text('State: Loading'),
                    ),
                    const PopupMenuItem(
                      value: ApiViewState.empty,
                      child: Text('State: Empty'),
                    ),
                    const PopupMenuItem(
                      value: ApiViewState.error,
                      child: Text('State: Error + Retry'),
                    ),
                  ],
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0x40FFFFFF),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.tune_rounded, size: 14, color: Colors.white),
                        SizedBox(width: 4),
                        Text(
                          'Test States',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Search Field
        GlassContainer(
          borderRadius: 18,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          child: TextField(
            onChanged: (val) => setState(() => _searchQuery = val),
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              icon: const Icon(Icons.search_rounded, size: 18),
              hintText: _showOnlySaved
                  ? 'Search within your itinerary...'
                  : 'Search Calea, heritage, coffee, nature...',
              border: InputBorder.none,
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Category Pills Filter th Spots Directory
        _buildCategoryPills(),
        const SizedBox(height: 14),

        // State 1: Loading (Centered middle of screen, no card)
        if (_apiState == ApiViewState.loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 60, horizontal: 20),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 44,
                    height: 44,
                    child: CircularProgressIndicator(
                      strokeWidth: 3.5,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                  SizedBox(height: 18),
                  Text(
                    'Fetching Bacolod Locations...',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      fontFamily: 'Outfit',
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Loading curated spots and travel recommendations.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          ),

        // State 2: Error + Retry (Centered middle of screen, no card)
        if (_apiState == ApiViewState.error)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 20),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 52,
                    color: Color(0xFFFFD1D9),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Unable to Reach Bacolod Locations',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      fontFamily: 'Outfit',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _errorMessage.isNotEmpty
                        ? 'Backend connection error.\nEndpoint: ${AppConfig.locationsEndpoint}'
                        : 'Could not connect to ${AppConfig.locationsEndpoint}. Please make sure the FastAPI server is running.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    alignment: WrapAlignment.center,
                    children: [
                      Vector3DButton(
                        onTap: _fetchLocations,
                        backgroundColor: Colors.white,
                        shadowColor: const Color(0xFFCBD5E1),
                        borderColor: const Color(0xFFE2E8F0),
                        borderRadius: 24,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 12,
                        ),
                        depth: 3.5,
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.refresh_rounded,
                              size: 18,
                              color: AppTheme.slateDark,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Retry Connection',
                              style: TextStyle(
                                fontFamily: 'Outfit',
                                fontWeight: FontWeight.w900,
                                fontSize: 14,
                                color: AppTheme.slateDark,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Vector3DButton(
                        onTap: _useFallbackLocations,
                        backgroundColor: const Color(0xFFFEF3C7),
                        shadowColor: const Color(0xFFD97706),
                        borderColor: const Color(0xFFFDE68A),
                        borderRadius: 24,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        depth: 3.5,
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.explore_rounded,
                              size: 18,
                              color: Color(0xFF92400E),
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Use Sample Spots',
                              style: TextStyle(
                                fontFamily: 'Outfit',
                                fontWeight: FontWeight.w900,
                                fontSize: 14,
                                color: Color(0xFF92400E),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

        // State 3: Empty State (When viewing saved spots or empty filter)
        if (_apiState == ApiViewState.empty ||
            (_apiState == ApiViewState.live && _filteredLocations.isEmpty))
          if (_showOnlySaved)
            // Center Screen Text View for Empty Itinerary (No Card)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 20),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.favorite_border_rounded,
                      size: 52,
                      color: Colors.white70,
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Your Itinerary is Empty',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        fontFamily: 'Outfit',
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Swipe right on destinations in the Swipe Deck\nor tap the heart on any spot to build your Bacolod itinerary.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white70,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Vector3DButton(
                      onTap: () {
                        setState(() {
                          _activeTab = AppTab.swipe;
                        });
                      },
                      backgroundColor: Colors.white,
                      shadowColor: const Color(0xFFCBD5E1),
                      borderColor: const Color(0xFFE2E8F0),
                      borderRadius: 24,
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                      depth: 3.5,
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.style_rounded, size: 18, color: AppTheme.slateDark),
                          SizedBox(width: 8),
                          Text(
                            'Build Your Itinerary',
                            style: TextStyle(
                              fontFamily: 'Outfit',
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                              color: AppTheme.slateDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            // Center Screen Text View for Empty Search / Filter (No Card)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 20),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.explore_off_outlined,
                      size: 52,
                      color: Colors.white70,
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'No Matching Locations Found',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        fontFamily: 'Outfit',
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Try resetting your search query or category filters.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Vector3DButton(
                      onTap: () {
                        setState(() {
                          _showOnlySaved = false;
                          _selectedCategory = 'all';
                          _searchQuery = '';
                          _apiState = ApiViewState.live;
                        });
                      },
                      backgroundColor: Colors.white,
                      shadowColor: const Color(0xFFCBD5E1),
                      borderColor: const Color(0xFFE2E8F0),
                      borderRadius: 24,
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                      depth: 3.5,
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.refresh_rounded, size: 18, color: AppTheme.slateDark),
                          SizedBox(width: 8),
                          Text(
                            'Reset Filters',
                            style: TextStyle(
                              fontFamily: 'Outfit',
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                              color: AppTheme.slateDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

        // State 4: Live Cards List (Responsive Web Grid or Mobile List)
        if (_apiState == ApiViewState.live && _filteredLocations.isNotEmpty)
          if (isWide)
            // Desktop / Web Responsive Grid Layout
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                for (final (i, item) in _filteredLocations.indexed)
                  FadeSlideIn(
                    key: ValueKey(item.id),
                    index: i,
                    child: TactilePressable(child: _buildWebSpotCard(item)),
                  ),
              ],
            )
          else
            // Mobile Vertical List Layout
            for (final (i, item) in _filteredLocations.indexed)
              FadeSlideIn(
                key: ValueKey(item.id),
                index: i,
                child: TactilePressable(
                  hoverLift: 2,
                  child: _buildMobileSpotCard(item),
                ),
              ),
      ],
    );
  }

  /// Mobile Compact Spot Card
  Widget _buildMobileSpotCard(LocationItem item) {
    final isSaved = _savedIds.contains(item.id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassContainer(
        borderRadius: 20,
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.network(
                item.imageUrl,
                width: 74,
                height: 74,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  width: 74,
                  height: 74,
                  color: item.gradientColors.first,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.slateDark,
                          ),
                        ),
                      ),
                      TactilePressable(
                        onTap: () => _toggleSave(item.id),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 260),
                          switchInCurve: Curves.elasticOut,
                          transitionBuilder: (child, animation) =>
                              ScaleTransition(scale: animation, child: child),
                          child: KeyedSubtree(
                            key: ValueKey(isSaved),
                            child: Icon(
                              isSaved ? Icons.favorite : Icons.favorite_border,
                              size: 18,
                              color: isSaved
                                  ? const Color(0xFFF43F5E)
                                  : AppTheme.slateMuted,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.slateMuted,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        item.category.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0284C7),
                        ),
                      ),
                      Text(
                        item.costRange,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.slateDark,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Web Glassmorphic Spot Card
  Widget _buildWebSpotCard(LocationItem item) {
    final isSaved = _savedIds.contains(item.id);
    return SizedBox(
      width: 310,
      child: GlassContainer(
        borderRadius: 22,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                children: [
                  Image.network(
                    item.imageUrl,
                    height: 140,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      height: 140,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: item.gradientColors),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0x600F172A),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        item.category.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: TactilePressable(
                      onTap: () => _toggleSave(item.id),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: Color(0x80000000),
                          shape: BoxShape.circle,
                        ),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 260),
                          switchInCurve: Curves.elasticOut,
                          transitionBuilder: (child, animation) =>
                              ScaleTransition(scale: animation, child: child),
                          child: KeyedSubtree(
                            key: ValueKey(isSaved),
                            child: Icon(
                              isSaved ? Icons.favorite : Icons.favorite_border,
                              size: 16,
                              color: isSaved
                                  ? const Color(0xFFF43F5E)
                                  : Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: AppTheme.slateDark,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              item.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.slateMuted,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: item.vibeTags.take(2).map((t) {
                    return Container(
                      margin: const EdgeInsets.only(right: 4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE0F2FE),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '#$t',
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF075985),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                Text(
                  item.costRange,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF047857),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Bottom Floating 3D Vector Navigation Dock (Used on mobile/narrow viewports)
  Widget _buildBottomGlassDock() {
    return Row(
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(36),
              border: Border.all(color: const Color(0xFFE2E8F0), width: 2.2),
              boxShadow: const [
                BoxShadow(
                  color: Color(0xFFCBD5E1),
                  offset: Offset(0, 4),
                  blurRadius: 0,
                ),
                BoxShadow(
                  color: Color(0x220F172A),
                  blurRadius: 16,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavPillButton(
                  icon: Icons.explore_rounded,
                  label: 'Home',
                  tab: AppTab.explore,
                ),
                _buildNavPillButton(
                  icon: Icons.layers_rounded,
                  label: 'Spots',
                  tab: AppTab.spots,
                ),
                _buildNavPillButton(
                  icon: Icons.luggage_rounded,
                  label: 'Trips',
                  tab: AppTab.trips,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Vector3DButton(
          onTap: () => setState(() => _activeTab = AppTab.swipe),
          backgroundColor: _activeTab == AppTab.swipe
              ? const Color(0xFFF43F5E)
              : const Color(0xFFF59E0B),
          shadowColor: _activeTab == AppTab.swipe
              ? const Color(0xFF9F1239)
              : const Color(0xFFB45309),
          borderColor: Colors.white,
          borderRadius: 26,
          padding: const EdgeInsets.all(13),
          depth: 4.0,
          child: const Icon(
            Icons.style_rounded,
            color: Colors.white,
            size: 22,
          ),
        ),
      ],
    );
  }

  Widget _buildNavPillButton({
    required IconData icon,
    required String label,
    required AppTab tab,
  }) {
    final isActive = _activeTab == tab && !_showOnlySaved;
    // Three pills share the dock; shrink rather than overflow on tiny phones.
    final pill = Vector3DButton(
      onTap: () => setState(() {
        _showOnlySaved = false;
        _activeTab = tab;
      }),
      backgroundColor: isActive
          ? (tab == AppTab.explore ? const Color(0xFF0F172A) : const Color(0xFF2563EB))
          : Colors.white,
      shadowColor: isActive
          ? (tab == AppTab.explore ? const Color(0xFF020617) : const Color(0xFF1D4ED8))
          : const Color(0xFFE2E8F0),
      borderColor: isActive
          ? Colors.transparent
          : const Color(0xFFF1F5F9),
      borderRadius: 24,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      depth: 3.0,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: isActive ? Colors.white : AppTheme.slateDark,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              fontFamily: 'Outfit',
              color: isActive ? Colors.white : AppTheme.slateDark,
            ),
          ),
        ],
      ),
    );
    return Flexible(
      child: FittedBox(fit: BoxFit.scaleDown, child: pill),
    );
  }
}

/// Clips to the child's box grown by [horizontal] and [vertical] pixels, so
/// decorations can paint just outside a scroll view without being cut off.
class _BleedClipper extends CustomClipper<Rect> {
  final double horizontal;
  final double vertical;

  const _BleedClipper({required this.horizontal, required this.vertical});

  @override
  Rect getClip(Size size) => Rect.fromLTRB(
    -horizontal,
    -vertical,
    size.width + horizontal,
    size.height + vertical,
  );

  @override
  bool shouldReclip(_BleedClipper oldClipper) =>
      oldClipper.horizontal != horizontal || oldClipper.vertical != vertical;
}
