import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_number.dart';
import 'package:abakus_one_v2/features/orders/domain/pricing/price_calculator.dart';
import 'package:abakus_one_v2/features/orders/domain/receipt/receipt.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/request_duplicate_receipt.dart';
import 'package:abakus_one_v2/features/pos/data/closure_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/audit/closure_audit_event_type.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/authorization_result.dart';
import 'package:abakus_one_v2/features/pos/domain/receipts/receipt_print_provider.dart';
import 'package:abakus_one_v2/features/pos/domain/receipts/receipt_print_result.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fake_clock.dart';
import '../../test_support/fake_pos_authorization_policy.dart';

Receipt _buildReceipt() {
  return Receipt(
    receiptNumber: 'R-001',
    orderId: OrderId('order-1'),
    orderNumber: OrderNumber('A-001'),
    issuedAt: DateTime(2026, 7, 29),
    summary:
        PriceCalculator.calculate(lines: const [], currency: Currency.tryLira),
  );
}

void main() {
  group('RequestDuplicateReceipt', () {
    test(
        'with the default NoOpReceiptPrintProvider, reports unavailable and still logs the request',
        () async {
      final clock = FakeClock(DateTime(2026, 7, 29, 12, 0));
      final auditRepository = InMemoryClosureAuditEntryRepository();

      final result = await RequestDuplicateReceipt(
        clock: clock,
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        auditRepository: auditRepository,
        printProvider: const NoOpReceiptPrintProvider(),
      )(
        orderId: OrderId('order-1'),
        receipt: _buildReceipt(),
        requestedByStaffId: 'staff-1',
        requestId: 'req-1',
      );

      expect(result.status, ReceiptPrintResultStatus.unavailable);

      final events = await auditRepository.findByOrderId(OrderId('order-1'));
      expect(
          events.single.type, ClosureAuditEventType.duplicateReceiptRequested);
    });

    test(
        'two separate requestIds for the same receipt produce two distinct audit entries',
        () async {
      final clock = FakeClock(DateTime(2026, 7, 29, 12, 0));
      final auditRepository = InMemoryClosureAuditEntryRepository();
      final useCase = RequestDuplicateReceipt(
        clock: clock,
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        auditRepository: auditRepository,
        printProvider: const NoOpReceiptPrintProvider(),
      );
      final receipt = _buildReceipt();

      await useCase(
        orderId: OrderId('order-1'),
        receipt: receipt,
        requestedByStaffId: 'staff-1',
        requestId: 'req-1',
      );
      await useCase(
        orderId: OrderId('order-1'),
        receipt: receipt,
        requestedByStaffId: 'staff-1',
        requestId: 'req-2',
      );

      final events = await auditRepository.findByOrderId(OrderId('order-1'));
      expect(events, hasLength(2));
      expect(events[0].id, isNot(events[1].id));
    });

    test(
        'throws AuthorizationDeniedViolation when denied, and logs no audit entry',
        () async {
      final clock = FakeClock(DateTime(2026, 7, 29, 12, 0));
      final auditRepository = InMemoryClosureAuditEntryRepository();
      final useCase = RequestDuplicateReceipt(
        clock: clock,
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: false)),
        auditRepository: auditRepository,
        printProvider: const NoOpReceiptPrintProvider(),
      );

      await expectLater(
        () => useCase(
          orderId: OrderId('order-1'),
          receipt: _buildReceipt(),
          requestedByStaffId: 'staff-1',
          requestId: 'req-1',
        ),
        throwsA(isA<AuthorizationDeniedViolation>()),
      );
      expect(await auditRepository.findByOrderId(OrderId('order-1')), isEmpty);
    });
  });
}
