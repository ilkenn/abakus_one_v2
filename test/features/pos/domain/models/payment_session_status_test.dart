import 'package:abakus_one_v2/features/pos/domain/models/payment_session_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PaymentSessionStatusTransitions — valid transitions', () {
    test('collecting -> readyToComplete is valid', () {
      expect(
        PaymentSessionStatusTransitions.canTransition(
          PaymentSessionStatus.collecting,
          PaymentSessionStatus.readyToComplete,
        ),
        isTrue,
      );
    });

    test('readyToComplete -> collecting is valid (a split was removed)', () {
      expect(
        PaymentSessionStatusTransitions.canTransition(
          PaymentSessionStatus.readyToComplete,
          PaymentSessionStatus.collecting,
        ),
        isTrue,
      );
    });

    test('collecting -> cancelled is valid', () {
      expect(
        PaymentSessionStatusTransitions.canTransition(
          PaymentSessionStatus.collecting,
          PaymentSessionStatus.cancelled,
        ),
        isTrue,
      );
    });

    test('readyToComplete -> completing is valid', () {
      expect(
        PaymentSessionStatusTransitions.canTransition(
          PaymentSessionStatus.readyToComplete,
          PaymentSessionStatus.completing,
        ),
        isTrue,
      );
    });

    test('completing -> completed is valid', () {
      expect(
        PaymentSessionStatusTransitions.canTransition(
          PaymentSessionStatus.completing,
          PaymentSessionStatus.completed,
        ),
        isTrue,
      );
    });

    test('completing -> failed is valid', () {
      expect(
        PaymentSessionStatusTransitions.canTransition(
          PaymentSessionStatus.completing,
          PaymentSessionStatus.failed,
        ),
        isTrue,
      );
    });

    test('failed -> completing (retry) is valid', () {
      expect(
        PaymentSessionStatusTransitions.canTransition(
          PaymentSessionStatus.failed,
          PaymentSessionStatus.completing,
        ),
        isTrue,
      );
    });

    test('failed -> collecting (go back and adjust) is valid', () {
      expect(
        PaymentSessionStatusTransitions.canTransition(
          PaymentSessionStatus.failed,
          PaymentSessionStatus.collecting,
        ),
        isTrue,
      );
    });
  });

  group('PaymentSessionStatusTransitions — invalid transitions', () {
    test('completing does not skip directly to readyToComplete', () {
      expect(
        PaymentSessionStatusTransitions.canTransition(
          PaymentSessionStatus.completing,
          PaymentSessionStatus.readyToComplete,
        ),
        isFalse,
      );
    });

    test('collecting cannot jump straight to completing', () {
      expect(
        PaymentSessionStatusTransitions.canTransition(
          PaymentSessionStatus.collecting,
          PaymentSessionStatus.completing,
        ),
        isFalse,
      );
    });

    test('completed is terminal', () {
      expect(
        PaymentSessionStatusTransitions.allowedNextStates(
          PaymentSessionStatus.completed,
        ),
        isEmpty,
      );
    });

    test('cancelled is terminal', () {
      expect(
        PaymentSessionStatusTransitions.allowedNextStates(
          PaymentSessionStatus.cancelled,
        ),
        isEmpty,
      );
    });

    test(
        'remaining completing after completed is rejected (no self/backward loop)',
        () {
      expect(
        PaymentSessionStatusTransitions.canTransition(
          PaymentSessionStatus.completed,
          PaymentSessionStatus.completing,
        ),
        isFalse,
      );
    });
  });
}
