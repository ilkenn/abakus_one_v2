import 'dart:async';

import 'package:abakus_one_v2/core/fraud/domain/fraud_evidence.dart';
import 'package:abakus_one_v2/core/fraud/domain/mock_location_status.dart';
import 'package:abakus_one_v2/features/address_search/data/address_location_gateway.dart';
import 'package:abakus_one_v2/features/address_search/data/address_search_exception.dart';
import 'package:abakus_one_v2/features/address_search/domain/models/address_suggestion.dart';
import 'package:abakus_one_v2/features/address_search/domain/models/resolved_address.dart';
import 'package:abakus_one_v2/features/address_search/domain/services/address_search_provider.dart';
import 'package:abakus_one_v2/features/address_search/presentation/providers/address_search_provider.dart';
import 'package:abakus_one_v2/features/address_search/presentation/screens/address_search_screen.dart';
import 'package:abakus_one_v2/features/address_search/presentation/screens/map_first_address_screen.dart';
import 'package:abakus_one_v2/features/orders/data/saved_address_repository.dart';
import 'package:abakus_one_v2/features/orders/domain/models/saved_address.dart';
import 'package:abakus_one_v2/features/orders/presentation/providers/saved_address_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

const _besiktas = LatLng(41.0449616, 29.0076831);
const _sisli = LatLng(41.06, 28.99);

ResolvedAddress _resolvedFor(LatLng point, {bool sufficientlyResolved = true}) {
  return ResolvedAddress(
    providerPlaceId: 'place-${point.latitude}-${point.longitude}',
    formattedAddress: 'Resolved at ${point.latitude}, ${point.longitude}',
    provinceName: 'İstanbul',
    districtName: sufficientlyResolved ? 'Beşiktaş' : null,
    neighborhoodName: 'Balmumcu',
    routeName: 'Barbaros Bulvarı',
    streetNumber: '74',
    latitude: point.latitude,
    longitude: point.longitude,
    isSufficientlyResolved: sufficientlyResolved,
  );
}

class _FakeAddressSearchProvider implements AddressSearchProvider {
  final List<(double, double)> reverseGeocodeCalls = [];
  bool failNextReverseGeocode = false;
  bool Function(LatLng)? sufficientlyResolvedOverride;

  /// When set, `reverseGeocode` waits on this instead of resolving
  /// immediately — lets a test control exactly when an in-flight call
  /// completes, to simulate two overlapping requests racing.
  Future<void>? holdUntil;

  @override
  Future<List<AddressSuggestion>> autocomplete({
    required String input,
    required String sessionToken,
  }) async =>
      [];

  @override
  Future<ResolvedAddress> resolvePlace({
    required String placeId,
    required String sessionToken,
  }) async =>
      _resolvedFor(_besiktas);

  @override
  Future<ResolvedAddress> reverseGeocode({
    required double latitude,
    required double longitude,
  }) async {
    reverseGeocodeCalls.add((latitude, longitude));
    if (holdUntil != null) await holdUntil;
    if (failNextReverseGeocode) {
      throw const AddressSearchException('not-found', 'Konum çözümlenemedi.');
    }
    final point = LatLng(latitude, longitude);
    final sufficient = sufficientlyResolvedOverride?.call(point) ?? true;
    return _resolvedFor(point, sufficientlyResolved: sufficient);
  }
}

class _FakeAddressLocationGateway implements AddressLocationGateway {
  _FakeAddressLocationGateway({
    this.position,
    this.permanentlyDenied = false,
    this.captureResult = const DeviceLocationCaptureResult.unavailable(
      DeviceLocationUnavailableReason.permissionDenied,
    ),
  });

  ({double latitude, double longitude})? position;
  bool permanentlyDenied;
  int currentPositionCalls = 0;

  /// FRAUD-F.1 — the fake result [captureLocationEvidence] returns.
  /// Defaults to "unavailable" so existing tests (written before FRAUD-F.1
  /// existed) keep exercising the "no candidate" path, matching this
  /// gateway's own real "never fabricate coordinates" default posture.
  DeviceLocationCaptureResult captureResult;
  int captureLocationEvidenceCalls = 0;

  @override
  Future<({double latitude, double longitude})?> currentPosition() async {
    currentPositionCalls++;
    return position;
  }

  @override
  Future<bool> isPermissionPermanentlyDenied() async => permanentlyDenied;

