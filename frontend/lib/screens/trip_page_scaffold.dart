import 'package:flutter/material.dart';

import '../theme.dart';

/// Sky-gradient page shell for pushed trip screens, matching the home
/// screen backdrop, with a tactile back button and lowercase title. [S2-04]
class TripPageScaffold extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final Widget? trailing;

  const TripPageScaffold({
    super.key,
    required this.title,
    this.subtitle,
    required this.children,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 768;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppTheme.skyTop, AppTheme.skyMid, AppTheme.skyBottom],
            stops: [0.0, 0.48, 1.0],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: isWide ? 640 : 430),
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  isWide ? 32 : 20,
                  12,
                  isWide ? 32 : 20,
                  40,
                ),
                children: [
                  Row(
                    children: [
                      Vector3DButton(
                        key: const ValueKey('trip-back'),
                        onTap: () => Navigator.of(context).maybePop(),
                        backgroundColor: Colors.white,
                        shadowColor: const Color(0xFFCBD5E1),
                        borderColor: const Color(0xFFE2E8F0),
                        borderRadius: 20,
                        padding: const EdgeInsets.all(10),
                        depth: 3,
                        child: const Icon(
                          Icons.arrow_back_rounded,
                          size: 20,
                          color: AppTheme.slateDark,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: 'Outfit',
                                fontWeight: FontWeight.w900,
                                fontSize: 28,
                                color: Colors.white,
                                letterSpacing: -0.5,
                              ),
                            ),
                            if (subtitle != null)
                              Text(
                                subtitle!,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12.5,
                                  color: Color(0xE6FFFFFF),
                                ),
                              ),
                          ],
                        ),
                      ),
                      ?trailing,
                    ],
                  ),
                  const SizedBox(height: 18),
                  ...children,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
