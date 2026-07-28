import 'package:abakus_one_v2/features/pos/domain/models/order_closure_lifecycle_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OrderClosureLifecycleTransitions — valid transitions', () {
    test('open -> paymentInProgress is valid', () {
      expect(
        OrderClosureLifecycleTransitions.canTransition(
          OrderClosureLifecycleStatus.open,
          OrderClosureLifecycleStatus.paymentInProgress,
        ),
        isTrue,
      );
    });

    test('open -> cancelled is valid', () {
      expect(
        OrderClosureLifecycleTransitions.canTransition(
          OrderClosureLifecycleStatus.open,
          OrderClosureLifecycleStatus.cancelled,
        ),
        isTrue,
      );
    });

    test('paymentInProgress -> open is valid (payment session cancelled)', () {
      expect(
        OrderClosureLifecycleTransitions.canTransition(
          OrderClosureLifecycleStatus.paymentInProgress,
          OrderClosureLifecycleStatus.open,
        ),
        isTrue,
      );
    });

    test('paymentInProgress -> closed is valid (first closure)', () {
      expect(
        OrderClosureLifecycleTransitions.canTransition(
          OrderClosureLifecycleStatus.paymentInProgress,
          OrderClosureLifecycleStatus.closed,
        ),
        isTrue,
      );
    });

    test('paymentInProgress -> reclosed is valid (subsequent closure)', () {
      expect(
        OrderClosureLifecycleTransitions.canTransition(
          OrderClosureLifecycleStatus.paymentInProgress,
          OrderClosureLifecycleStatus.reclosed,
        ),
        isTrue,
      );
    });

    test('closed -> reopened is valid', () {
      expect(
        OrderClosureLifecycleTransitions.canTransition(
          OrderClosureLifecycleStatus.closed,
          OrderClosureLifecycleStatus.reopened,
        ),
        isTrue,
      );
    });

    test('reopened -> paymentInProgress is valid', () {
      expect(
        OrderClosureLifecycleTransitions.canTransition(
          OrderClosureLifecycleStatus.reopened,
          OrderClosureLifecycleStatus.paymentInProgress,
        ),
        isTrue,
      );
    });

    test('reclosed -> reopened is valid (cycle repeats)', () {
      expect(
        OrderClosureLifecycleTransitions.canTransition(
          OrderClosureLifecycleStatus.reclosed,
          OrderClosureLifecycleStatus.reopened,
        ),
        isTrue,
      );
    });
  });

  group('OrderClosureLifecycleTransitions — invalid transitions', () {
    test('cancelled is terminal', () {
      expect(
        OrderClosureLifecycleTransitions.allowedNextStates(
          OrderClosureLifecycleStatus.cancelled,
        ),
        isEmpty,
      );
    });

    test('closed cannot jump directly to reclosed', () {
      expect(
        OrderClosureLifecycleTransitions.canTransition(
          OrderClosureLifecycleStatus.closed,
          OrderClosureLifecycleStatus.reclosed,
        ),
        isFalse,
      );
    });

    test('open cannot jump directly to closed', () {
      expect(
        OrderClosureLifecycleTransitions.canTransition(
          OrderClosureLifecycleStatus.open,
          OrderClosureLifecycleStatus.closed,
        ),
        isFalse,
      );
    });
  });
}
