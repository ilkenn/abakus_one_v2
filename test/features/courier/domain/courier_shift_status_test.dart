import 'package:abakus_one_v2/features/courier/domain/shift/courier_shift_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CourierShiftStatusTransitions', () {
    test('completed, rejected, and cancelled are terminal', () {
      expect(
          CourierShiftStatusTransitions.isTerminal(
              CourierShiftStatus.completed),
          isTrue);
      expect(
          CourierShiftStatusTransitions.isTerminal(CourierShiftStatus.rejected),
          isTrue);
      expect(
          CourierShiftStatusTransitions.isTerminal(
              CourierShiftStatus.cancelled),
          isTrue);
    });

    test(
        'awaitingManagerApproval can only move to approved/rejected — '
        'never straight to active', () {
      expect(
        CourierShiftStatusTransitions.canTransition(
            CourierShiftStatus.awaitingManagerApproval,
            CourierShiftStatus.approved),
        isTrue,
      );
      expect(
        CourierShiftStatusTransitions.canTransition(
            CourierShiftStatus.awaitingManagerApproval,
            CourierShiftStatus.active),
        isFalse,
      );
    });

    test('an ending request may be withdrawn back to active', () {
      expect(
        CourierShiftStatusTransitions.canTransition(
            CourierShiftStatus.ending, CourierShiftStatus.active),
        isTrue,
      );
    });

    test('suspended may return to active or move to completed', () {
      expect(
        CourierShiftStatusTransitions.canTransition(
            CourierShiftStatus.suspended, CourierShiftStatus.active),
        isTrue,
      );
      expect(
        CourierShiftStatusTransitions.canTransition(
            CourierShiftStatus.suspended, CourierShiftStatus.completed),
        isTrue,
      );
    });
  });
}
