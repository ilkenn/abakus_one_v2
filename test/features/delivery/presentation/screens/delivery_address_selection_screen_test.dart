import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/core/fraud/domain/fraud_evidence.dart';
import 'package:abakus_one_v2/features/orders/data/saved_address_repository.dart';
import 'package:abakus_one_v2/features/orders/domain/models/saved_address.dart';
import 'package:abakus_one_v2/features/orders/presentation/providers/saved_address_providers.dart';
import 'package:abakus_one_v2/features/delivery/presentation/screens/delivery_address_selection_screen.dart';

/// Paket Servis P.3 — `DeliveryAddressSelectionScreen` only ever selects an
/// address for the current checkout (`Navigator.pop(context, address)`);
/// it never edits/deletes, unlike the profile `AddressesScreen`. Only a
/// verified address is selectable.
class _FakeSavedAddressRepository implements SavedAddressRepository {
  _FakeSavedAddressRepository({this.seed = const []});

  List<SavedAddress> seed;

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
  }) async =>
      throw UnimplementedError();

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

const _verified = SavedAddress(
  id: 'address-verified',
  customerId: 'uid-1',
  label: 'Ev',
  provinceId: 'istanbul',
  provinceName: 'İstanbul',
  districtId: 'besiktas',
  districtName: 'Beşiktaş',
  apartmentNo: '4',
  latitude: 41.05,
  longitude: 29.01,
  verificationStatus: AddressVerificationStatus.verified,
  providerSource: 'google_places',
);

const _unverified = SavedAddress(
  id: 'address-unverified',
  customerId: 'uid-1',
  label: 'İş',
  apartmentNo: '2',
);

void main() {
  testWidgets('doğrulanmış adrese dokununca Navigator.pop ile o adres döner',
      (tester) async {
    SavedAddress? popped;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          savedAddressRepositoryProvider.overrideWithValue(
            _FakeSavedAddressRepository(seed: [_verified]),
          ),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                popped = await Navigator.push<SavedAddress>(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        const DeliveryAddressSelectionScreen(),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ev'));
    await tester.pumpAndSettle();

    expect(popped?.id, 'address-verified');
  });

  testWidgets('doğrulanmamış adres seçilemez ve uyarı metni gösterilir',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          savedAddressRepositoryProvider.overrideWithValue(
            _FakeSavedAddressRepository(seed: [_unverified]),
          ),
        ],
        child: const MaterialApp(home: DeliveryAddressSelectionScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Bu adres henüz doğrulanmadı, teslimat için kullanılamaz.'),
      findsOneWidget,
    );

    final inkWell = tester.widget<InkWell>(find.byType(InkWell).first);
    expect(inkWell.onTap, isNull);
  });
}
