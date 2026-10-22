import 'package:flutter/material.dart';

import '../theme.dart';

/// Tactile confirmation dialog. Resolves `true` only when the user taps
/// [confirmLabel]; dismissing or cancelling resolves `false`. [S2-05]
Future<bool> showTactileConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  IconData icon = Icons.delete_forever_rounded,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    barrierColor: const Color(0x660F172A),
    builder: (context) => _TactileConfirmDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      icon: icon,
    ),
  );
  return confirmed ?? false;
}

class _TactileConfirmDialog extends StatelessWidget {
  final String title;
  final String message;
  final String confirmLabel;
  final IconData icon;

  const _TactileConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.icon,
  });

  static const Color _rose = Color(0xFFE11D48);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: GlassContainer(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1F2),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFFECDD3), width: 2),
                ),
                child: Icon(icon, size: 28, color: _rose),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Outfit',
                  fontWeight: FontWeight.w900,
                  fontSize: 19,
                  color: AppTheme.slateDark,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                  height: 1.35,
                  color: AppTheme.slateMuted,
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: Vector3DButton(
                      key: const ValueKey('confirm-cancel'),
                      onTap: () => Navigator.of(context).pop(false),
                      backgroundColor: Colors.white,
                      shadowColor: const Color(0xFFCBD5E1),
                      borderColor: const Color(0xFFE2E8F0),
                      borderRadius: 22,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      child: const Center(
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            fontFamily: 'Outfit',
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                            color: AppTheme.slateDark,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Vector3DButton(
                      key: const ValueKey('confirm-accept'),
                      onTap: () => Navigator.of(context).pop(true),
                      backgroundColor: _rose,
                      shadowColor: const Color(0xFF9F1239),
                      borderColor: const Color(0xFFFDA4AF),
                      borderRadius: 22,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      child: Center(
                        child: Text(
                          confirmLabel,
                          style: const TextStyle(
                            fontFamily: 'Outfit',
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
