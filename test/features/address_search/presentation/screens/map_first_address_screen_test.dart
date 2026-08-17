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
const _kadikoy = LatLng(40.9922, 29.0244);

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

  /// Simulates the physical-device report: a raw, non-`AddressSearchException`
  /// error (e.g. a plugin-internal `ExecutionException`) reaching this
  /// provider's caller — proves the screen never renders it verbatim.
  bool throwRawErrorOnNextReverseGeocode = false;
  bool Function(LatLng)? sufficientlyResolvedOverride;

  /// When set, `reverseGeocode` waits on this instead of resolving
  /// immediately — lets a test control exactly when an in-flight call
  /// completes, to simulate two overlapping requests racing.
  Future<void>? holdUntil;

  final List<String> autocompleteCalls = [];

  /// Query-aware, mirroring the real (fixed) backend fixture — Paket
  /// Servis P.3 §D14: two different queries must resolve to two
  /// genuinely different suggestions/places, never the same one
  /// regardless of what was typed (the original "Adres Ara" bug).
  @override
  Future<List<AddressSuggestion>> autocomplete({
    required String input,
    required String sessionToken,
  }) async {
    autocompleteCalls.add(input);
    final normalized = input.toLowerCase();
    if (normalized.contains('kadıköy') || normalized.contains('kadikoy')) {
      return const [
        AddressSuggestion(
          providerPlaceId: 'fixture-kadikoy',
          text: 'Caferağa, Moda Cd. No:12, Kadıköy/İstanbul, Türkiye',
        ),
      ];
    }
    if (input.trim().isEmpty) return [];
    return const [
      AddressSuggestion(
        providerPlaceId: 'fixture-besiktas',
        text: 'Balmumcu, Barbaros Bulvarı No:74, Beşiktaş/İstanbul, Türkiye',
      ),
    ];
  }

  @override
  Future<ResolvedAddress> resolvePlace({
    required String placeId,
    required String sessionToken,
  }) async {
    if (placeId == 'fixture-kadikoy') return _resolvedFor(_kadikoy);
    return _resolvedFor(_besiktas);
  }

  @override
  Future<ResolvedAddress> reverseGeocode({
    required double latitude,
    required double longitude,
  }) async {
    reverseGeocodeCalls.add((latitude, longitude));
    if (holdUntil != null) await holdUntil;
    if (throwRawErrorOnNextReverseGeocode) {
      // Deliberately NOT an AddressSearchException — a raw plugin/platform-
      // shaped error, matching the physical-device report exactly.
      throw Exception(
        'java.util.concurrent.ExecutionException: com.google.firebase.functions.FirebaseFunctionsException: INTERNAL',
      );
    }
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
    this.currentPositionDelay,
    this.captureResult = const DeviceLocationCaptureResult.unavailable(
      DeviceLocationUnavailableReason.permissionDenied,
    ),
  });

  ({double latitude, double longitude})? position;
  bool permanentlyDenied;
  int currentPositionCalls = 0;

  /// When set, [currentPosition] waits on this before resolving — lets a
  /// test simulate a device-location fix that genuinely arrives after the
  /// map/controller already exist (Paket Servis P.3 §D16, test scenario
  /// 5), rather than always resolving synchronously-ish like a real
  /// `Geolocator.getCurrentPosition()` call practically never does.
  Future<void>? currentPositionDelay;

  /// FRAUD-F.1 — the fake result [captureLocationEvidence] returns.
  /// Defaults to "unavailable" so existing tests (written before FRAUD-F.1
  /// existed) keep exercising the "no candidate" path, matching this
  /// gateway's own real "never fabricate coordinates" default posture.
  DeviceLocationCaptureResult captureResult;
  int captureLocationEvidenceCalls = 0;

  @override
  Future<({double latitude, double longitude})?> currentPosition() async {
    currentPositionCalls++;
    if (currentPositionDelay != null) await currentPositionDelay;
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
  _SpySavedAddressRepository({this.seed = const []});

  final List<String> savedPlaceIds = [];
  ClientLocationEvidence? lastDeviceLocation;
  String? lastDeviceLocationUnavailableReason;

  /// Pre-existing saved addresses "already on the account" — Paket Servis
  /// P.3 §D16's exact scenario: proves `MapFirstAddressScreen` in NEW
  /// ADDRESS mode never reads this list at all, regardless of what it
  /// contains (a previously saved Kadıköy address, in particular, must
  /// never leak into the NEW ADDRESS initial camera position).
  List<SavedAddress> seed;

  /// Simulates the same class of physical-device failure as
  /// `_FakeAddressSearchProvider.throwRawErrorOnNextReverseGeocode`, for
  /// the address-save call specifically — a raw, non-`SavedAddressException`
  /// error (e.g. a blocked-cleartext-connection platform exception).
  bool throwRawErrorOnNextSave = false;

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
    if (throwRawErrorOnNextSave) {
      throw Exception(
        'java.util.concurrent.ExecutionException: java.io.IOException: Cleartext HTTP traffic not permitted',
      );
    }
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
  Future<List<SavedAddress>> listForCurrentUser() async => seed;

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
        'the address card never visually covers the fixed pin — collapsed '
        'state (address card redesign)', (tester) async {
      await tester.pumpWidget(_wrap(
        child: MapFirstAddressScreen(
          initialLatitude: _besiktas.latitude,
          initialLongitude: _besiktas.longitude,
        ),
        searchProvider: _FakeAddressSearchProvider(),
        locationGateway: _FakeAddressLocationGateway(),
      ));
      await tester.pump();

      final pinRect = tester.getRect(find.byIcon(Icons.location_on));
      final cardRect =
          tester.getRect(find.byKey(const Key('address-info-card')));

      expect(
        cardRect.overlaps(pinRect),
        isFalse,
        reason: 'the collapsed card must not overlap the fixed pin',
      );
      expect(
        cardRect.top,
        greaterThanOrEqualTo(pinRect.bottom),
        reason: 'the card must sit entirely below the pin, not merely avoid '
            'overlapping it in some other direction',
      );
    });

    testWidgets(
        'the address card never covers the pin, and the area above it '
        'stays visible — expanded state (address card redesign)',
        (tester) async {
      await tester.pumpWidget(_wrap(
        child: MapFirstAddressScreen(
          initialLatitude: _besiktas.latitude,
          initialLongitude: _besiktas.longitude,
        ),
        searchProvider: _FakeAddressSearchProvider(),
        locationGateway: _FakeAddressLocationGateway(),
      ));
      await tester.pump();

      final collapsedCardRect =
          tester.getRect(find.byKey(const Key('address-info-card')));

      await tester.tap(find.byKey(const Key('address-card-expand-toggle')));
      await tester.pumpAndSettle();

      final pinRect = tester.getRect(find.byIcon(Icons.location_on));
      final expandedCardRect =
          tester.getRect(find.byKey(const Key('address-info-card')));

      expect(
        expandedCardRect.overlaps(pinRect),
        isFalse,
        reason: 'the expanded card must still never overlap the fixed pin',
      );
      expect(
        expandedCardRect.top,
        greaterThanOrEqualTo(pinRect.bottom),
        reason: 'the pin, and the map area above it, must remain visible '
            'even when the card is fully expanded',
      );
      expect(
        expandedCardRect.height,
        greaterThan(collapsedCardRect.height),
        reason: 'sanity check that expanding actually grew the card',
      );
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
        'a raw, non-AddressSearchException reverse-geocode failure (e.g. a '
        'plugin-internal ExecutionException) never renders raw technical '
        'text — only the safe Turkish fallback', (tester) async {
      final fake = _FakeAddressSearchProvider()
        ..throwRawErrorOnNextReverseGeocode = true;
      await tester.pumpWidget(_wrap(
        child: MapFirstAddressScreen(
          initialLatitude: _besiktas.latitude,
          initialLongitude: _besiktas.longitude,
        ),
        searchProvider: fake,
        locationGateway: _FakeAddressLocationGateway(),
      ));
      await tester.pump();

      expect(find.text('Konum çözümlenemedi. Lütfen tekrar deneyin.'),
          findsOneWidget);
      expect(find.text('Bu Konumu Kullan'), findsNothing);
      expect(find.textContaining('ExecutionException'), findsNothing);
      expect(find.textContaining('FirebaseFunctionsException'), findsNothing);
      expect(find.textContaining('java.'), findsNothing);
      expect(find.textContaining('Exception:'), findsNothing);
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

      await tester.tap(find.byKey(const Key('address-card-expand-toggle')));
      await tester.pumpAndSettle();

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

      await tester.tap(find.byKey(const Key('address-card-expand-toggle')));
      await tester.pumpAndSettle();

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
        'a raw, non-SavedAddressException save failure (e.g. a blocked-'
        'cleartext-connection platform exception) never renders raw '
        'technical text — only the safe Turkish fallback (P.3 map-routing '
        'device-blocker audit)', (tester) async {
      final fake = _FakeAddressSearchProvider();
      final spy = _SpySavedAddressRepository()..throwRawErrorOnNextSave = true;
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

      await tester.tap(find.byKey(const Key('address-card-expand-toggle')));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, 'Daire No *'), '4');
      await tester.ensureVisible(find.text('Bu Konumu Kullan'));
      await tester.tap(find.text('Bu Konumu Kullan'));
      await tester.pumpAndSettle();

      expect(spy.savedPlaceIds, isEmpty);
      expect(
        find.text('Adres kaydedilemedi. Lütfen tekrar deneyin.'),
        findsOneWidget,
      );
      expect(find.textContaining('ExecutionException'), findsNothing);
      expect(find.textContaining('IOException'), findsNothing);
      expect(find.textContaining('Cleartext'), findsNothing);
      expect(find.textContaining('java.'), findsNothing);
      expect(find.textContaining('Exception:'), findsNothing);
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
        'a programmatic recenter (current-location button) never locks '
        'out a later manual drag — onCameraMove/onCameraIdle keep working '
        'and resolve the newer manual position (P.3 map-dynamic-address '
        'audit)', (tester) async {
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

      // Programmatic recenter first.
      await tester.tap(find.byIcon(Icons.my_location));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
            'Resolved at ${_sisli.latitude}, ${_sisli.longitude}'),
        findsOneWidget,
      );

      // A manual drag afterwards must still update the resolved address —
      // the recenter must not leave the map "locked" to its own position.
      const manualPoint = LatLng(41.09, 29.05);
      final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
      map.onCameraMove?.call(const CameraPosition(target: manualPoint));
      map.onCameraIdle?.call();
      await tester.pumpAndSettle();

      expect(
        find.textContaining(
            'Resolved at ${manualPoint.latitude}, ${manualPoint.longitude}'),
        findsOneWidget,
        reason: 'manual movement after a programmatic recenter must still '
            'resolve to the new, manually-selected point',
      );
    });

    testWidgets(
        'a programmatic recenter via "Adres Ara" never locks out a later '
        'manual drag either (P.3 map-dynamic-address audit)', (tester) async {
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
      Navigator.of(tester.element(find.byType(AddressSearchScreen)))
          .pop(_sisli);
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
            'Resolved at ${_sisli.latitude}, ${_sisli.longitude}'),
        findsOneWidget,
      );

      const manualPoint = LatLng(41.09, 29.05);
      final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
      map.onCameraMove?.call(const CameraPosition(target: manualPoint));
      map.onCameraIdle?.call();
      await tester.pumpAndSettle();

      expect(
        find.textContaining(
            'Resolved at ${manualPoint.latitude}, ${manualPoint.longitude}'),
        findsOneWidget,
        reason: 'manual movement after "Adres Ara" recentering must still '
            'resolve to the new, manually-selected point',
      );
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
  });

  group(
      'MapFirstAddressScreen — NEW ADDRESS vs EDIT initial-position '
      'semantics (Paket Servis P.3 §D16)', () {
    SavedAddress kadikoySavedAddress() => SavedAddress(
          id: 'saved-kadikoy',
          customerId: 'uid-1',
          label: 'Ev',
          provinceName: 'İstanbul',
          districtName: 'Kadıköy',
          apartmentNo: '3',
          latitude: _kadikoy.latitude,
          longitude: _kadikoy.longitude,
          verificationStatus: AddressVerificationStatus.verified,
          providerSource: 'google_places',
        );

    testWidgets(
        'scenario 2: a saved Kadıköy address exists + current device '
        'location is Beşiktaş -> NEW ADDRESS starts at Beşiktaş, NOT '
        'Kadıköy', (tester) async {
      final fake = _FakeAddressSearchProvider();
      final gateway = _FakeAddressLocationGateway(
        position: (
          latitude: _besiktas.latitude,
          longitude: _besiktas.longitude,
        ),
      );
      final savedAddressRepository = _SpySavedAddressRepository(
        seed: [kadikoySavedAddress()],
      );
      await tester.pumpWidget(_wrap(
        child: const MapFirstAddressScreen(), // NEW ADDRESS — no args.
        searchProvider: fake,
        locationGateway: gateway,
        savedAddressRepository: savedAddressRepository,
      ));
      await tester.pumpAndSettle();

      expect(
        find.textContaining(
            'Resolved at ${_besiktas.latitude}, ${_besiktas.longitude}'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
            'Resolved at ${_kadikoy.latitude}, ${_kadikoy.longitude}'),
        findsNothing,
        reason: 'the saved Kadıköy address must never leak into NEW '
            'ADDRESS\'s initial camera position',
      );
    });

    testWidgets(
        'scenario 3: editing the saved Kadıköy address starts the map at '
        'the saved Kadıköy coordinate', (tester) async {
      final fake = _FakeAddressSearchProvider();
      await tester.pumpWidget(_wrap(
        child: MapFirstAddressScreen(
          existingAddressId: 'saved-kadikoy',
          initialLatitude: _kadikoy.latitude,
          initialLongitude: _kadikoy.longitude,
        ),
        searchProvider: fake,
        locationGateway: _FakeAddressLocationGateway(),
      ));
      await tester.pumpAndSettle();

      final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
      expect(map.initialCameraPosition.target, _kadikoy);
      expect(
        find.textContaining(
            'Resolved at ${_kadikoy.latitude}, ${_kadikoy.longitude}'),
        findsOneWidget,
      );
    });

    testWidgets(
        'scenario 4: current location unavailable + a saved Kadıköy '
        'address exists -> the saved address is NOT presented as current '
        'location; the neutral Istanbul default is used instead',
        (tester) async {
      final fake = _FakeAddressSearchProvider();
      final gateway = _FakeAddressLocationGateway(position: null);
      final savedAddressRepository = _SpySavedAddressRepository(
        seed: [kadikoySavedAddress()],
      );
      await tester.pumpWidget(_wrap(
        child: const MapFirstAddressScreen(),
        searchProvider: fake,
        locationGateway: gateway,
        savedAddressRepository: savedAddressRepository,
      ));
      await tester.pumpAndSettle();

      final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
      expect(
        map.initialCameraPosition.target,
        MapFirstAddressScreen.istanbulDefault,
      );
      expect(
        find.textContaining(
            'Resolved at ${_kadikoy.latitude}, ${_kadikoy.longitude}'),
        findsNothing,
        reason: 'an unavailable device location must never fall back to a '
            'previously saved address',
      );
    });

    testWidgets(
        'scenario 5: current location arrives asynchronously after the map '
        'is already created -> the map still recenters correctly',
        (tester) async {
      final fake = _FakeAddressSearchProvider();
      final locationGate = Completer<void>();
      final gateway = _FakeAddressLocationGateway(
        position: (
          latitude: _besiktas.latitude,
          longitude: _besiktas.longitude,
        ),
        currentPositionDelay: locationGate.future,
      );
      await tester.pumpWidget(_wrap(
        child: const MapFirstAddressScreen(),
        searchProvider: fake,
        locationGateway: gateway,
      ));
      await tester.pump();
      // The map (and its controller, via onMapCreated) already exists —
      // the device-location fix has not resolved yet.
      expect(find.byType(GoogleMap), findsOneWidget);
      expect(
        find.textContaining(
            'Resolved at ${_besiktas.latitude}, ${_besiktas.longitude}'),
        findsNothing,
      );

      locationGate.complete();
      await tester.pumpAndSettle();

      expect(
        find.textContaining(
            'Resolved at ${_besiktas.latitude}, ${_besiktas.longitude}'),
        findsOneWidget,
      );
    });

    testWidgets(
        'scenario 6: a stale prior search result cannot override a fresh '
        'device location on a NEW route instance', (tester) async {
      final fake = _FakeAddressSearchProvider();
      final gateway = _FakeAddressLocationGateway(
        position: (
          latitude: _besiktas.latitude,
          longitude: _besiktas.longitude,
        ),
      );

      // First instance: search for Kadıköy and recenter there, exactly
      // like a customer would in one visit to this screen.
      await tester.pumpWidget(_wrap(
        child: const MapFirstAddressScreen(),
        searchProvider: fake,
        locationGateway: gateway,
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Adres Ara'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Kadıköy');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await tester.tap(
          find.text('Caferağa, Moda Cd. No:12, Kadıköy/İstanbul, Türkiye'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
            'Resolved at ${_kadikoy.latitude}, ${_kadikoy.longitude}'),
        findsOneWidget,
      );

      // A completely fresh route instance (e.g. the customer left and
      // came back to "Yeni Adres Ekle" again) must start over cleanly —
      // no leftover Kadıköy state from the first instance/State object.
      // A distinct Key forces Flutter to discard the previous element/
      // State entirely rather than merely calling didUpdateWidget on the
      // existing one (which pumpWidget-ing an identically-shaped tree
      // would otherwise do) — the same distinction a real Navigator.push
      // of a brand new route makes automatically.
      await tester.pumpWidget(_wrap(
        child: MapFirstAddressScreen(key: UniqueKey()),
        searchProvider: fake,
        locationGateway: gateway,
      ));
      await tester.pumpAndSettle();

      expect(
        find.textContaining(
            'Resolved at ${_besiktas.latitude}, ${_besiktas.longitude}'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
            'Resolved at ${_kadikoy.latitude}, ${_kadikoy.longitude}'),
        findsNothing,
        reason: 'a fresh MapFirstAddressScreen instance must never retain '
            'the previous instance\'s search-driven state',
      );
    });
  });

  group('MapFirstAddressScreen — Faz P.2.1.2 map-first UX (continued)', () {
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

  group(
      'MapFirstAddressScreen — "Adres Ara" full round-trip (Paket Servis '
      'P.3 §D14 — the AddressSearchScreen UI itself, not a bypassed pop)', () {
    testWidgets(
        'searching for address A, selecting it, recenters the canonical '
        'map and resolves address A — real AddressSearchScreen UI, not a '
        'bypassed Navigator.pop', (tester) async {
      final fake = _FakeAddressSearchProvider();
      await tester.pumpWidget(_wrap(
        child: MapFirstAddressScreen(
          initialLatitude: _sisli.latitude,
          initialLongitude: _sisli.longitude,
        ),
        searchProvider: fake,
        locationGateway: _FakeAddressLocationGateway(),
      ));
      await tester.pump();

      await tester.tap(find.text('Adres Ara'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Barbaros Bulvarı');
      await tester.pump(const Duration(milliseconds: 400)); // debounce
      await tester.pumpAndSettle();

      expect(
        find.text(
            'Balmumcu, Barbaros Bulvarı No:74, Beşiktaş/İstanbul, Türkiye'),
        findsOneWidget,
      );
      await tester.tap(find.text(
          'Balmumcu, Barbaros Bulvarı No:74, Beşiktaş/İstanbul, Türkiye'));
      await tester.pumpAndSettle();

      // Back on the canonical map screen, never a second screen.
      expect(find.byType(AddressSearchScreen), findsNothing);
      expect(find.byType(MapFirstAddressScreen), findsOneWidget);
      expect(
        find.textContaining(
            'Resolved at ${_besiktas.latitude}, ${_besiktas.longitude}'),
        findsOneWidget,
      );
    });

    testWidgets(
        'searching for a materially different address B, selecting it, '
        'recenters the map to B — never collapses onto the same result '
        'address A would produce', (tester) async {
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
      // The screen already shows the Beşiktaş address before searching —
      // this is the exact "stale previous address" the physical-device
      // report described still being visible after a search.
      expect(
        find.textContaining(
            'Resolved at ${_besiktas.latitude}, ${_besiktas.longitude}'),
        findsOneWidget,
      );

      await tester.tap(find.text('Adres Ara'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Kadıköy');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(
        find.text('Caferağa, Moda Cd. No:12, Kadıköy/İstanbul, Türkiye'),
        findsOneWidget,
      );
      await tester.tap(
          find.text('Caferağa, Moda Cd. No:12, Kadıköy/İstanbul, Türkiye'));
      await tester.pumpAndSettle();

      // The map genuinely recentered to B, not stuck showing A.
      expect(
        find.textContaining(
            'Resolved at ${_besiktas.latitude}, ${_besiktas.longitude}'),
        findsNothing,
        reason: 'the previous (Beşiktaş) address must not remain shown as '
            'if it were the newly resolved one',
      );
      expect(
        find.textContaining(
            'Resolved at ${_kadikoy.latitude}, ${_kadikoy.longitude}'),
        findsOneWidget,
      );
    });

    testWidgets(
        'after a search-driven recenter, manual dragging the map still '
        'works and continues resolving new addresses', (tester) async {
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
      await tester.enterText(find.byType(TextField), 'Kadıköy');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await tester.tap(
          find.text('Caferağa, Moda Cd. No:12, Kadıköy/İstanbul, Türkiye'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
            'Resolved at ${_kadikoy.latitude}, ${_kadikoy.longitude}'),
        findsOneWidget,
      );

      const manualPoint = LatLng(41.09, 29.05);
      final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
      map.onCameraMove?.call(const CameraPosition(target: manualPoint));
      map.onCameraIdle?.call();
      await tester.pumpAndSettle();

      expect(
        find.textContaining(
            'Resolved at ${manualPoint.latitude}, ${manualPoint.longitude}'),
        findsOneWidget,
        reason: 'manual drag must still work after a search-driven recenter',
      );
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

      await tester.tap(find.byKey(const Key('address-card-expand-toggle')));
      await tester.pumpAndSettle();

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

      await tester.tap(find.byKey(const Key('address-card-expand-toggle')));
      await tester.pumpAndSettle();

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
