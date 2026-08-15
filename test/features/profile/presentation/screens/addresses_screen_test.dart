import 'package:abakus_one_v2/features/address_search/data/address_location_gateway.dart';
import 'package:abakus_one_v2/features/address_search/domain/models/address_suggestion.dart';
import 'package:abakus_one_v2/features/address_search/domain/models/resolved_address.dart';
import 'package:abakus_one_v2/features/address_search/domain/services/address_search_provider.dart';
import 'package:abakus_one_v2/features/address_search/presentation/providers/address_search_provider.dart';
import 'package:abakus_one_v2/features/address_search/presentation/screens/address_search_screen.dart';
import 'package:abakus_one_v2/features/address_search/presentation/screens/map_first_address_screen.dart';
import 'package:abakus_one_v2/features/orders/data/saved_address_repository.dart';
import 'package:abakus_one_v2/features/orders/domain/models/saved_address.dart';
import 'package:abakus_one_v2/features/orders/presentation/providers/saved_address_providers.dart';
import 'package:abakus_one_v2/features/profile/presentation/screens/address_form_screen.dart';
import 'package:abakus_one_v2/features/profile/presentation/screens/addresses_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Faz P.2.1.2 — proves `Profil → Adreslerim` reads the real canonical
/// `SavedAddress` source and its `+`/edit actions route to the map-first
/// canonical flow, never the legacy `AddressFormScreen` or the (now
/// secondary-only) `AddressSearchScreen` as a primary destination.
class _FakeAddressSearchProvider implements AddressSearchProvider {
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
      throw UnimplementedError();

  @override
  Future<ResolvedAddress> reverseGeocode({
    required double latitude,
    required double longitude,
  }) async {
    return ResolvedAddress(
      providerPlaceId: 'place-1',
      formattedAddress: 'Test Address',
      provinceName: 'İstanbul',
      districtName: 'Beşiktaş',
      neighborhoodName: 'Balmumcu',
      routeName: 'Barbaros Bulvarı',
      streetNumber: '74',
      latitude: latitude,
      longitude: longitude,
      isSufficientlyResolved: true,
    );
  }
}

class _FakeAddressLocationGateway implements AddressLocationGateway {
  @override
  Future<({double latitude, double longitude})?> currentPosition() async =>
      null;

  @override
  Future<bool> isPermissionPermanentlyDenied() async => false;
}

class _FakeSavedAddressRepository implements SavedAddressRepository {
  _FakeSavedAddressRepository({this.seed = const []});

  List<SavedAddress> seed;
  final List<String> deletedIds = [];

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
  }) async {
    throw UnimplementedError();
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
  Future<void> delete(String addressId) async {
    deletedIds.add(addressId);
    seed = seed.where((a) => a.id != addressId).toList();
  }
}

