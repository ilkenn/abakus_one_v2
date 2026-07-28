import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/close_order_account.dart';
import 'package:abakus_one_v2/features/pos/data/closure_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/audit/closure_audit_event_type.dart';
import 'package:abakus_one_v2/features/pos/domain/models/order_closure.dart';
import 'package:abakus_one_v2/features/pos/domain/models/order_closure_lifecycle_status.dart';
import 'package:abakus_one_v2/features/pos/domain/models/payment_session.dart';
import 'package:abakus_one_v2/features/pos/domain/models/payment_session_status.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fake_clock.dart';

OrderClosure _paymentInProgressClosure({int reopenCount = 0, int revision = 2}) {
  return OrderClosure(
    closureId: 'c1',
    orderId: OrderId('order-1'),
    lifecycleStatus: OrderClosureLifecycleStatus.paymentInProgress,
    revision: revision,
    reopenCount: reopenCount,
  );
}

PaymentSession _completedSession() {
  return PaymentSession(
    id: 'ps1',
    orderId: OrderId('order-1'),
    totalAmount: Money.fromWhole(100, Currency.tryLira),
    status: PaymentSessionStatus.completed,
    createdAt: DateTime(2026, 7, 29),
    revision: 2,
  );
}

void main() {
  group('CloseOrderAccount', () {
    test('lands on closed the first time (reopenCount == 0)', () async {
      final clock = FakeClock(DateTime(2026, 7, 29, 12, 0));
      final auditRepository = InMemoryClosureAuditEntryRepository();
      final closure = _paymentInProgressClosure();

      final updated = await CloseOrderAccount(clock: clock, auditRepository: auditRepository)(
        closure: closure,
        paymentSession: _completedSession(),
        expectedRevision: closure.revision,
        closedByStaffId: 'staff-1',
      );

      expect(updated.lifecycleStatus, OrderClosureLifecycleStatus.closed);
      expect(updated.closedByStaffId, 'staff-1');
      expect(updated.paymentSessionId, 'ps1');

      final events = await auditRepository.findByOrderId(OrderId('order-1'));
      expect(events.single.type, ClosureAuditEventType.orderClosed);
    });

    test('lands on reclosed when reopenCount > 0', () async {
      final clock = FakeClock(DateTime(2026, 7, 29, 12, 0));
      final auditRepository = InMemoryClosureAuditEntryRepository();
      final closure = _paymentInProgressClosure(reopenCount: 1);

      final updated = await CloseOrderAccount(clock: clock, auditRepository: auditRepository)(
        closure: closure,
        paymentSession: _completedSession(),
        expectedRevision: closure.revision,
        closedByStaffId: 'staff-1',
      );

      expect(updated.lifecycleStatus, OrderClosureLifecycleStatus.reclosed);
      final events = await auditRepository.findByOrderId(OrderId('order-1'));
      expect(events.single.type, ClosureAuditEventType.orderReclosed);
    });

    test('rejects closing while the payment session is not completed', () async {
      final clock = FakeClock(DateTime(2026, 7, 29, 12, 0));
      final auditRepository = InMemoryClosureAuditEntryRepository();
      final closure = _paymentInProgressClosure();
      final incompleteSession = PaymentSession(
        id: 'ps1',
        orderId: OrderId('order-1'),
        totalAmount: Money.fromWhole(100, Currency.tryLira),
        status: PaymentSessionStatus.readyToComplete,
        createdAt: DateTime(2026, 7, 29),
        revision: 1,
      );

      await expectLater(
        CloseOrderAccount(clock: clock, auditRepository: auditRepository)(
          closure: closure,
          paymentSession: incompleteSession,
          expectedRevision: closure.revision,
          closedByStaffId: 'staff-1',
        ),
        throwsA(isA<PaymentSessionNotReadyViolation>()),
      );
    });

    test('rejects a stale expectedRevision', () async {
      final clock = FakeClock(DateTime(2026, 7, 29, 12, 0));
      final auditRepository = InMemoryClosureAuditEntryRepository();
      final closure = _paymentInProgressClosure();

      await expectLater(
        CloseOrderAccount(clock: clock, auditRepository: auditRepository)(
          closure: closure,
          paymentSession: _completedSession(),
          expectedRevision: closure.revision - 1,
          closedByStaffId: 'staff-1',
        ),
        throwsA(isA<StaleRevisionViolation>()),
      );
    });

    test('rejects closing an already-closed record', () async {
      final clock = FakeClock(DateTime(2026, 7, 29, 12, 0));
      final auditRepository = InMemoryClosureAuditEntryRepository();
      final closure = OrderClosure(
        closureId: 'c1',
        orderId: OrderId('order-1'),
        lifecycleStatus: OrderClosureLifecycleStatus.closed,
        revision: 3,
      );

      await expectLater(
        CloseOrderAccount(clock: clock, auditRepository: auditRepository)(
          closure: closure,
          paymentSession: _completedSession(),
          expectedRevision: closure.revision,
          closedByStaffId: 'staff-1',
        ),
        throwsA(isA<InvalidOrderClosureTransitionViolation>()),
      );
    });
  });
}
