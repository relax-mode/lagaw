import 'package:flutter/material.dart';

import '../theme.dart';

/// Hiligaynon greeting for the local time of day.
String hiligaynonGreeting(DateTime now) {
  final h = now.hour;
  if (h >= 5 && h < 11) return 'Maayong aga,';
  if (h >= 11 && h < 13) return 'Maayong udto,';
  if (h >= 13 && h < 18) return 'Maayong hapon,';
  return 'Maayong gab-i,';
}

/// The v3 header on every phone tab: avatar, greeting, liked-and-saved
/// count and search, in one white pill. [home v3]
class GreetingPill extends StatelessWidget {
  final String avatarLetter;
  final int likedCount;
  final VoidCallback onSearch;
  final VoidCallback onSaved;
  final VoidCallback onAccount;

  /// Test hook for the greeting.
  final DateTime Function() clock;

  const GreetingPill({
    super.key,
    required this.avatarLetter,
    required this.likedCount,
    required this.onSearch,
    required this.onSaved,
    required this.onAccount,
    this.clock = DateTime.now,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xF5FFFFFF),
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [
          BoxShadow(
            color: Color(0x330F1B2D),
            blurRadius: 24,
            offset: Offset(0, 10),
            spreadRadius: -12,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            button: true,
            label: 'Your account',
            child: GestureDetector(
              key: const ValueKey('home-account'),
              onTap: onAccount,
              child: Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFFF9A3D), Color(0xFFF2620F)],
                  ),
                ),
                child: Text(
                  avatarLetter,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                hiligaynonGreeting(clock()),
                key: const ValueKey('home-greeting'),
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF4A5B73),
                  height: 1.1,
                ),
              ),
              const Text(
                'Bacolod City',
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.slateDark,
                  height: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(width: 14),
          _icon(
            key: const ValueKey('home-saved'),
            label: 'Liked and saved places',
            onTap: onSaved,
            icon: Icons.favorite_rounded,
            color: const Color(0xFFF2620F),
            badge: likedCount,
          ),
          const SizedBox(width: 6),
          _icon(
            key: const ValueKey('home-search'),
            label: 'Search places',
            onTap: onSearch,
            icon: Icons.search_rounded,
            color: AppTheme.slateDark,
          ),
        ],
      ),
    );
  }

  Widget _icon({
    required Key key,
    required String label,
    required VoidCallback onTap,
    required IconData icon,
    required Color color,
    int badge = 0,
  }) {
    return Semantics(
      button: true,
      label: badge > 0 ? '$label, $badge' : label,
      child: GestureDetector(
        key: key,
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFEEF4FC),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 20, color: color),
              ),
              if (badge > 0)
                Positioned(
                  top: -3,
                  right: -3,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 18),
                    height: 18,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF2620F),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: Text(
                      badge > 99 ? '99+' : '$badge',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
