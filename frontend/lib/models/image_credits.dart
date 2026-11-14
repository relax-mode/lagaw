import 'dart:convert';

import 'package:flutter/services.dart';

/// Who took a destination photo and under which license (#107 manifest).
class ImageCredit {
  final String locationId;
  final String sha256;
  final bool primary;

  /// e.g. "Photo: Rauxilian / CC BY-SA 4.0 via Wikimedia Commons".
  final String attribution;
  final String photographer;
  final String license;
  final String? licenseUrl;
  final String? sourceUrl;

  /// How the uploaded copy differs from the original, if it does.
  final String? modified;

  const ImageCredit({
    required this.locationId,
    required this.sha256,
    required this.primary,
    required this.attribution,
    required this.photographer,
    required this.license,
    this.licenseUrl,
    this.sourceUrl,
    this.modified,
  });

  factory ImageCredit.fromJson(Map<String, dynamic> json) => ImageCredit(
    locationId: json['location_id'] as String,
    sha256: (json['sha256'] as String).toLowerCase(),
    primary: json['primary'] as bool? ?? false,
    attribution: json['attribution'] as String,
    photographer: json['photographer'] as String,
    license: json['license'] as String,
    licenseUrl: json['license_url'] as String?,
    sourceUrl: json['source_url'] as String?,
    modified: json['modified'] as String?,
  );
}

/// Approved photos, keyed by the SHA-256 of the uploaded file. [S4-09]
///
/// The #108 upload script stores each file at
/// `locations/<location id>/<sha256>.<ext>`, so a photo URL names its exact
/// bytes. A photo is shown only when those bytes are approved for that same
/// location; anything else (an unlicensed file, or a photo linked to the
/// wrong place) falls back to the honest placeholder.
class ImageCredits {
  final Map<String, ImageCredit> _bySha;

  ImageCredits(Iterable<ImageCredit> credits)
    : _bySha = {for (final c in credits) c.sha256: c};

  /// Loaded once at startup; empty (nothing shown) until then.
  static ImageCredits instance = ImageCredits(const []);

  static final RegExp _objectName = RegExp(
    r'/locations/([0-9a-fA-F-]{36})/([0-9a-fA-F]{64})\.(jpe?g|png|webp)$',
  );

  factory ImageCredits.fromJson(Map<String, dynamic> json) => ImageCredits([
    for (final image in json['images'] as List<dynamic>)
      ImageCredit.fromJson(image as Map<String, dynamic>),
  ]);

  static Future<void> load({AssetBundle? bundle}) async {
    try {
      final text = await (bundle ?? rootBundle).loadString(
        'assets/image_credits.json',
      );
      instance = ImageCredits.fromJson(
        jsonDecode(text) as Map<String, dynamic>,
      );
    } catch (_) {
      // Without credits no photo is shown, which is the safe default.
      instance = ImageCredits(const []);
    }
  }

  int get length => _bySha.length;

  /// The credit for [imageUrl] when it is an approved photo of
  /// [locationId]; null otherwise.
  ImageCredit? creditFor(String locationId, String? imageUrl) {
    if (imageUrl == null) return null;
    final path = Uri.tryParse(imageUrl)?.path;
    final match = path == null ? null : _objectName.firstMatch(path);
    if (match == null) return null;
    final credit = _bySha[match.group(2)!.toLowerCase()];
    if (credit == null) return null;
    final pathLocation = match.group(1)!.toLowerCase();
    final id = locationId.toLowerCase();
    return credit.locationId == id && pathLocation == id ? credit : null;
  }
}
