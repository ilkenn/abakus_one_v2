import 'package:abakus_one_v2/core/fraud/domain/fraud_evidence.dart';
import 'package:abakus_one_v2/features/address_search/data/address_search_exception.dart';
import 'package:abakus_one_v2/features/address_search/domain/models/address_suggestion.dart';
import 'package:abakus_one_v2/features/address_search/domain/models/resolved_address.dart';
import 'package:abakus_one_v2/features/address_search/domain/services/address_search_provider.dart';
import 'package:abakus_one_v2/features/address_search/presentation/providers/address_search_provider.dart';
import 'package:abakus_one_v2/features/address_search/presentation/screens/address_details_form_screen.dart';
import 'package:abakus_one_v2/features/orders/data/saved_address_repository.dart';
import 'package:abakus_one_v2/features/orders/domain/models/saved_address.dart';
import 'package:abakus_one_v2/features/orders/presentation/providers/saved_address_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

ResolvedAddress _resolvedFixture(
    {bool sufficientlyResolved = true, String placeId = 'place-original'}) {
  return ResolvedAddress(
    providerPlaceId: placeId,
    formattedAddress: 'Balmumcu, Barbaros Blv. No:74, Beşiktaş/İstanbul',
    provinceName: 'İstanbul',
    districtName: sufficientlyResolved ? 'Beşiktaş' : null,
    neighborhoodName: 'Balmumcu',
    routeName: 'Barbaros Bulvarı',
    streetNumber: '74',
    latitude: 41.0449616,
    longitude: 29.0076831,
    isSufficientlyResolved: sufficientlyResolved,
  );
}

class _FakeAddressSearchProvider implements AddressSearchProvider {
  _FakeAddressSearchProvider({this.resolveResult, this.reverseGeocodeResult});

  ResolvedAddress? resolveResult;
  ResolvedAddress? reverseGeocodeResult;
  final List<(double, double)> reverseGeocodeCalls = [];

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
  }) async {
    final result = resolveResult;
    if (result == null) {
      throw const AddressSearchException('not-found', 'not found');
    }
    return result;
  }

  @override
  Future<ResolvedAddress> reverseGeocode({
    required double latitude,
    required double longitude,
  }) async {
    reverseGeocodeCalls.add((latitude, longitude));
    final result = reverseGeocodeResult;
    if (result == null) {
      throw const AddressSearchException('not-found', 'not found');
    }
    return result;
  }
}

class _SpySavedAddressRepository implements SavedAddressRepository {
  final List<String> savedPlaceIds = [];

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

void main() {
  group('AddressDetailsFormScreen — Faz P.2.1', () {
    testWidgets('the address summary renders alongside the map (req 3)',
        (tester) async {
      final fake =
          _FakeAddressSearchProvider(resolveResult: _resolvedFixture());
      await tester.pumpWidget(
        ProviderScope(
          overrides: [addressSearchProviderProvider.overrideWithValue(fake)],
          child: const MaterialApp(
            home: AddressDetailsFormScreen(
              providerPlaceId: 'place-original',
              sessionToken: 'session-1',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Barbaros Blv. No:74'), findsOneWidget);
      expect(find.text('Beşiktaş'), findsOneWidget);
      expect(find.byType(GoogleMap), findsOneWidget);
    });

    testWidgets(
        'a moved pin that reverse-geocodes to an insufficiently-resolved '
        'address shows the not-verified warning, never implies it is '
        'verified (req 4)', (tester) async {
      final fake = _FakeAddressSearchProvider(
        resolveResult: _resolvedFixture(),
        reverseGeocodeResult: _resolvedFixture(
            sufficientlyResolved: false, placeId: 'place-moved'),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [addressSearchProviderProvider.overrideWithValue(fake)],
          child: const MaterialApp(
            home: AddressDetailsFormScreen(
              providerPlaceId: 'place-original',
              sessionToken: 'session-1',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
      map.markers.first.onDragEnd?.call(const LatLng(41.06, 29.02));
      await tester.pump();

      await tester.ensureVisible(find.text('Konumu Onayla'));
      await tester.tap(find.text('Konumu Onayla'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('tam olarak dogrulanamadi'),
        findsOneWidget,
      );
    });

    testWidgets(
        'moving the pin without confirming does not change what gets '
        'saved — the original server-resolved placeId is used, never the '
        'raw dragged coordinates (req 5)', (tester) async {
      final fake =
          _FakeAddressSearchProvider(resolveResult: _resolvedFixture());
      final spyRepository = _SpySavedAddressRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            addressSearchProviderProvider.overrideWithValue(fake),
            savedAddressRepositoryProvider.overrideWithValue(spyRepository),
          ],
          child: const MaterialApp(
            home: AddressDetailsFormScreen(
              providerPlaceId: 'place-original',
              sessionToken: 'session-1',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Drag the pin but deliberately never tap "Konumu Onayla".
      final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
      map.markers.first.onDragEnd?.call(const LatLng(41.06, 29.02));
      await tester.pump();

      await tester.enterText(find.widgetWithText(TextField, 'Daire No *'), '4');
      await tester.ensureVisible(find.text('Adresi Kaydet'));
      await tester.tap(find.text('Adresi Kaydet'));
      await tester.pumpAndSettle();

      expect(spyRepository.savedPlaceIds, ['place-original']);
      expect(fake.reverseGeocodeCalls, isEmpty);
    });
  });
}
