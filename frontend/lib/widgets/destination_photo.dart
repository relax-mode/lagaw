import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/image_credits.dart';
import '../models/location.dart';
import '../theme.dart';

/// A destination's real, licensed photo with its credit, or an honest
/// stand-in: the category colors with an icon and "No photo yet". A photo
/// is shown only when its file is approved for this place in the #107
/// manifest, so unlicensed or mislinked images are never displayed. Also
/// used while loading and when the image fails. [S4-17, S4-09]
/// Where the photo credit sits, so card titles and fades never cover it.
enum CreditCorner { bottomLeft, topLeft, topRight }

class DestinationPhoto extends StatelessWidget {
  final LocationItem location;
  final double? width;
  final double? height;

  /// Small thumbnails show only the icon (and a credit button, not text).
  final bool compact;

  /// Test hook; defaults to [ImageCredits.instance].
  final ImageCredits? credits;

  /// Cards with a title at the bottom move the credit to a top corner.
  final CreditCorner creditCorner;

  const DestinationPhoto({
    super.key,
    required this.location,
    this.width,
    this.height,
    this.compact = false,
    this.credits,
    this.creditCorner = CreditCorner.bottomLeft,
  });

  @override
  Widget build(BuildContext context) {
    final url = location.imageUrl;
    final credit = (credits ?? ImageCredits.instance).creditFor(
      location.id,
      url,
    );
    if (url == null || credit == null) {
      return _placeholder(label: 'No photo yet');
    }
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            url,
            width: width,
            height: height,
            fit: BoxFit.cover,
            // Decode near display size instead of the full upload.
            cacheWidth: width != null && width!.isFinite
                ? (width! * MediaQuery.devicePixelRatioOf(context)).round()
                : 1200,
            loadingBuilder: (context, child, progress) =>
                progress == null ? child : _placeholder(),
            errorBuilder: (_, _, _) => _placeholder(label: 'Photo unavailable'),
          ),
          switch (creditCorner) {
            CreditCorner.bottomLeft => Positioned(
              left: 6,
              bottom: 6,
              right: compact ? null : 6,
              child: _CreditChip(credit: credit, compact: compact),
            ),
            CreditCorner.topLeft => Positioned(
              left: 10,
              top: 10,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 240),
                child: _CreditChip(credit: credit, compact: compact),
              ),
            ),
            CreditCorner.topRight => Positioned(
              right: 10,
              top: 10,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 200),
                child: _CreditChip(credit: credit, compact: compact),
              ),
            ),
          },
        ],
      ),
    );
  }

  Widget _placeholder({String? label}) {
    return Container(
      key: ValueKey('photo-placeholder-${location.id}'),
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: location.gradientColors,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _icon(location.category),
              color: const Color(0xCCFFFFFF),
              size: compact ? 28 : 40,
            ),
            if (label != null && !compact) ...[
              const SizedBox(height: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xDDFFFFFF),
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static IconData _icon(String category) => switch (category) {
    'cafe' => Icons.local_cafe_rounded,
    'heritage' => Icons.account_balance_rounded,
    'museum' => Icons.museum_rounded,
    'park' => Icons.park_rounded,
    'gallery' => Icons.palette_rounded,
    'restaurant' => Icons.restaurant_rounded,
    'landmark' => Icons.location_city_rounded,
    _ => Icons.place_rounded,
  };
}

/// "Photo: Name / License" on the image; tapping opens the full credit.
class _CreditChip extends StatelessWidget {
  final ImageCredit credit;
  final bool compact;

  const _CreditChip({required this.credit, required this.compact});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Photo credit: ${credit.attribution}',
      child: GestureDetector(
        key: ValueKey('photo-credit-${credit.sha256.substring(0, 12)}'),
        onTap: () => showPhotoCredit(context, credit),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 4 : 8,
            vertical: compact ? 2 : 3,
          ),
          decoration: BoxDecoration(
            color: const Color(0x99000000),
            borderRadius: BorderRadius.circular(8),
          ),
          child: compact
              ? const Icon(
                  Icons.copyright_rounded,
                  size: 12,
                  color: Colors.white,
                )
              : Text(
                  'Photo: ${credit.photographer} · ${credit.license}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
      ),
    );
  }
}

/// Full attribution with links to the source and the license. [S4-09]
Future<void> showPhotoCredit(BuildContext context, ImageCredit credit) {
  return showModalBottomSheet<void>(
    context: context,
    // Above any pop-up card, full width, like the app's other sheets.
    useRootNavigator: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Container(
        key: const ValueKey('photo-credit-sheet'),
        // M3 sheets shrink to their content; credits read better full width.
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Photo credit',
              style: TextStyle(
                fontFamily: 'Outfit',
                fontWeight: FontWeight.w900,
                fontSize: 18,
                color: AppTheme.slateDark,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              credit.attribution,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppTheme.slateDark,
              ),
            ),
            if (credit.modified != null) ...[
              const SizedBox(height: 6),
              Text(
                'Changes: ${credit.modified}',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppTheme.slateMuted,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                if (credit.sourceUrl != null)
                  TextButton.icon(
                    key: const ValueKey('photo-credit-source'),
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    label: const Text('Original photo'),
                    onPressed: () => _open(credit.sourceUrl!),
                  ),
                if (credit.licenseUrl != null)
                  TextButton.icon(
                    key: const ValueKey('photo-credit-license'),
                    icon: const Icon(Icons.gavel_rounded, size: 16),
                    label: Text(credit.license),
                    onPressed: () => _open(credit.licenseUrl!),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _open(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http')) return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}
