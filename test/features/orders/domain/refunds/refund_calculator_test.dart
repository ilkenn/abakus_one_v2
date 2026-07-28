import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/orders/domain/refunds/refund_calculator.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RefundCalculator.refundableAmount', () {
    test('equals settled amount when nothing has been refunded yet', () {
      final refundable = RefundCalculator.refundableAmount(
        settledAmount: Money.fromWhole(200, Currency.tryLira),
        alreadyRefundedAmount: Money.zero(Currency.tryLira),
      );
      expect(refundable, Money.fromWhole(200, Currency.tryLira));
    });

    test('subtracts what has already been refunded', () {
      final refundable = RefundCalculator.refundableAmount(
        settledAmount: Money.fromWhole(200, Currency.tryLira),
        alreadyRefundedAmount: Money.fromWhole(50, Currency.tryLira),
      );
      expect(refundable, Money.fromWhole(150, Currency.tryLira));
    });

    test('never goes negative even if already-refunded somehow exceeds settled',
        () {
      final refundable = RefundCalculator.refundableAmount(
        settledAmount: Money.fromWhole(100, Currency.tryLira),
        alreadyRefundedAmount: Money.fromWhole(150, Currency.tryLira),
      );
      expect(refundable.isZero, isTrue);
    });
  });

  group('RefundCalculator.validateRefundRequest', () {
    test('a full refund of the entire settled amount is valid', () {
      expect(
        () => RefundCalculator.validateRefundRequest(
          requestedAmount: Money.fromWhole(200, Currency.tryLira),
          settledAmount: Money.fromWhole(200, Currency.tryLira),
          alreadyRefundedAmount: Money.zero(Currency.tryLira),
        ),
        returnsNormally,
      );
    });

    test('a partial refund within the refundable amount is valid', () {
      expect(
        () => RefundCalculator.validateRefundRequest(
          requestedAmount: Money.fromWhole(50, Currency.tryLira),
          settledAmount: Money.fromWhole(200, Currency.tryLira),
          alreadyRefundedAmount: Money.zero(Currency.tryLira),
        ),
        returnsNormally,
      );
    });

    test('rejects a request exceeding the refundable amount', () {
      expect(
        () => RefundCalculator.validateRefundRequest(
          requestedAmount: Money.fromWhole(250, Currency.tryLira),
          settledAmount: Money.fromWhole(200, Currency.tryLira),
          alreadyRefundedAmount: Money.zero(Currency.tryLira),
        ),
        throwsA(isA<RefundExceedsRefundableAmountViolation>()),
      );
    });

    test(
        'rejects a second partial refund that would exceed what remains refundable',
        () {
      expect(
        () => RefundCalculator.validateRefundRequest(
          requestedAmount: Money.fromWhole(60, Currency.tryLira),
          settledAmount: Money.fromWhole(200, Currency.tryLira),
          alreadyRefundedAmount: Money.fromWhole(150, Currency.tryLira),
        ),
        throwsA(isA<RefundExceedsRefundableAmountViolation>()),
      );
    });
  });
}
