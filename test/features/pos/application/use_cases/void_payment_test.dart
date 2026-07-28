import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:abakus_one_v2/features/orders/domain/payment/payment_split.dart';
import 'package:abakus_one_v2/features/payment/domain/models/payment_method_seed_data.dart';
import 'package:abakus_one_v2/features/payment/domain/models/payment_method_snapshot.dart';
import 'package:abakus_one_v2/features/payment/presentation/services/payment_service.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/void_payment.dart';
import 'package:abakus_one_v2/features/pos/data/closure_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/audit/closure_audit_event_type.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/authorization_result.dart';
import 'package:abakus_one_v2/features/pos/domain/payments/payment_void_status.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fake_clock.dart';
import '../../test_support/fake_pos_authorization_policy.dart';

void main() {
  group('VoidPayment', () {
    test('a manual method (no provider) completes synchronously', () async {
      final clock = FakeClock(DateTime(2026, 7, 29, 12, 0));
      final auditRepository = InMemoryClosureAuditEntryRepository();
      final policy = FakePosAuthorizationPolicy(const AuthorizationResult(granted: true));
      final split = PaymentSplit.tryLira(
        id: 'split-1',
        methodSnapshot: PaymentMethodSnapshot.capture(PaymentMethodSeedData.cash),
        amount: Money.fromWhole(100, Currency.tryLira),
      );

      final result = await VoidPayment(
        clock: clock,
        authorizationPolicy: policy,
        auditRepository: auditRepository,
        paymentService: PaymentService(),
      )(
        orderId: OrderId('order-1'),
        split: split,
        reason: 'Wrong amount entered',
        requestedByStaffId: 'staff-1',
      );

      expect(result.status, PaymentVoidStatus.completed);
      expect(result.originalSplitId, 'split-1');

      final events = await auditRepository.findByOrderId(OrderId('order-1'));
      expect(events.single.type, ClosureAuditEventType.paymentVoided);
    });

    test('a provider-routed method is rejected today (no real provider integration)', () async {
      final clock = FakeClock(DateTime(2026, 7, 29, 12, 0));
      final auditRepository = InMemoryClosureAuditEntryRepository();
      final policy = FakePosAuthorizationPolicy(const AuthorizationResult(granted: true));
      final split = PaymentSplit.tryLira(
        id: 'split-1',
        methodSnapshot: PaymentMethodSnapshot.capture(PaymentMethodSeedData.pluxee),
        amount: Money.fromWhole(100, Currency.tryLira),
      );

      final result = await VoidPayment(
        clock: clock,
        authorizationPolicy: policy,
        auditRepository: auditRepository,
        paymentService: PaymentService(),
      )(
        orderId: OrderId('order-1'),
        split: split,
        reason: 'Wrong method',
        requestedByStaffId: 'staff-1',
      );

      expect(result.status, PaymentVoidStatus.rejected);
    });

    test('rejects when the policy denies the action', () async {
      final clock = FakeClock(DateTime(2026, 7, 29, 12, 0));
      final auditRepository = InMemoryClosureAuditEntryRepository();
      final policy = FakePosAuthorizationPolicy(
        const AuthorizationResult(granted: false, reason: 'Not authorized'),
      );
      final split = PaymentSplit.tryLira(
        id: 'split-1',
        methodSnapshot: PaymentMethodSnapshot.capture(PaymentMethodSeedData.cash),
        amount: Money.fromWhole(100, Currency.tryLira),
      );

      await expectLater(
        VoidPayment(
          clock: clock,
          authorizationPolicy: policy,
          auditRepository: auditRepository,
          paymentService: PaymentService(),
        )(
          orderId: OrderId('order-1'),
          split: split,
          reason: 'Test',
          requestedByStaffId: 'staff-1',
        ),
        throwsA(isA<AuthorizationDeniedViolation>()),
      );
    });
  });
}