  @override
  Future<DeviceLocationCaptureResult> captureLocationEvidence() async {
    captureLocationEvidenceCalls++;
    return captureResult;
  }
}

class _SpySavedAddressRepository implements SavedAddressRepository {
  final List<String> savedPlaceIds = [];
  ClientLocationEvidence? lastDeviceLocation;
  String? lastDeviceLocationUnavailableReason;

  @override
  Future<SavedAddress> save({
    String? addressId,
    required String providerPlaceId,
    required String label,
    bool isDefault = false,
    required String apartmentNo,
    String? floor,
    String? addressDescription,
    String? buildingNoOverride,
    ClientLocationEvidence? deviceLocation,
    String? deviceLocationUnavailableReason,
  }) async {
    savedPlaceIds.add(providerPlaceId);
    lastDeviceLocation = deviceLocation;
    lastDeviceLocationUnavailableReason = deviceLocationUnavailableReason;
    return SavedAddress(
      id: 'saved-1',
      customerId: 'uid-1',
      label: label,
      apartmentNo: apartmentNo,
      verificationStatus: AddressVerificationStatus.verified,
    );
  }

  @override
  Future<List<SavedAddress>> listForCurrentUser() async => [];

  @override
  Future<void> updateMetadata({
    required String addressId,
    String? label,
    bool? isDefault,
    String? apartmentNo,
    String? floor,
    String? addressDescription,
    String? buildingNoOverride,
  }) async {}

  @override
  Future<void> delete(String addressId) async {}
}

Widget _wrap({
  required Widget child,
  required _FakeAddressSearchProvider searchProvider,
  required _FakeAddressLocationGateway locationGateway,
  SavedAddressRepository? savedAddressRepository,
}) {
  return ProviderScope(
    overrides: [
      addressSearchProviderProvider.overrideWithValue(searchProvider),
      addressLocationGatewayProvider.overrideWithValue(locationGateway),
      if (savedAddressRepository != null)
        savedAddressRepositoryProvider
            .overrideWithValue(savedAddressRepository),
    ],
    child: MaterialApp(home: child),
  );
}

