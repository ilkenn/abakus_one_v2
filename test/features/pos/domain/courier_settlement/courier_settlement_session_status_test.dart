import 'package:abakus_one_v2/features/pos/domain/courier_settlement/courier_settlement_session_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CourierSettlementSessionStatusTransitions', () {
    test('active can only move to pendingApproval', () {
      expect(
        CourierSettlementSessionStatusTransitions.canTransition(
          CourierSettlementSessionStatus.active,
          CourierSettlementSessionStatus.pendingApproval,
        ),
        isTrue,
      );
      expect(
        CourierSettlementSessionStatusTransitions.canTransition(
          CourierSettlementSessionStatus.active,
          CourierSettlementSessionStatus.approved,
        ),
        isFalse,
      );
    });

    test('pendingApproval can move to approved or rejected', () {
      expect(
        CourierSettlementSessionStatusTransitions.canTransition(
          CourierSettlementSessionStatus.pendingApproval,
          CourierSettlementSessionStatus.approved,
        ),
        isTrue,
      );
      expect(
        CourierSettlementSessionStatusTransitions.canTransition(
          CourierSettlementSessionStatus.pendingApproval,
          CourierSettlementSessionStatus.rejected,
        ),
        isTrue,
      );
    });

    test(
        'rejected returns only to pendingApproval (redeclare, no '
        'reactivate step)', () {
      expect(
        CourierSettlementSessionStatusTransitions.canTransition(
          CourierSettlementSessionStatus.rejected,
          CourierSettlementSessionStatus.pendingApproval,
        ),
        isTrue,
      );
      expect(
        CourierSettlementSessionStatusTransitions.canTransition(
          CourierSettlementSessionStatus.rejected,
          CourierSettlementSessionStatus.active,
        ),
        isFalse,
      );
    });

    test('approved can only move to closed', () {
      expect(
        CourierSettlementSessionStatusTransitions.canTransition(
          CourierSettlementSessionStatus.approved,
          CourierSettlementSessionStatus.closed,
        ),
        isTrue,
      );
    });

    test('closed is terminal', () {
      expect(
        CourierSettlementSessionStatusTransitions.isTerminal(
          CourierSettlementSessionStatus.closed,
        ),
        isTrue,
      );
    });

    test('a status never transitions to itself', () {
      expect(
        CourierSettlementSessionStatusTransitions.canTransition(
          CourierSettlementSessionStatus.active,
          CourierSettlementSessionStatus.active,
        ),
        isFalse,
      );
    });
  });
}
