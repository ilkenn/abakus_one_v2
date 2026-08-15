import 'package:abakus_one_v2/features/orders/domain/models/delivery_address_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

DeliveryAddressSnapshot _build({String buildingNo = '12'}) {
  return DeliveryAddressSnapshot(
    savedAddressId: 'address-1',
    label: 'Ev',
    provinceId: 'il-34',
    provinceName: 'İstanbul',
    districtId: 'ilce-besiktas',
    districtName: 'Beşiktaş',
    neighborhoodId: 'mah-levent',
    neighborhoodName: 'Levent',
    streetId: 'sok-1',
    streetName: '1. Sokak',
    buildingNo: buildingNo,
    apartmentNo: '4',
    floor: '2',
    addressDescription: 'Kapıcıya bırakın',
    latitude: 41.08,
    longitude: 29.02,
    providerSource: 'manual',
    providerPlaceId: 'place-1',
    serverVerifiedAt: DateTime(2026, 8, 1, 10, 0),
  );
}

void main() {
  group('DeliveryAddressSnapshot', () {
    test('two snapshots built from the same values are value-equal', () {
      expect(_build(), _build());
      expect(_build().hashCode, _build().hashCode);
    });

    test('differing in one field breaks equality', () {
      expect(_build(buildingNo: '12'), isNot(_build(buildingNo: '13')));
    });

    test(
        'streetId/streetName/floor/addressDescription/providerPlaceId are '
        'independently optional', () {
      final snapshot = DeliveryAddressSnapshot(
        savedAddressId: 'address-1',
        label: 'İş',
        provinceId: 'il-34',
        provinceName: 'İstanbul',
        districtId: 'ilce-sisli',
        districtName: 'Şişli',
        neighborhoodId: 'mah-mecidiyekoy',
        neighborhoodName: 'Mecidiyeköy',
        buildingNo: '5',
        apartmentNo: '1',
        latitude: 41.06,
        longitude: 28.99,
        providerSource: 'manual',
        serverVerifiedAt: DateTime(2026, 8, 1),
      );

      expect(snapshot.streetId, isNull);
      expect(snapshot.streetName, isNull);
      expect(snapshot.floor, isNull);
      expect(snapshot.addressDescription, isNull);
      expect(snapshot.providerPlaceId, isNull);
    });
  });
}
