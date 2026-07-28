import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:abakus_one_v2/features/orders/domain/payment/payment_split.dart';
import 'package:abakus_one_v2/features/payment/domain/models/payment_method_seed_data.dart';
import 'package:abakus_one_v2/features/payment/domain/models/payment_method_snapshot.dart';
import 'package:abakus_one_v2/features/payment/presentation/services/payment_service.dart';
import 'package:abakus_one_v2/features/pos/application/identity/payment_split_id_generator.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/correct_payment_method.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/void_payment.dart';
import 'package:abakus_one_v2/features/pos/data/closure_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/audit/closure_audit_event_type.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/authorization_result.dart';
import 'package:abakus_one_v2/features/pos/domain/payments/payment_correction_type.dart';
import 'package:abakus_one_v2/features/pos/domain/payments/payment_void_status.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fake_clock.dart';
import '../../test_support/fake_pos_authorization_policy.dart';

void main() {
  group('CorrectPaymentMethod', () {
    test('voids the original, records a same-amount replacement under the new method', () async {
      final clock = FakeClock(DateTime(2026, 7, 29, 12, 0));
      final auditRepository = InMemoryClosureAuditEntryRepository();
      final policy = FakePosAuthorizationPolicy(const AuthorizationResult(granted: true));
      final voidPayment = VoidPayment(
        clock: clock,
        authorizationPolicy: policy,
        auditRepository: auditRepository,
        paymentService: PaymentService(),
      );
      final originalSplit = PaymentSplit.tryLira(
        id: 'split-1',
        methodSnapshot: PaymentMethodSnapshot.capture(PaymentMethodSeedData.cash),
        amount: Money.fromWhole(100, Currency.tryLira),
      );

      final result = await CorrectPaymentMethod(
        clock: clock,
        authorizationPolicy: policy,
        auditRepository: auditRepository,
        voidPayment: voidPayment,
        splitIdGenerator: SequentialPaymentSplitIdGenerator(),
      )(
        orderId: OrderId('order-1'),
        originalSplit: originalSplit,
        newMethod: PaymentMethodSeedData.creditCard,
        reason: 'Cashier mis-selected cash',
        correctedByStaffId: 'staff-1',
      );

      expect(result.void_.status, PaymentVoidStatus.completed);
      expect(result.void_.originalSplitId, 'split-1');
      expect(result.replacementSplit.methodSnapshot.paymentMethodId, 'credit_card');
      expect(result.replacementSplit.amount, originalSplit.amount);
      expect(result.correction.correctionType, PaymentCorrectionType.paymentMethodCorrection);
      expect(result.correction.originalPaymentId, 'split-1');
      expect(result.correction.replacementPaymentId, result.replacementSplit.id);

      final events = await auditRepository.findByOrderId(OrderId('order-1'));
      expect(
        events.map((e) => e.type),
        containsAll([ClosureAuditEventType.paymentVoided, ClosureAuditEventType.paymentMethodCorrected]),
      );
    });

    test('rejects when the policy denies the action', () async {
      final clock = FakeClock(DateTime(2026, 7, 29, 12, 0));
      final auditRepository = InMemoryClosureAuditEntryRepository();
      final deniedPolicy = FakePosAuthorizationPolicy(
        const AuthorizationResult(granted: false, reason: 'Not authorized'),
      );
      final voidPayment = VoidPayment(
        clock: clock,
        authorizationPolicy: FakePosAuthorizationPolicy(const AuthorizationResult(granted: true)),
        auditRepository: auditRepository,
        paymentService: PaymentService(),
      );
      final originalSplit = PaymentSplit.tryLira(
        id: 'split-1',
        methodSnapshot: PaymentMethodSnapshot.capture(PaymentMethodSeedData.cash),
        amount: Money.fromWhole(100, Currency.tryLira),
      );

      await expectLater(
        CorrectPaymentMethod(
          clock: clock,
          authorizationPolicy: deniedPolicy,
          auditRepository: auditRepository,
          voidPayment: voidPayment,
          splitIdGenerator: SequentialPaymentSplitIdGenerator(),
        )(
          orderId: OrderId('order-1'),
          originalSplit: originalSplit,
          newMethod: PaymentMethodSeedData.creditCard,
          reason: 'Test',
          correctedByStaffId: 'staff-1',
        ),
        throwsA(isA<AuthorizationDeniedViolation>()),
      );
    });
  });
}
