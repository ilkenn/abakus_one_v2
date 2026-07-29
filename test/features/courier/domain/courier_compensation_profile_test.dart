import 'package:abakus_one_v2/features/courier/domain/compensation/courier_compensation_profile.dart';
import 'package:flutter_test/flutter_test.dart';

CourierCompensationProfile _profile({
  DateTime? effectiveFrom,
  DateTime? effectiveUntil,
  bool isActive = true,
}) {
  return CourierCompensationProfile(
    id: 'profile-1',
    courierId: 'courier-1',
    version: 1,
    effectiveFrom: effectiveFrom ?? DateTime(2026, 1, 1),
    effectiveUntil: effectiveUntil,
    isActive: isActive,
    createdByStaffId: 'manager-1',
    createdAt: DateTime(2026, 1, 1),
  );
}

void main() {
  group('CourierCompensationProfile.coversAt', () {
    test(
        'an open-ended profile covers every instant at or after '
        'effectiveFrom', () {
      final profile = _profile(effectiveFrom: DateTime(2026, 1, 1));
      expect(profile.coversAt(DateTime(2026, 1, 1)), isTrue);
      expect(profile.coversAt(DateTime(2027, 1, 1)), isTrue);
      expect(profile.coversAt(DateTime(2025, 12, 31)), isFalse);
    });

    test(
        'a bounded profile does not cover its own effectiveUntil instant '
        '(exclusive end)', () {
      final profile = _profile(
        effectiveFrom: DateTime(2026, 1, 1),
        effectiveUntil: DateTime(2026, 2, 1),
      );
      expect(profile.coversAt(DateTime(2026, 1, 31)), isTrue);
      expect(profile.coversAt(DateTime(2026, 2, 1)), isFalse);
    });

    test('an inactive profile never covers any instant', () {
      final profile = _profile(isActive: false);
      expect(profile.coversAt(DateTime(2026, 6, 1)), isFalse);
    });
  });
}