Future<void> _pumpAddressesScreen(
  WidgetTester tester, {
  required SavedAddressRepository repository,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        addressSearchProviderProvider.overrideWithValue(
          _FakeAddressSearchProvider(),
        ),
        addressLocationGatewayProvider.overrideWithValue(
          _FakeAddressLocationGateway(),
        ),
        savedAddressRepositoryProvider.overrideWithValue(repository),
      ],
      child: const MaterialApp(home: AddressesScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('AddressesScreen — Faz P.2.1.2 canonical list + map-first routing', () {
    testWidgets(
        '"+" opens the map-first canonical flow — never the legacy '
        'AddressFormScreen, never AddressSearchScreen as a primary '
        'destination (req 1, 17)', (tester) async {
      await _pumpAddressesScreen(
        tester,
        repository: _FakeSavedAddressRepository(),
      );

      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();

      expect(find.byType(MapFirstAddressScreen), findsOneWidget);
      expect(find.byType(AddressFormScreen), findsNothing);
      expect(find.byType(AddressSearchScreen), findsNothing);
    });

    testWidgets(
        'reads the real canonical SavedAddress source, not the '
        'legacy mock AddressModel (req 2)', (tester) async {
      final repository = _FakeSavedAddressRepository(
        seed: const [
          SavedAddress(
            id: 'address-1',
            customerId: 'uid-1',
            label: 'Ev',
            formattedAddress: 'Canonical Test Address, Beşiktaş',
            apartmentNo: '4',
            isDefault: true,
            verificationStatus: AddressVerificationStatus.verified,
          ),
        ],
      );
      await _pumpAddressesScreen(tester, repository: repository);

      expect(find.text('Canonical Test Address, Beşiktaş'), findsOneWidget);
      // Legacy mock's own hardcoded seed ("Moda Caddesi") must not appear.
      expect(find.textContaining('Moda'), findsNothing);
    });

    testWidgets('correct label and default indicator render (req 4, 5)',
        (tester) async {
      final repository = _FakeSavedAddressRepository(
        seed: const [
          SavedAddress(
            id: 'address-1',
            customerId: 'uid-1',
            label: 'İş',
            formattedAddress: 'Work Address',
            apartmentNo: '2',
            isDefault: true,
            verificationStatus: AddressVerificationStatus.verified,
          ),
        ],
      );
      await _pumpAddressesScreen(tester, repository: repository);

      expect(find.text('İş'), findsOneWidget);
      expect(find.text('Varsayılan'), findsOneWidget);
    });

    testWidgets(
        'the edit action opens the map-first flow pre-centered at '
        'the saved location (req 6)', (tester) async {
      final repository = _FakeSavedAddressRepository(
        seed: const [
          SavedAddress(
            id: 'address-1',
            customerId: 'uid-1',
            label: 'Ev',
            formattedAddress: 'Test Address',
            apartmentNo: '4',
            latitude: 41.05,
            longitude: 29.01,
            verificationStatus: AddressVerificationStatus.verified,
          ),
        ],
      );
      await _pumpAddressesScreen(tester, repository: repository);

      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();

      expect(find.byType(MapFirstAddressScreen), findsOneWidget);
      expect(find.byType(AddressFormScreen), findsNothing);
      final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
      expect(map.initialCameraPosition.target, const LatLng(41.05, 29.01));
    });

    testWidgets(
        'delete removes the canonical address and refreshes the '
        'list (req 7)', (tester) async {
      final repository = _FakeSavedAddressRepository(
        seed: const [
          SavedAddress(
            id: 'address-1',
            customerId: 'uid-1',
            label: 'Ev',
            formattedAddress: 'To Be Deleted',
            apartmentNo: '4',
            verificationStatus: AddressVerificationStatus.verified,
          ),
        ],
      );
      await _pumpAddressesScreen(tester, repository: repository);
      expect(find.text('To Be Deleted'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sil'));
      await tester.pumpAndSettle();

      expect(repository.deletedIds, ['address-1']);
      expect(find.text('To Be Deleted'), findsNothing);
    });

    testWidgets(
        'an empty saved-address list shows a friendly empty state '
        '(req 9)', (tester) async {
      await _pumpAddressesScreen(
        tester,
        repository: _FakeSavedAddressRepository(seed: const []),
      );

      expect(find.text('Kayıtlı adresiniz bulunmuyor.'), findsOneWidget);
    });
  });

  group('AddressesScreen — error state (req 10)', () {
    testWidgets(
        'a repository failure shows a safe retry UI, never raw '
        'Firebase error text', (tester) async {
      final container = ProviderContainer(
        overrides: [
          savedAddressRepositoryProvider.overrideWithValue(
            _ThrowingSavedAddressRepository(),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: AddressesScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Adresler yüklenemedi. Lütfen tekrar deneyin.'),
          findsOneWidget);
      expect(find.text('Tekrar Dene'), findsOneWidget);
      expect(find.textContaining('FirebaseException'), findsNothing);
      expect(find.textContaining('Exception:'), findsNothing);
    });
  });
}

class _ThrowingSavedAddressRepository implements SavedAddressRepository {
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
  }) async =>
      throw UnimplementedError();

  @override
  Future<List<SavedAddress>> listForCurrentUser() async {
    throw Exception('simulated network failure');
  }

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
