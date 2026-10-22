import 'package:flutter/material.dart';

import '../theme.dart';
import 'tactile_motion.dart';

enum StatusTone { error, info, success }

/// Tactile inline banner for request outcomes, with an optional action. [S2-04]
class StatusBanner extends StatelessWidget {
  final StatusTone tone;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const StatusBanner({
    super.key,
    required this.tone,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  ({Color tint, Color border, Color bevel, Color accent, IconData icon})
  get _palette => switch (tone) {
    StatusTone.error => (
      tint: const Color(0xFFFFF1F2),
      border: const Color(0xFFFECDD3),
      bevel: const Color(0xFFFDA4AF),
      accent: const Color(0xFFE11D48),
      icon: Icons.error_rounded,
    ),
    StatusTone.info => (
      tint: const Color(0xFFEFF6FF),
      border: const Color(0xFFBFDBFE),
      bevel: const Color(0xFF93C5FD),
      accent: AppTheme.primaryBlue,
      icon: Icons.info_rounded,
    ),
    StatusTone.success => (
      tint: const Color(0xFFF0FDF4),
      border: const Color(0xFFBBF7D0),
      bevel: const Color(0xFF86EFAC),
      accent: const Color(0xFF16A34A),
      icon: Icons.check_circle_rounded,
    ),
  };

  @override
  Widget build(BuildContext context) {
    final p = _palette;
    return FadeSlideIn(
      offsetY: 10,
      child: Semantics(
        liveRegion: true,
        child: GlassContainer(
          tintColor: p.tint,
          borderColor: p.border,
          borderRadius: 18,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          boxShadow: [
            BoxShadow(
              color: p.bevel,
              offset: const Offset(0, 3),
              blurRadius: 0,
            ),
          ],
          child: Row(
            children: [
              Icon(p.icon, color: p.accent, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.slateDark,
                  ),
                ),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(width: 10),
                Vector3DButton(
                  onTap: onAction,
                  backgroundColor: Colors.white,
                  shadowColor: p.bevel,
                  borderColor: p.border,
                  borderRadius: 16,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  depth: 2.5,
                  child: Text(
                    actionLabel!,
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontWeight: FontWeight.w900,
                      fontSize: 12.5,
                      color: p.accent,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
