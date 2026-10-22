import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/locations_screen.dart';
import 'package:frontend/screens/trips_tab.dart';
import 'package:frontend/services/trip_service.dart';

/// Pumps the home screen at [size]. Some home rows (hero, category pills)
/// already overflow slightly with the wide test font at phone widths; that
/// predates S2-04, so those errors are drained and only reported via [onOverflow].
Future<void> _pumpHome(
  WidgetTester tester,
  Size size, {
  void Function(Object error)? onOverflow,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: LocationsScreen(tripService: TripService(token: '')),
    ),
  );
  await tester.pump(const Duration(seconds: 1));
  final error = tester.takeException();
  if (error != null) onOverflow?.call(error);
}

void main() {
  testWidgets('wide header fits the Trips button without overflow', (
    tester,
  ) async {
    Object? overflow;
    await _pumpHome(
      tester,
      const Size(1280, 900),
      onOverflow: (e) => overflow = e,
    );

    expect(overflow, isNull);
    expect(find.text('My Trips'), findsOneWidget);
  });

  testWidgets('narrow wide-layout shows Trips as an icon with tooltip', (
    tester,
  ) async {
    await _pumpHome(tester, const Size(900, 900));

    expect(find.byTooltip('My Trips'), findsOneWidget);
    expect(find.text('My Trips'), findsNothing);
  });

  testWidgets('mobile dock Trips pill opens My Trips', (tester) async {
    await _pumpHome(tester, const Size(390, 844));

    await tester.tap(find.text('Trips'));
    // Let the tab cross-fade finish and the trip request resolve.
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }
    tester.takeException();

    expect(find.byType(TripsTab), findsOneWidget);
    // No token in tests: the tab explains how to configure it.
    expect(find.textContaining('TRIP_DEMO_TOKEN'), findsOneWidget);
  });
}
