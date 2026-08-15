import 'package:abakus_one_v2/features/address_search/presentation/widgets/address_map_confirmation_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

void main() {
  group('AddressMapConfirmationCard', () {
    testWidgets('opens the map centered on the resolved coordinates (req 1)',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AddressMapConfirmationCard(
              latitude: 41.0449616,
              longitude: 29.0076831,
              formattedAddress: 'Balmumcu, Beşiktaş/İstanbul',
              onPinMoved: (_) {},
            ),
          ),
        ),
      );
      // Deliberately do NOT pump past the fallback timeout — this
      // inspects the GoogleMap widget's own configuration before the
      // (test-environment-only) fallback would ever trigger.

      final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
      expect(map.initialCameraPosition.target.latitude, 41.0449616);
      expect(map.initialCameraPosition.target.longitude, 29.0076831);
    });

    testWidgets('renders a marker at the resolved position (req 2)',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AddressMapConfirmationCard(
              latitude: 41.05,
              longitude: 29.01,
              formattedAddress: null,
              onPinMoved: (_) {},
            ),
          ),
        ),
      );

      final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
      expect(map.markers, hasLength(1));
      final marker = map.markers.first;
      expect(marker.position.latitude, 41.05);
      expect(marker.position.longitude, 29.01);
      expect(marker.draggable, isTrue);
    });

    testWidgets(
        'a map that never becomes ready falls back to a safe address '
        'summary with retry, never a silent OSM substitution (req 6)',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AddressMapConfirmationCard(
              latitude: 41.05,
              longitude: 29.01,
              formattedAddress: 'Test formatted address',
              onPinMoved: (_) {},
              mapReadyTimeout: const Duration(milliseconds: 10),
            ),
          ),
        ),
      );

      // Under `flutter test`, GoogleMap's onMapCreated never fires (no
      // real platform view) — advancing past the short timeout
      // deterministically exercises the real fallback path.
      await tester.pump(const Duration(milliseconds: 20));

      expect(find.byType(GoogleMap), findsNothing);
      expect(
          find.byKey(const ValueKey('address-map-fallback')), findsOneWidget);
      expect(find.text('Test formatted address'), findsOneWidget);
      expect(find.text('Tekrar Dene'), findsOneWidget);
    });

    testWidgets(
        'dragging the marker calls onPinMoved with the new position, '
        'never mutating latitude/longitude directly', (tester) async {
      LatLng? reportedPosition;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AddressMapConfirmationCard(
              latitude: 41.05,
              longitude: 29.01,
              formattedAddress: null,
              onPinMoved: (position) => reportedPosition = position,
            ),
          ),
        ),
      );

      final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
      final marker = map.markers.first;
      marker.onDragEnd?.call(const LatLng(41.06, 29.02));

      expect(reportedPosition, const LatLng(41.06, 29.02));
    });
  });
}
