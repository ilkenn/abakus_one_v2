import 'package:abakus_one_v2/features/orders/domain/models/pickup_time_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PickupTimePolicy — exact NOW+20 boundary', () {
    test('minimumPickupTime is exactly now + 20 minutes', () {
      final now = DateTime(2026, 8, 10, 14, 0, 0);
      expect(
        PickupTimePolicy.minimumPickupTime(now),
        DateTime(2026, 8, 10, 14, 20, 0),
      );
    });

    test('now + 19:59 is denied', () {
      final now = DateTime(2026, 8, 10, 14, 0, 0);
      final pickupTime = DateTime(2026, 8, 10, 14, 19, 59);
      expect(PickupTimePolicy.isValid(pickupTime, now), isFalse);
    });

    test('now + 20:00 is accepted (inclusive boundary)', () {
      final now = DateTime(2026, 8, 10, 14, 0, 0);
      final pickupTime = DateTime(2026, 8, 10, 14, 20, 0);
      expect(PickupTimePolicy.isValid(pickupTime, now), isTrue);
    });

    test('now + 20:01 is accepted', () {
      final now = DateTime(2026, 8, 10, 14, 0, 0);
      final pickupTime = DateTime(2026, 8, 10, 14, 20, 1);
      expect(PickupTimePolicy.isValid(pickupTime, now), isTrue);
    });

    test('a past pickup time is denied', () {
      final now = DateTime(2026, 8, 10, 14, 0, 0);
      final pickupTime = DateTime(2026, 8, 10, 13, 0, 0);
      expect(PickupTimePolicy.isValid(pickupTime, now), isFalse);
    });

    test(
        'a manipulated client "now" cannot shrink the effective minimum — '
        'isValid always measures against whatever "now" it is actually '
        'given, so the server-side caller (Firestore rules\' request.time) '
        'is what determines the real boundary, never the client\'s own '
        'clock', () {
      // Simulates a client with its clock rolled back an hour, computing
      // its own (wrong) "now" — the 20-minute-from-*that*-now selection is
      // still only valid relative to *that* now, not the real one. This is
      // exactly why the authoritative check lives in firestore.rules
      // against request.time, not in this class.
      final manipulatedNow = DateTime(2026, 8, 10, 13, 0, 0);
      final realNow = DateTime(2026, 8, 10, 14, 0, 0);
      final pickupTimeChosenUnderManipulatedClock =
          PickupTimePolicy.minimumPickupTime(manipulatedNow); // 13:20

      // Valid under the manipulated clock's own frame...
      expect(
        PickupTimePolicy.isValid(
          pickupTimeChosenUnderManipulatedClock,
          manipulatedNow,
        ),
        isTrue,
      );
      // ...but invalid once measured against the real clock — this is the
      // check that actually protects the system.
      expect(
        PickupTimePolicy.isValid(
          pickupTimeChosenUnderManipulatedClock,
          realNow,
        ),
        isFalse,
      );
    });

    test('minimumLeadTime is exactly 20 minutes', () {
      expect(PickupTimePolicy.minimumLeadTime, const Duration(minutes: 20));
    });
  });
}
