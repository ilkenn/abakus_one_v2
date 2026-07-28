import 'package:abakus_one_v2/features/pos/domain/cash/cash_session_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CashSessionStatusTransitions', () {
    test('active moves only to pendingApproval', () {
      expect(
        CashSessionStatusTransitions.canTransition(
            CashSessionStatus.active, CashSessionStatus.pendingApproval),
        isTrue,
      );
      expect(
        CashSessionStatusTransitions.canTransition(
            CashSessionStatus.active, CashSessionStatus.approved),
        isFalse,
      );
    });

    test('pendingApproval moves to approved or rejected', () {
      expect(
        CashSessionStatusTransitions.canTransition(
            CashSessionStatus.pendingApproval, CashSessionStatus.approved),
        isTrue,
      );
      expect(
        CashSessionStatusTransitions.canTransition(
            CashSessionStatus.pendingApproval, CashSessionStatus.rejected),
        isTrue,
      );
    });

    test('rejected returns only to active (recount)', () {
      expect(
        CashSessionStatusTransitions.canTransition(
            CashSessionStatus.rejected, CashSessionStatus.active),
        isTrue,
      );
      expect(
        CashSessionStatusTransitions.canTransition(
            CashSessionStatus.rejected, CashSessionStatus.approved),
        isFalse,
      );
    });

    test('approved moves only to closed, closed is terminal', () {
      expect(
        CashSessionStatusTransitions.canTransition(
            CashSessionStatus.approved, CashSessionStatus.closed),
        isTrue,
      );
      expect(CashSessionStatusTransitions.isTerminal(CashSessionStatus.closed),
          isTrue);
    });

    test('a status never transitions to itself', () {
      expect(
        CashSessionStatusTransitions.canTransition(
            CashSessionStatus.active, CashSessionStatus.active),
        isFalse,
      );
    });
  });
}
