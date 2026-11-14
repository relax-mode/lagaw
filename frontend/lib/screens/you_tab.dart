import 'package:flutter/material.dart';

import '../auth/auth_session.dart';
import '../theme.dart';
import 'onboarding/first_run_gate.dart';

/// "You": the signed-in account, travel preferences, liked and saved
/// places, and sign out, gathered from the avatar menu. [home v3]
class YouTab extends StatelessWidget {
  final AuthSession? session;
  final int likedCount;
  final VoidCallback onOpenSaved;

  const YouTab({
    super.key,
    required this.session,
    required this.likedCount,
    required this.onOpenSaved,
  });

  @override
  Widget build(BuildContext context) {
    final email = session?.accountEmail;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'You',
          style: TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w900,
            letterSpacing: -1,
            color: Colors.white,
            shadows: [
              Shadow(
                color: Color(0x66104AA0),
                blurRadius: 18,
                offset: Offset(0, 4),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _card(
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
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
                  email == null || email.isEmpty ? '?' : email[0].toUpperCase(),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Signed in as',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.slateMuted,
                      ),
                    ),
                    Text(
                      email ?? 'Not signed in',
                      key: const ValueKey('you-email'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.slateDark,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _card(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _row(
                key: const ValueKey('you-preferences'),
                icon: Icons.tune_rounded,
                title: 'Travel preferences',
                subtitle: 'Interests, budget and pace',
                onTap: () => openTravelPreferences(context),
              ),
              const Divider(height: 1, indent: 64),
              _row(
                key: const ValueKey('you-saved'),
                icon: Icons.favorite_rounded,
                title: 'Liked and saved',
                subtitle: likedCount == 1 ? '1 place' : '$likedCount places',
                onTap: onOpenSaved,
              ),
            ],
          ),
        ),
        if (session != null) ...[
          const SizedBox(height: 12),
          _card(
            padding: EdgeInsets.zero,
            child: _row(
              key: const ValueKey('you-sign-out'),
              icon: Icons.logout_rounded,
              title: 'Sign out',
              danger: true,
              onTap: () => session!.signOut(),
            ),
          ),
        ],
      ],
    );
  }

  Widget _card({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(16),
  }) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x330F1B2D),
            blurRadius: 24,
            offset: Offset(0, 12),
            spreadRadius: -14,
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _row({
    required Key key,
    required IconData icon,
    required String title,
    String? subtitle,
    bool danger = false,
    required VoidCallback onTap,
  }) {
    final color = danger ? const Color(0xFFE11D48) : AppTheme.primaryBlue;
    // Own Material so the tap ripple shows on the white card.
    return Material(
      type: MaterialType.transparency,
      child: ListTile(
        key: key,
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 20, color: color),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: danger ? color : AppTheme.slateDark,
          ),
        ),
        subtitle: subtitle == null ? null : Text(subtitle),
        trailing: danger ? null : const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}
