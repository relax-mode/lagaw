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
        child: Stack(
          children: [
            Positioned(
              top: -90,
              left: -90,
              child: IgnorePointer(
                child: Container(
                  width: 250,
                  height: 250,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        Color(0xFFFFFBEB),
                        Color(0xFFFEF08A),
                        Color(0xFFF59E0B),
                        Color(0x00F59E0B),
                      ],
                      stops: [0, 0.35, 0.7, 1],
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
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
                          Semantics(
                            button: true,
                            label: 'Back',
                            child: GestureDetector(
                              key: const ValueKey('trip-back'),
                              onTap: () => Navigator.of(context).maybePop(),
                              child: Container(
                                width: 44,
                                height: 44,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Color(0xF5FFFFFF),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Color(0x330F1B2D),
                                      blurRadius: 18,
                                      offset: Offset(0, 8),
                                      spreadRadius: -10,
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.arrow_back_rounded,
                                  size: 21,
                                  color: AppTheme.slateDark,
                                ),
                              ),
                            ),
                          ),
                          const Spacer(),
                          ?trailing,
                        ],
                      ),
                      const SizedBox(height: 14),
                      // Centered like Spots, Trips and You. [home v3]
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 34,
                          height: 1.05,
                          color: Colors.white,
                          letterSpacing: -1,
                          shadows: [
                            Shadow(
                              color: Color(0x40104AA0),
                              blurRadius: 22,
                              offset: Offset(0, 6),
                            ),
                          ],
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          subtitle!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            height: 1.35,
                            color: Color(0xEBFFFFFF),
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      ...children,
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
}
