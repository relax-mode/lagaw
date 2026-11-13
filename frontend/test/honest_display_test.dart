import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/config.dart';
import 'package:frontend/models/location.dart';
import 'package:frontend/widgets/destination_photo.dart';

LocationItem _place({String? image}) => LocationItem.fromJson({
  'id': 'loc-1',
  'name': 'Calea',
  'category': 'cafe',
  'image_url': image,
});

void main() {
  group('formatCostRange', () {
    test('"Free" only when the API says the place costs nothing', () {
      expect(formatCostRange(0, 0), 'Free');
      expect(formatCostRange(null, 0), 'Free');
      expect(formatCostRange(0, null), 'Price unknown');
      expect(formatCostRange(null, null), 'Price unknown');
    });

    test('shows the known part of a range', () {
      expect(formatCostRange(70, 100), '₱70 – ₱100');
      expect(formatCostRange(0, 100), '₱0 – ₱100');
      expect(formatCostRange(150, 150), '₱150');
      expect(formatCostRange(null, 300), 'Up to ₱300');
      expect(formatCostRange(200, null), 'From ₱200');
      expect(formatCostRange(70.5, 99.99), '₱70.50 – ₱99.99');
    });

    test('decimal strings from the API are understood', () {
      final place = LocationItem.fromJson({
        'id': 'x',
        'estimated_cost_min': '70.00',
        'estimated_cost_max': '100.00',
        'typical_visit_duration': 60,
      });
      expect(place.costRange, '₱70 – ₱100');
      expect(place.duration, '60 mins');
    });
  });

  test('visit length is never invented', () {
    expect(formatVisitLength(null), 'Visit length unknown');
    expect(formatVisitLength(0), 'Visit length unknown');
    expect(formatVisitLength(45), '45 mins');
  });

  group('releaseConfigError', () {
    test('debug builds are never blocked', () {
      expect(
        releaseConfigError(
          isRelease: false,
          apiBaseUrlProvided: false,
          authEnabled: false,
        ),
        isNull,
      );
    });

    test('a release build needs the API and Supabase configured', () {
      for (final (api, auth) in [
        (false, true),
        (true, false),
        (false, false),
      ]) {
        expect(
          releaseConfigError(
            isRelease: true,
            apiBaseUrlProvided: api,
            authEnabled: auth,
          ),
          contains('not configured'),
        );
      }
      expect(
        releaseConfigError(
          isRelease: true,
          apiBaseUrlProvided: true,
          authEnabled: true,
        ),
        isNull,
      );
    });
  });

  group('DestinationPhoto', () {
    Future<void> pump(WidgetTester tester, LocationItem place) =>
        tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 300,
                height: 200,
                child: DestinationPhoto(location: place),
              ),
            ),
          ),
        );

    testWidgets('no photo shows an honest placeholder, not a stock image', (
      tester,
    ) async {
      await pump(tester, _place());
      expect(find.text('No photo yet'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(
        find.byKey(const ValueKey('photo-placeholder-loc-1')),
        findsOneWidget,
      );
    });

    testWidgets('a real photo is loaded from its URL', (tester) async {
      await pump(tester, _place(image: 'https://example.com/calea.jpg'));
      final image = tester.widget<Image>(find.byType(Image));
      expect(
        (image.image as NetworkImage).url,
        'https://example.com/calea.jpg',
      );
    });

    testWidgets('a photo that fails to load says so', (tester) async {
      await pump(tester, _place(image: 'https://example.com/missing.jpg'));
      await tester.pumpAndSettle();
      expect(find.text('Photo unavailable'), findsOneWidget);
    });
  });
}