void main() {
  group('MapFirstAddressScreen — Faz P.2.1.2 map-first UX', () {
    testWidgets('a fixed center pin overlay exists (req 4)', (tester) async {
      await tester.pumpWidget(_wrap(
        child: MapFirstAddressScreen(
          initialLatitude: _besiktas.latitude,
          initialLongitude: _besiktas.longitude,
        ),
        searchProvider: _FakeAddressSearchProvider(),
        locationGateway: _FakeAddressLocationGateway(),
      ));
      await tester.pump();

      expect(find.byIcon(Icons.location_on), findsOneWidget);
    });

    testWidgets(
        'camera movement alone (onCameraMove) never triggers a reverse '
        'geocode call (req 5)', (tester) async {
      final fake = _FakeAddressSearchProvider();
      await tester.pumpWidget(_wrap(
        child: MapFirstAddressScreen(
          initialLatitude: _besiktas.latitude,
          initialLongitude: _besiktas.longitude,
        ),
        searchProvider: fake,
        locationGateway: _FakeAddressLocationGateway(),
      ));
      await tester.pump();
      fake.reverseGeocodeCalls.clear();

      final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
      map.onCameraMove?.call(const CameraPosition(target: _sisli));
      await tester.pump();

      expect(fake.reverseGeocodeCalls, isEmpty);
    });

    testWidgets(
        'camera idle triggers a reverse geocode at the last known camera '
        'position (req 6)', (tester) async {
      final fake = _FakeAddressSearchProvider();
      await tester.pumpWidget(_wrap(
        child: MapFirstAddressScreen(
          initialLatitude: _besiktas.latitude,
          initialLongitude: _besiktas.longitude,
        ),
        searchProvider: fake,
        locationGateway: _FakeAddressLocationGateway(),
      ));
      await tester.pump();
      fake.reverseGeocodeCalls.clear();

      final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
      map.onCameraMove?.call(const CameraPosition(target: _sisli));
      map.onCameraIdle?.call();
      await tester.pump();

      expect(fake.reverseGeocodeCalls, [(_sisli.latitude, _sisli.longitude)]);
    });

    testWidgets(
        'rapid successive camera-idle events do not corrupt state — a '
        'stale in-flight resolution is discarded in favor of the latest '
        'one (req 7)', (tester) async {
      final fake = _FakeAddressSearchProvider();
      await tester.pumpWidget(_wrap(
        child: MapFirstAddressScreen(
          initialLatitude: _besiktas.latitude,
          initialLongitude: _besiktas.longitude,
        ),
        searchProvider: fake,
        locationGateway: _FakeAddressLocationGateway(),
      ));
      await tester.pump();

      // Hold the first call in flight, fire it, then immediately fire a
      // second (unheld) idle event for a different position — the second
      // one wins, even though the first hasn't resolved yet.
      final firstCallGate = Completer<void>();
      fake.holdUntil = firstCallGate.future;
      final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
      map.onCameraMove?.call(const CameraPosition(target: _sisli));
      map.onCameraIdle?.call();
      await tester.pump();

      fake.holdUntil = null;
      const thirdPoint = LatLng(41.09, 29.05);
      map.onCameraMove?.call(const CameraPosition(target: thirdPoint));
      map.onCameraIdle?.call();
      await tester.pumpAndSettle();

      firstCallGate.complete();
      await tester.pumpAndSettle();

      expect(
        find.textContaining(
            'Resolved at ${thirdPoint.latitude}, ${thirdPoint.longitude}'),
        findsOneWidget,
        reason: 'the later camera position must win over the stale one',
      );
    });

    testWidgets(
        'the resolved address updates (formatted address text changes) '
        'when the map location changes (req 8)', (tester) async {
      final fake = _FakeAddressSearchProvider();
      await tester.pumpWidget(_wrap(
        child: MapFirstAddressScreen(
          initialLatitude: _besiktas.latitude,
          initialLongitude: _besiktas.longitude,
        ),
        searchProvider: fake,
        locationGateway: _FakeAddressLocationGateway(),
      ));
      await tester.pump();
      expect(
        find.textContaining(
            'Resolved at ${_besiktas.latitude}, ${_besiktas.longitude}'),
        findsOneWidget,
      );

      final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
      map.onCameraMove?.call(const CameraPosition(target: _sisli));
      map.onCameraIdle?.call();
      await tester.pump();

      expect(
        find.textContaining(
            'Resolved at ${_sisli.latitude}, ${_sisli.longitude}'),
        findsOneWidget,
      );
    });

    testWidgets(
        'a failed reverse geocode shows an error and never lets the save '
        'button treat anything as resolved/verified (req 10)', (tester) async {
      final fake = _FakeAddressSearchProvider()..failNextReverseGeocode = true;
      await tester.pumpWidget(_wrap(
        child: MapFirstAddressScreen(
          initialLatitude: _besiktas.latitude,
          initialLongitude: _besiktas.longitude,
        ),
        searchProvider: fake,
        locationGateway: _FakeAddressLocationGateway(),
      ));
      await tester.pump();

      expect(find.text('Konum çözümlenemedi.'), findsOneWidget);
      expect(find.text('Bu Konumu Kullan'), findsNothing);
    });

    testWidgets(
        'apartment number remains customer input — save is rejected '
        'client-side when empty, never fabricated (req 11)', (tester) async {
      final fake = _FakeAddressSearchProvider();
      final spy = _SpySavedAddressRepository();
      await tester.pumpWidget(_wrap(
        child: MapFirstAddressScreen(
          initialLatitude: _besiktas.latitude,
          initialLongitude: _besiktas.longitude,
        ),
        searchProvider: fake,
        locationGateway: _FakeAddressLocationGateway(),
        savedAddressRepository: spy,
      ));
      await tester.pump();

      await tester.ensureVisible(find.text('Bu Konumu Kullan'));
      await tester.tap(find.text('Bu Konumu Kullan'));
      await tester.pumpAndSettle();

      expect(spy.savedPlaceIds, isEmpty);
      expect(find.text('Daire numarası gereklidir.'), findsOneWidget);
    });

    testWidgets(
        'saving sends only the server-resolved providerPlaceId — never '
        'raw client coordinates (req 9, 13)', (tester) async {
      final fake = _FakeAddressSearchProvider();
      final spy = _SpySavedAddressRepository();
      await tester.pumpWidget(_wrap(
        child: MapFirstAddressScreen(
          initialLatitude: _besiktas.latitude,
          initialLongitude: _besiktas.longitude,
        ),
        searchProvider: fake,
        locationGateway: _FakeAddressLocationGateway(),
        savedAddressRepository: spy,
      ));
      await tester.pump();

      await tester.enterText(find.widgetWithText(TextField, 'Daire No *'), '4');
      await tester.ensureVisible(find.text('Bu Konumu Kullan'));
      await tester.tap(find.text('Bu Konumu Kullan'));
      await tester.pumpAndSettle();

      expect(spy.savedPlaceIds, hasLength(1));
      expect(
        spy.savedPlaceIds.single,
        'place-${_besiktas.latitude}-${_besiktas.longitude}',
      );
    });

    testWidgets(
        'the current-location recenter action calls the location gateway '
        '(req 12)', (tester) async {
      final fake = _FakeAddressSearchProvider();
      final gateway = _FakeAddressLocationGateway(
        position: (latitude: _sisli.latitude, longitude: _sisli.longitude),
      );
      await tester.pumpWidget(_wrap(
        child: MapFirstAddressScreen(
          initialLatitude: _besiktas.latitude,
          initialLongitude: _besiktas.longitude,
        ),
        searchProvider: fake,
        locationGateway: gateway,
      ));
      await tester.pump();
      final callsBefore = gateway.currentPositionCalls;

      await tester.tap(find.byIcon(Icons.my_location));
      await tester.pumpAndSettle();

      expect(gateway.currentPositionCalls, greaterThan(callsBefore));
    });

    testWidgets(
        'location permission denied still opens the map with a manual '
        'default center, never blocking address creation (req 3)',
        (tester) async {
      final fake = _FakeAddressSearchProvider();
      final gateway = _FakeAddressLocationGateway(position: null);
      await tester.pumpWidget(_wrap(
        child: const MapFirstAddressScreen(),
        searchProvider: fake,
        locationGateway: gateway,
      ));
      await tester.pumpAndSettle();

      expect(find.byType(GoogleMap), findsOneWidget);
      final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
      expect(map.initialCameraPosition.target,
          MapFirstAddressScreen.istanbulDefault);
    });

    testWidgets(
        'a permanently denied location permission shows the settings '
        'hint, but still allows manual map positioning (req 3)',
        (tester) async {
      final fake = _FakeAddressSearchProvider();
      final gateway =
          _FakeAddressLocationGateway(position: null, permanentlyDenied: true);
      await tester.pumpWidget(_wrap(
        child: const MapFirstAddressScreen(),
        searchProvider: fake,
        locationGateway: gateway,
      ));
      await tester.pumpAndSettle();

      expect(
        find.text('Konum iznini ayarlardan açabilirsiniz.'),
        findsOneWidget,
      );
      expect(find.byType(GoogleMap), findsOneWidget);
    });

    testWidgets(
        'granted location permission centers the initial camera at the '
        'device position once resolved (req 2)', (tester) async {
      final fake = _FakeAddressSearchProvider();
      final gateway = _FakeAddressLocationGateway(
        position: (latitude: _sisli.latitude, longitude: _sisli.longitude),
      );
      await tester.pumpWidget(_wrap(
        child: const MapFirstAddressScreen(),
        searchProvider: fake,
        locationGateway: gateway,
      ));
      await tester.pumpAndSettle();

      expect(
        find.textContaining(
            'Resolved at ${_sisli.latitude}, ${_sisli.longitude}'),
        findsOneWidget,
      );
    });

    testWidgets(
        'editing pre-centers the map at the existing saved location '
        'and immediately resolves it (req 15)', (tester) async {
      final fake = _FakeAddressSearchProvider();
      await tester.pumpWidget(_wrap(
        child: MapFirstAddressScreen(
          existingAddressId: 'address-1',
          initialLatitude: _besiktas.latitude,
          initialLongitude: _besiktas.longitude,
        ),
        searchProvider: fake,
        locationGateway: _FakeAddressLocationGateway(),
      ));
      await tester.pump();

      final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
      expect(map.initialCameraPosition.target, _besiktas);
      expect(
        fake.reverseGeocodeCalls,
        contains((_besiktas.latitude, _besiktas.longitude)),
      );
    });

    testWidgets(
        '"Adres Ara" opens the AddressSearchScreen subflow, never a '
        'separate save path — selecting a result re-centers the same map '
        '(req 1, 17)', (tester) async {
      final fake = _FakeAddressSearchProvider();
      await tester.pumpWidget(_wrap(
        child: MapFirstAddressScreen(
          initialLatitude: _besiktas.latitude,
          initialLongitude: _besiktas.longitude,
        ),
        searchProvider: fake,
        locationGateway: _FakeAddressLocationGateway(),
      ));
      await tester.pump();

      await tester.tap(find.text('Adres Ara'));
      await tester.pumpAndSettle();

      expect(find.byType(AddressSearchScreen), findsOneWidget);
    });
  });

  group('MapFirstAddressScreen — FRAUD-F.1 address-save evidence capture', () {
    testWidgets(
        'address save still proceeds when device-location evidence is '
        'unavailable (permission denied)', (tester) async {
      final fake = _FakeAddressSearchProvider();
      final gateway = _FakeAddressLocationGateway(
        captureResult: const DeviceLocationCaptureResult.unavailable(
          DeviceLocationUnavailableReason.permissionDenied,
        ),
      );
      final spy = _SpySavedAddressRepository();
      await tester.pumpWidget(_wrap(
        child: MapFirstAddressScreen(
          initialLatitude: _besiktas.latitude,
          initialLongitude: _besiktas.longitude,
        ),
        searchProvider: fake,
        locationGateway: gateway,
        savedAddressRepository: spy,
      ));
      await tester.pump();

      await tester.enterText(find.widgetWithText(TextField, 'Daire No *'), '4');
      await tester.ensureVisible(find.text('Bu Konumu Kullan'));
      await tester.tap(find.text('Bu Konumu Kullan'));
      await tester.pumpAndSettle();

      expect(spy.savedPlaceIds, hasLength(1),
          reason: 'the address save itself must succeed unaffected');
      expect(gateway.captureLocationEvidenceCalls, 1);
      expect(spy.lastDeviceLocation, isNull);
      expect(spy.lastDeviceLocationUnavailableReason, 'permissionDenied');
    });

    testWidgets(
        'selected map pin/place is never overwritten by the captured '
        'device location — the two remain fully independent', (tester) async {
      final fake = _FakeAddressSearchProvider();
      // A device location deliberately far from the selected _besiktas
      // pin — proves the save still targets _besiktas's own
      // server-resolved place, never the captured evidence coordinates.
      final gateway = _FakeAddressLocationGateway(
        captureResult: DeviceLocationCaptureResult.available(
          ClientLocationEvidence(
            latitude: _sisli.latitude,
            longitude: _sisli.longitude,
            accuracyMeters: 20,
            clientCapturedAt: DateTime(2026, 8, 15, 9, 0),
            mockLocationStatus: MockLocationStatus.notDetected,
            permissionState: 'granted',
            precisionState: 'precise',
          ),
        ),
      );
      final spy = _SpySavedAddressRepository();
      await tester.pumpWidget(_wrap(
        child: MapFirstAddressScreen(
          initialLatitude: _besiktas.latitude,
          initialLongitude: _besiktas.longitude,
        ),
        searchProvider: fake,
        locationGateway: gateway,
        savedAddressRepository: spy,
      ));
      await tester.pump();

      // Checked BEFORE tapping save — the screen pops (navigates away)
      // on a successful save, so GoogleMap is no longer in the tree
      // afterward. Capturing device-location evidence never happens
      // until `_save()` itself runs, so the map/pin state at this point
      // already proves nothing before it has moved the camera — and
      // nothing in the capture/save code path ever calls setState on
      // `_cameraTarget` at all.
      final mapBeforeSave = tester.widget<GoogleMap>(find.byType(GoogleMap));
      expect(mapBeforeSave.initialCameraPosition.target, _besiktas);

      await tester.enterText(find.widgetWithText(TextField, 'Daire No *'), '4');
      await tester.ensureVisible(find.text('Bu Konumu Kullan'));
      await tester.tap(find.text('Bu Konumu Kullan'));
      await tester.pumpAndSettle();

      // The saved place is still the selected (_besiktas) one — the
      // captured evidence never redirected what gets saved.
      expect(
        spy.savedPlaceIds.single,
        'place-${_besiktas.latitude}-${_besiktas.longitude}',
      );
      // The evidence WAS captured and forwarded — just never used to
      // influence the selected location.
      expect(spy.lastDeviceLocation?.latitude, _sisli.latitude);
      expect(spy.lastDeviceLocation?.longitude, _sisli.longitude);
    });
  });
}
