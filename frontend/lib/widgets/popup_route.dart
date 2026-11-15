import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme.dart';

/// A pop-up page: the app behind blurs and dims and the card rises in, as
/// for travel preferences, Picked for you and Plan a trip. [home v3]
Route<T> blurPopupRoute<T>(WidgetBuilder builder) {
  return PageRouteBuilder<T>(
    opaque: false,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 380),
    reverseTransitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (context, animation, _) => builder(context),
    transitionsBuilder: (context, animation, _, child) {
      final reduce = MediaQuery.disableAnimationsOf(context);
      final fade = CurvedAnimation(parent: animation, curve: Curves.easeOut);
      final rise = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return Stack(
        children: [
          Positioned.fill(
            child: FadeTransition(
              opacity: fade,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                child: const ColoredBox(color: Color(0x590A1830)),
              ),
            ),
          ),
          FadeTransition(
            opacity: fade,
            child: reduce
                ? child
                : AnimatedBuilder(
                    animation: rise,
                    builder: (context, c) => Transform.translate(
                      offset: Offset(0, 28 * (1 - rise.value)),
                      child: Transform.scale(
                        scale: 0.94 + 0.06 * rise.value,
                        child: c,
                      ),
                    ),
                    child: child,
                  ),
          ),
        ],
      );
    },
  );
}

/// The white card of a pop-up page: a sky header with an eyebrow, title,
/// subtitle and ×, then [child]. Tapping outside closes it unless [busy].
class PopupCard extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String? subtitle;
  final bool busy;
  final Widget child;
  final double maxWidth;

  const PopupCard({
    super.key,
    required this.eyebrow,
    required this.title,
    this.subtitle,
    this.busy = false,
    this.maxWidth = 460,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.viewInsetsOf(context);
    void close() => Navigator.of(context).maybePop();
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: busy ? null : close,
            ),
          ),
          SafeArea(
            child: Center(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + insets.bottom),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x660A1830),
                          blurRadius: 40,
                          offset: Offset(0, 22),
                          spreadRadius: -14,
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [AppTheme.skyTop, AppTheme.skyMid],
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      eyebrow.toUpperCase(),
                                      style: const TextStyle(
                                        fontSize: 11,
                                        letterSpacing: 1.2,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xD9FFFFFF),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      title,
                                      style: const TextStyle(
                                        fontSize: 22,
                                        height: 1.15,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.white,
                                      ),
                                    ),
                                    if (subtitle != null)
                                      Text(
                                        subtitle!,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xE6FFFFFF),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              if (!busy)
                                Semantics(
                                  button: true,
                                  label: 'Close',
                                  child: GestureDetector(
                                    key: const ValueKey('popup-close'),
                                    onTap: close,
                                    child: Container(
                                      width: 34,
                                      height: 34,
                                      decoration: const BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Color(0xEBFFFFFF),
                                      ),
                                      child: const Icon(
                                        Icons.close_rounded,
                                        size: 19,
                                        color: AppTheme.slateDark,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Flexible(child: child),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
