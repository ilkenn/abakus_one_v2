import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/orders/domain/models/saved_address.dart';
import 'package:flutter_test/flutter_test.dart';

SavedAddress _build({
  AddressVerificationStatus verificationStatus =
      AddressVerificationStatus.unverified,
  DateTime? verifiedAt,
  double? latitude,
  double? longitude,
  String? providerSource,
}) {
  return SavedAddress(
    id: 'address-1',
    customerId: 'customer-1',
    label: 'Ev',
    provinceId: 'il-34',
    provinceName: 'İstanbul',
    districtId: 'ilce-besiktas',
    districtName: 'Beşiktaş',
    neighborhoodId: 'mah-levent',
    neighborhoodName: 'Levent',
    buildingNo: '12',
    apartmentNo: '4',
    latitude: latitude,
    longitude: longitude,
    verificationStatus: verificationStatus,
    verifiedAt: verifiedAt,
    providerSource: providerSource,
  );
}

void main() {
  group('SavedAddress — verification status (Faz P.1 req 7, 20)', () {
    test('a newly created address starts unverified by default', () {
      final address = _build();
      expect(address.verificationStatus, AddressVerificationStatus.unverified);
      expect(address.isDeliveryAuthorized, isFalse);
    });

    test(
        'isDeliveryAuthorized is true only for verified, not stale or '
        'unverified', () {
      expect(_build().isDeliveryAuthorized, isFalse);
      expect(
        _build(verificationStatus: AddressVerificationStatus.stale)
            .isDeliveryAuthorized,
        isFalse,
      );
      expect(
        _build(verificationStatus: AddressVerificationStatus.verified)
            .isDeliveryAuthorized,
        isTrue,
      );
    });

    test(
        'toDeliveryAddressSnapshot throws AddressNotVerifiedForDeliveryViolation '
        'for an unverified address (req 20)', () {
      final address = _build();
      expect(
        address.toDeliveryAddressSnapshot,
        throwsA(isA<AddressNotVerifiedForDeliveryViolation>()),
      );
    });

    test(
        'toDeliveryAddressSnapshot throws for a stale address, not just an '
        'unverified one (req 20)', () {
      final address = _build(
        verificationStatus: AddressVerificationStatus.stale,
        verifiedAt: DateTime(2026, 7, 1),
        latitude: 41.08,
        longitude: 29.02,
        providerSource: 'manual',
      );
      expect(
        address.toDeliveryAddressSnapshot,
        throwsA(isA<AddressNotVerifiedForDeliveryViolation>()),
      );
    });

    test(
        'toDeliveryAddressSnapshot throws for a verified address that is '
        'still missing coordinates/verifiedAt/providerSource (defensive '
        'check, req 20)', () {
      final address =
          _build(verificationStatus: AddressVerificationStatus.verified);
      expect(
        address.toDeliveryAddressSnapshot,
        throwsA(isA<AddressNotVerifiedForDeliveryViolation>()),
      );
    });

    test(
        'toDeliveryAddressSnapshot succeeds for a fully verified address and '
        'freezes its values (req 7, 20)', () {
      final verifiedAt = DateTime(2026, 8, 1, 9, 30);
      final address = _build(
        verificationStatus: AddressVerificationStatus.verified,
        verifiedAt: verifiedAt,
        latitude: 41.08,
        longitude: 29.02,
        providerSource: 'manual',
      );

      final snapshot = address.toDeliveryAddressSnapshot();

      expect(snapshot.savedAddressId, 'address-1');
      expect(snapshot.label, 'Ev');
      expect(snapshot.latitude, 41.08);
      expect(snapshot.longitude, 29.02);
      expect(snapshot.providerSource, 'manual');
      expect(snapshot.serverVerifiedAt, verifiedAt);
    });
  });

  group('SavedAddress — Faz P.2 real-evidence corrections', () {
    test(
        'toDeliveryAddressSnapshot throws for a "verified" address missing '
        'districtName, even though isDeliveryAuthorized is true — the '
        'defensive check added after the spike found district can be '
        'genuinely absent', () {
      final address = SavedAddress(
        id: 'address-2',
        customerId: 'customer-1',
        label: 'Ev',
        provinceId: 'il-34',
        provinceName: 'İstanbul',
        // districtId/districtName deliberately omitted (null).
        apartmentNo: '4',
        latitude: 41.08,
        longitude: 29.02,
        verificationStatus: AddressVerificationStatus.verified,
        verifiedAt: DateTime(2026, 8, 1),
        providerSource: 'google_places',
      );
      expect(
        address.toDeliveryAddressSnapshot,
        throwsA(isA<AddressNotVerifiedForDeliveryViolation>()),
      );
    });

    test(
        'toDeliveryAddressSnapshot succeeds with neighborhoodName/buildingNo '
        'both null — genuinely optional even for a verified address (real '
        'spike evidence: a mahalle-only address has no street_number)', () {
      final address = SavedAddress(
        id: 'address-3',
        customerId: 'customer-1',
        label: 'Ev',
        provinceId: 'il-34',
        provinceName: 'İstanbul',
        districtId: 'ilce-kagithane',
        districtName: 'Kağıthane',
        apartmentNo: '4',
        latitude: 41.08,
        longitude: 29.02,
        verificationStatus: AddressVerificationStatus.verified,
        verifiedAt: DateTime(2026, 8, 1),
        providerSource: 'google_places',
      );

      final snapshot = address.toDeliveryAddressSnapshot();

      expect(snapshot.neighborhoodName, isNull);
      expect(snapshot.buildingNo, isNull);
      expect(snapshot.districtName, 'Kağıthane');
    });

    test('buildingNoSource is preserved through to the snapshot', () {
      final address = SavedAddress(
        id: 'address-4',
        customerId: 'customer-1',
        label: 'Ev',
        provinceId: 'il-34',
        provinceName: 'İstanbul',
        districtId: 'ilce-besiktas',
        districtName: 'Beşiktaş',
        buildingNo: '12',
        buildingNoSource: 'customer',
        apartmentNo: '4',
        latitude: 41.08,
        longitude: 29.02,
        verificationStatus: AddressVerificationStatus.verified,
        verifiedAt: DateTime(2026, 8, 1),
        providerSource: 'google_places',
      );

      final snapshot = address.toDeliveryAddressSnapshot();

      expect(snapshot.buildingNo, '12');
      expect(snapshot.buildingNoSource, 'customer');
    });
  });

  group('SavedAddress.copyWith', () {
    test('preserves fields when not given, updates when given', () {
      final address = _build();
      final untouched = address.copyWith(label: 'Ev');
      expect(untouched.customerId, 'customer-1');
      expect(untouched.districtName, 'Beşiktaş');

      final updated = address.copyWith(
        verificationStatus: AddressVerificationStatus.verified,
        verifiedAt: DateTime(2026, 8, 1),
        latitude: 41.08,
        longitude: 29.02,
        providerSource: 'manual',
      );
      expect(updated.verificationStatus, AddressVerificationStatus.verified);
      expect(updated.isDeliveryAuthorized, isTrue);
      expect(address.isDeliveryAuthorized, isFalse,
          reason: 'copyWith must not mutate the original');
    });
  });
}
