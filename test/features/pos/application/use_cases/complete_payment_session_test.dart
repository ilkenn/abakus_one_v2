import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:abakus_one_v2/features/pos/application/identity/payment_split_id_generator.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/add_payment_split.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/complete_payment_session.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/start_payment_session.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/approval_result.dart';
import 'package:abakus_one_v2/features/pos/domain/models/payment_session.dart';
import 'package:abakus_one_v2/features/pos/domain/models/payment_session_status.dart';
import 'package:abakus_one_v2/features/payment/domain/models/payment_method.dart';
import 'package:abakus_one_v2/features/payment/domain/models/payment_method_reporting_category.dart';
import 'package:abakus_one_v2/features/payment/domain/models/payment_method_seed_data.dart';
import 'package:abakus_one_v2/features/payment/presentation/services/payment_service.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fake_clock.dart';

const _approvalRequiredMethod = PaymentMethod(
  id: 'manager_comp',
  name: 'Manager Comp',
  iconAssetPath: 'assets/images/payment/manager_comp.png',
  brandColorValue: 0xFF000000,
  isActive: true,
  supportsSplitPayment: true,
  supportsRefund: true,
  requiresReferenceNumber: false,
  requiresApproval: true,
  sortOrder: 99,
  reportingCategory: PaymentMethodReportingCategory.unknown,
);

void main() {
  PaymentSession buildReadySession(
      {required PaymentMethod method, String? transactionReference}) {
    final clock = FakeClock(DateTime(2026, 7, 29, 12, 0));
    final session = StartPaymentSession(clock: clock).call(
      sessionId: 'ps1',
      orderId: OrderId('order-1'),
      totalAmount: Money.fromWhole(100, Currency.tryLira),
    );
    return AddPaymentSplit(
        splitIdGenerator: SequentialPaymentSplitIdGenerator())(
      session: session,
      method: method,
      amount: Money.fromWhole(100, Currency.tryLira),
      transactionReference: transactionReference,
    );
  }

  group('CompletePaymentSession — happy path', () {
    test('completes a fully-settled, no-provider (cash) session', () async {
      final session = buildReadySession(method: PaymentMethodSeedData.cash);
      final useCase = CompletePaymentSession(paymentService: PaymentService());

      final completed =
          await useCase(session: session, expectedRevision: session.revision);

      expect(completed.status, PaymentSessionStatus.completed);
      expect(completed.revision, session.revision + 1);
    });
  });

  group('CompletePaymentSession — validation and failure', () {
    test('rejects a stale expectedRevision', () async {
      final session = buildReadySession(method: PaymentMethodSeedData.cash);
      final useCase = CompletePaymentSession(paymentService: PaymentService());

      await expectLater(
        useCase(session: session, expectedRevision: session.revision - 1),
        throwsA(isA<StaleRevisionViolation>()),
      );
    });

    test('rejects completion while remainingAmount is not zero', () async {
      final clock = FakeClock(DateTime(2026, 7, 29, 12, 0));
      final session = StartPaymentSession(clock: clock).call(
        sessionId: 'ps1',
        orderId: OrderId('order-1'),
        totalAmount: Money.fromWhole(100, Currency.tryLira),
      );
      final useCase = CompletePaymentSession(paymentService: PaymentService());

      await expectLater(
        useCase(session: session, expectedRevision: session.revision),
        throwsA(isA<PaymentSessionNotReadyViolation>()),
      );
    });

    test('rejects a method requiring a reference number with none recorded',
        () async {
      final session =
          buildReadySession(method: PaymentMethodSeedData.bankTransfer);
      final useCase = CompletePaymentSession(paymentService: PaymentService());

      await expectLater(
        useCase(session: session, expectedRevision: session.revision),
        throwsA(isA<MissingPaymentReferenceViolation>()),
      );
    });

    test('accepts a method requiring a reference number when one was recorded',
        () async {
      final session = buildReadySession(
        method: PaymentMethodSeedData.bankTransfer,
        transactionReference: 'EFT-12345',
      );
      final useCase = CompletePaymentSession(paymentService: PaymentService());

      final completed =
          await useCase(session: session, expectedRevision: session.revision);

      expect(completed.status, PaymentSessionStatus.completed);
    });

    test('rejects a method requiring approval with none granted', () async {
      final session = buildReadySession(method: _approvalRequiredMethod);
      final useCase = CompletePaymentSession(paymentService: PaymentService());

      await expectLater(
        useCase(session: session, expectedRevision: session.revision),
        throwsA(isA<PaymentMethodNotApprovedViolation>()),
      );
    });

    test('accepts a method requiring approval when granted is supplied',
        () async {
      final session = buildReadySession(method: _approvalRequiredMethod);
      final useCase = CompletePaymentSession(paymentService: PaymentService());
      final splitId = session.splits.single.id;

      final completed = await useCase(
        session: session,
        expectedRevision: session.revision,
        approvals: {
          splitId: const ApprovalResult(
              granted: true, approvedByStaffId: 'manager-1')
        },
      );

      expect(completed.status, PaymentSessionStatus.completed);
    });

    test(
        'rejects a provider-routed split since no real provider integration exists',
        () async {
      final session = buildReadySession(method: PaymentMethodSeedData.pluxee);
      final useCase = CompletePaymentSession(paymentService: PaymentService());

      await expectLater(
        useCase(session: session, expectedRevision: session.revision),
        throwsA(isA<ProviderTransactionNotSuccessfulViolation>()),
      );
    });
  });
}
