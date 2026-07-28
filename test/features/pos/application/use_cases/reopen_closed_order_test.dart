import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/reopen_closed_order.dart';
import 'package:abakus_one_v2/features/pos/data/closure_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/audit/closure_audit_event_type.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/approval_result.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/authorization_result.dart';
import 'package:abakus_one_v2/features/pos/domain/models/order_closure.dart';
import 'package:abakus_one_v2/features/pos/domain/models/order_closure_lifecycle_status.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fake_clock.dart';
import '../../test_support/fake_pos_authorization_policy.dart';

OrderClosure _closedClosure({int revision = 3}) {
  return OrderClosure(
    closureId: 'c1',
    orderId: OrderId('order-1'),
    lifecycleStatus: OrderClosureLifecycleStatus.closed,
    revision: revision,
  );
}

void main() {
  group('ReopenClosedOrder', () {
    test('reopens a closed record when authorized, incrementing reopenCount', () async {
      final clock = FakeClock(DateTime(2026, 7, 29, 12, 0));
      final auditRepository = InMemoryClosureAuditEntryRepository();
      final policy = FakePosAuthorizationPolicy(const AuthorizationResult(granted: true));
      final closure = _closedClosure();

      final updated = await ReopenClosedOrder(
        clock: clock,
        authorizationPolicy: policy,
        auditRepository: auditRepository,
      )(
        closure: closure,
        expectedRevision: closure.revision,
        reason: 'Customer disputed the total',
        performedByStaffId: 'staff-1',
      );

      expect(updated.lifecycleStatus, OrderClosureLifecycleStatus.reopened);
      expect(updated.reopenCount, 1);
      expect(policy.lastAction!.name, 'reopenOrder');

      final events = await auditRepository.findByOrderId(OrderId('order-1'));
      expect(events.single.type, ClosureAuditEventType.orderReopened);
    });

    test('rejects when the policy denies the action', () async {
      final clock = FakeClock(DateTime(2026, 7, 29, 12, 0));
      final auditRepository = InMemoryClosureAuditEntryRepository();
      final policy = FakePosAuthorizationPolicy(
        const AuthorizationResult(granted: false, reason: 'Not a manager'),
      );
      final closure = _closedClosure();

      await expectLater(
        ReopenClosedOrder(clock: clock, authorizationPolicy: policy, auditRepository: auditRepository)(
          closure: closure,
          expectedRevision: closure.revision,
          reason: 'Test',
          performedByStaffId: 'staff-1',
        ),
        throwsA(isA<AuthorizationDeniedViolation>()),
      );
    });

    test('rejects when approval is required but not granted', () async {
      final clock = FakeClock(DateTime(2026, 7, 29, 12, 0));
      final auditRepository = InMemoryClosureAuditEntryRepository();
      final policy = FakePosAuthorizationPolicy(
        const AuthorizationResult(granted: true, requiresManagerApproval: true),
      );
      final closure = _closedClosure();

      await expectLater(
        ReopenClosedOrder(clock: clock, authorizationPolicy: policy, auditRepository: auditRepository)(
          closure: closure,
          expectedRevision: closure.revision,
          reason: 'Test',
          performedByStaffId: 'staff-1',
        ),
        throwsA(isA<AuthorizationDeniedViolation>()),
      );
    });

    test('succeeds when approval is required and granted', () async {
      final clock = FakeClock(DateTime(2026, 7, 29, 12, 0));
      final auditRepository = InMemoryClosureAuditEntryRepository();
      final policy = FakePosAuthorizationPolicy(
        const AuthorizationResult(granted: true, requiresManagerApproval: true),
      );
      final closure = _closedClosure();

      final updated = await ReopenClosedOrder(
        clock: clock,
        authorizationPolicy: policy,
        auditRepository: auditRepository,
      )(
        closure: closure,
        expectedRevision: closure.revision,
        reason: 'Test',
        performedByStaffId: 'staff-1',
        approval: const ApprovalResult(granted: true, approvedByStaffId: 'manager-1'),
      );

      expect(updated.lifecycleStatus, OrderClosureLifecycleStatus.reopened);
    });

    test('rejects reopening a record that is not currently closed/reclosed', () async {
      final clock = FakeClock(DateTime(2026, 7, 29, 12, 0));
      final auditRepository = InMemoryClosureAuditEntryRepository();
      final policy = FakePosAuthorizationPolicy(const AuthorizationResult(granted: true));
      final closure = OrderClosure(
        closureId: 'c1',
        orderId: OrderId('order-1'),
        lifecycleStatus: OrderClosureLifecycleStatus.open,
        revision: 1,
      );

      await expectLater(
        ReopenClosedOrder(clock: clock, authorizationPolicy: policy, auditRepository: auditRepository)(
          closure: closure,
          expectedRevision: closure.revision,
          reason: 'Test',
          performedByStaffId: 'staff-1',
        ),
        throwsA(isA<InvalidOrderClosureTransitionViolation>()),
      );
    });
  });
}
