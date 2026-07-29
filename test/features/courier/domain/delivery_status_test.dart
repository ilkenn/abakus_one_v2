import 'package:abakus_one_v2/features/courier/domain/delivery/delivery_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DeliveryStatusTransitions', () {
    test('delivered is terminal — no outgoing transition at all', () {
      expect(DeliveryStatusTransitions.isTerminal(DeliveryStatus.delivered),
          isTrue);
      expect(
        DeliveryStatusTransitions.canTransition(
            DeliveryStatus.delivered, DeliveryStatus.enRoute),
        isFalse,
      );
    });

    test('cancelled and returnedToRestaurant are terminal', () {
      expect(DeliveryStatusTransitions.isTerminal(DeliveryStatus.cancelled),
          isTrue);
      expect(
        DeliveryStatusTransitions.isTerminal(
            DeliveryStatus.returnedToRestaurant),
        isTrue,
      );
    });

    test('readyForAssignment can only move to assigned or cancelled', () {
      expect(
        DeliveryStatusTransitions.canTransition(
            DeliveryStatus.readyForAssignment, DeliveryStatus.assigned),
        isTrue,
      );
      expect(
        DeliveryStatusTransitions.canTransition(
            DeliveryStatus.readyForAssignment, DeliveryStatus.pickedUp),
        isFalse,
      );
    });

    test(
        'assignmentRejected/assignmentExpired always requeue to '
        'readyForAssignment', () {
      expect(
        DeliveryStatusTransitions.canTransition(
            DeliveryStatus.assignmentRejected,
            DeliveryStatus.readyForAssignment),
        isTrue,
      );
      expect(
        DeliveryStatusTransitions.canTransition(
            DeliveryStatus.assignmentExpired,
            DeliveryStatus.readyForAssignment),
        isTrue,
      );
    });

    test('pickup cannot happen before arrival at restaurant', () {
      expect(
        DeliveryStatusTransitions.canTransition(
            DeliveryStatus.accepted, DeliveryStatus.pickedUp),
        isFalse,
      );
    });

    test('a status never transitions to itself', () {
      expect(
        DeliveryStatusTransitions.canTransition(
            DeliveryStatus.assigned, DeliveryStatus.assigned),
        isFalse,
      );
    });
  });
}
