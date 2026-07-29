import 'package:abakus_one_v2/features/pos/domain/kds/kitchen_line_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('KitchenLineStatusTransitions', () {
    test('queued can move to acknowledged, cancelled, or unavailable', () {
      expect(
        KitchenLineStatusTransitions.canTransition(
            KitchenLineStatus.queued, KitchenLineStatus.acknowledged),
        isTrue,
      );
      expect(
        KitchenLineStatusTransitions.canTransition(
            KitchenLineStatus.queued, KitchenLineStatus.cancelled),
        isTrue,
      );
      expect(
        KitchenLineStatusTransitions.canTransition(
            KitchenLineStatus.queued, KitchenLineStatus.unavailable),
        isTrue,
      );
      expect(
        KitchenLineStatusTransitions.canTransition(
            KitchenLineStatus.queued, KitchenLineStatus.preparing),
        isFalse,
      );
    });

    test(
        'a completed (ready) line can only move to recalled — never '
        'silently back to an earlier state', () {
      expect(
        KitchenLineStatusTransitions.canTransition(
            KitchenLineStatus.ready, KitchenLineStatus.recalled),
        isTrue,
      );
      expect(
        KitchenLineStatusTransitions.canTransition(
            KitchenLineStatus.ready, KitchenLineStatus.preparing),
        isFalse,
      );
      expect(
        KitchenLineStatusTransitions.canTransition(
            KitchenLineStatus.ready, KitchenLineStatus.queued),
        isFalse,
      );
    });

    test('recalled returns only to preparing (explicit resume)', () {
      expect(
        KitchenLineStatusTransitions.canTransition(
            KitchenLineStatus.recalled, KitchenLineStatus.preparing),
        isTrue,
      );
      expect(
        KitchenLineStatusTransitions.canTransition(
            KitchenLineStatus.recalled, KitchenLineStatus.ready),
        isFalse,
      );
    });

    test('cancelled and unavailable are terminal', () {
      expect(
          KitchenLineStatusTransitions.isTerminal(KitchenLineStatus.cancelled),
          isTrue);
      expect(
          KitchenLineStatusTransitions.isTerminal(
              KitchenLineStatus.unavailable),
          isTrue);
    });

    test('a status never transitions to itself', () {
      expect(
        KitchenLineStatusTransitions.canTransition(
            KitchenLineStatus.preparing, KitchenLineStatus.preparing),
        isFalse,
      );
    });
  });
}
