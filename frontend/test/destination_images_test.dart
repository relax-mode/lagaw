import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/image_credits.dart';
import 'package:frontend/models/location.dart';
import 'package:frontend/widgets/destination_photo.dart';

const _cathedral = '1a3bca09-5532-5de6-8587-2440c4e5830d';
const _museum = '61bf94ab-6ec0-5ec3-8451-b575ee06169e';
final _sha = 'a' * 64;
final _museumSha = 'b' * 64;

String _url(String location, String sha) =>
    'https://example.supabase.co/storage/v1/object/public/'
    'destination-images/locations/$location/$sha.jpg';

final _credits = ImageCredits([
  ImageCredit(
    locationId: _cathedral,
    sha256: _sha,
    primary: true,
    attribution: 'Photo: Rauxilian / CC BY-SA 4.0 via Wikimedia Commons',
    photographer: 'Rauxilian',
    license: 'CC BY-SA 4.0',
    licenseUrl: 'https://creativecommons.org/licenses/by-sa/4.0',
    sourceUrl: 'https://commons.wikimedia.org/wiki/File:Example.jpg',
    modified: 'Resized from 4745x3164 to 2048x1366.',
  ),
  ImageCredit(
    locationId: _museum,
    sha256: _museumSha,
    primary: true,
    attribution: 'Photo: Patrickroque01 / CC BY-SA 4.0 via Wikimedia Commons',
    photographer: 'Patrickroque01',
    license: 'CC BY-SA 4.0',
  ),
]);

LocationItem _place(String id, String? image) => LocationItem.fromJson({
  'id': id,
  'name': 'Place',
  'category': 'heritage',
  'image_url': image,
});

void main() {
  group('ImageCredits.creditFor', () {
    test('matches an approved photo of the same place', () {
      expect(
        _credits.creditFor(_cathedral, _url(_cathedral, _sha))?.photographer,
        'Rauxilian',
      );
      expect(
        _credits.creditFor(_cathedral, _url(_cathedral, _sha.toUpperCase())),
        isNotNull,
      );
    });

    test('rejects a photo approved for a different place', () {
      // The staging mix-up: the museum's photo linked to the cathedral.
      expect(
        _credits.creditFor(_cathedral, _url(_cathedral, _museumSha)),
        isNull,
      );
      expect(_credits.creditFor(_cathedral, _url(_museum, _museumSha)), isNull);
    });

    test('rejects unknown files and URLs outside the upload layout', () {
      expect(
        _credits.creditFor(_cathedral, _url(_cathedral, 'c' * 64)),
        isNull,
      );
      expect(
        _credits.creditFor(_cathedral, 'https://example.com/photo.jpg'),
        isNull,
      );
      expect(_credits.creditFor(_cathedral, null), isNull);
      expect(_credits.creditFor(_cathedral, 'not a url'), isNull);
    });
  });

  test('the bundled credits match the generated asset format', () {
    final asset = jsonDecode(
      File('assets/image_credits.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final credits = ImageCredits.fromJson(asset);
    expect(credits.length, (asset['images'] as List).length);
    expect(credits.length, greaterThanOrEqualTo(10));
  });

  group('DestinationPhoto', () {
    Future<void> pump(WidgetTester tester, LocationItem place) =>
        tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 320,
                height: 220,
                child: DestinationPhoto(location: place, credits: _credits),
              ),
            ),
          ),
        );

    testWidgets('a valid photo is shown with its credit', (tester) async {
      await pump(tester, _place(_cathedral, _url(_cathedral, _sha)));
      final image = tester.widget<Image>(find.byType(Image));
      final provider = image.image is ResizeImage
          ? (image.image as ResizeImage).imageProvider
          : image.image;
      expect((provider as NetworkImage).url, _url(_cathedral, _sha));
      expect(find.text('Photo: Rauxilian · CC BY-SA 4.0'), findsOneWidget);
    });

    testWidgets('tapping the credit shows attribution, changes and links', (
      tester,
    ) async {
      await pump(tester, _place(_cathedral, _url(_cathedral, _sha)));
      await tester.tap(find.text('Photo: Rauxilian · CC BY-SA 4.0'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('photo-credit-sheet')), findsOneWidget);
      expect(
        find.text('Photo: Rauxilian / CC BY-SA 4.0 via Wikimedia Commons'),
        findsOneWidget,
      );
      expect(find.textContaining('Resized from 4745x3164'), findsOneWidget);
      expect(find.byKey(const ValueKey('photo-credit-source')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('photo-credit-license')),
        findsOneWidget,
      );
    });

    testWidgets('a missing photo shows the honest placeholder', (tester) async {
      await pump(tester, _place(_cathedral, null));
      expect(find.byType(Image), findsNothing);
      expect(find.text('No photo yet'), findsOneWidget);
    });

    testWidgets('a mislinked photo is not shown', (tester) async {
      await pump(tester, _place(_cathedral, _url(_cathedral, _museumSha)));
      expect(find.byType(Image), findsNothing);
      expect(find.text('No photo yet'), findsOneWidget);
    });

    testWidgets('a photo that fails to load says so', (tester) async {
      await pump(tester, _place(_cathedral, _url(_cathedral, _sha)));
      await tester.pumpAndSettle();
      expect(find.text('Photo unavailable'), findsOneWidget);
    });
  });
}
