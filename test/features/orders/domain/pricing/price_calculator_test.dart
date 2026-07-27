import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_line.dart';
import 'package:abakus_one_v2/features/orders/domain/pricing/price_calculator.dart';
import 'package:abakus_one_v2/features/orders/domain/pricing/tax_policy.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

OrderLine _line(int wholeTry, {int quantity = 1}) {
  return OrderLine.create(
    productId: 'p',
    productName: 'Product',
    quantity: quantity,
    unitPrice: Money.fromWhole(wholeTry, Currency.tryLira),
    taxRate: TaxPolicy.defaultRate,
  );
}

void main() {
  group('PriceCalculator.calculate — subtotal, taxable base, VAT', () {
    test('grossSubtotal is the sum of every line\'s lineTotal', () {
      final breakdown = PriceCalculator.calculate(
        lines: [_line(100), _line(50, quantity: 2)],
        currency: Currency.tryLira,
      );

      expect(breakdown.grossSubtotal, Money.fromWhole(200, Currency.tryLira));
    });

    test(
        'taxableBase and vatAmount are the sum of each line\'s own tax snapshot',
        () {
      final line1 = _line(110); // VAT = 10.00
      final line2 = _line(220); // VAT = 20.00
      final breakdown = PriceCalculator.calculate(
        lines: [line1, line2],
        currency: Currency.tryLira,
      );

      expect(breakdown.vatAmount, line1.tax.vatAmount + line2.tax.vatAmount);
      expect(
        breakdown.taxableBase,
        line1.tax.taxableBase + line2.tax.taxableBase,
      );
    });
  });

  group('PriceCalculator.calculate — discount and fees', () {
    test(
        'discount and fees do not alter taxableBase/vatAmount (documented, unresolved treatment)',
        () {
      final line = _line(100);
      final withoutAdjustments = PriceCalculator.calculate(
        lines: [line],
        currency: Currency.tryLira,
      );
      final withAdjustments = PriceCalculator.calculate(
        lines: [line],
        currency: Currency.tryLira,
        discount: Money.fromWhole(10, Currency.tryLira),
        serviceFee: Money.fromWhole(5, Currency.tryLira),
        deliveryFee: Money.fromWhole(15, Currency.tryLira),
        packagingFee: Money.fromWhole(2, Currency.tryLira),
        tip: Money.fromWhole(8, Currency.tryLira),
      );

      expect(withAdjustments.taxableBase, withoutAdjustments.taxableBase);
      expect(withAdjustments.vatAmount, withoutAdjustments.vatAmount);
    });

    test('grandTotal = grossSubtotal - discount + fees + tip', () {
      final breakdown = PriceCalculator.calculate(
        lines: [_line(100)],
        currency: Currency.tryLira,
        discount: Money.fromWhole(10, Currency.tryLira),
        serviceFee: Money.fromWhole(5, Currency.tryLira),
        deliveryFee: Money.fromWhole(15, Currency.tryLira),
        packagingFee: Money.fromWhole(2, Currency.tryLira),
        tip: Money.fromWhole(8, Currency.tryLira),
      );

      // 100 - 10 + 5 + 15 + 2 + 8 = 120
      expect(breakdown.grandTotal, Money.fromWhole(120, Currency.tryLira));
    });

    test('omitted adjustments default to zero', () {
      final breakdown = PriceCalculator.calculate(
        lines: [_line(100)],
        currency: Currency.tryLira,
      );

      expect(breakdown.discount, Money.zero(Currency.tryLira));
      expect(breakdown.serviceFee, Money.zero(Currency.tryLira));
      expect(breakdown.tip, Money.zero(Currency.tryLira));
      expect(breakdown.grandTotal, Money.fromWhole(100, Currency.tryLira));
    });
  });

  group('PriceCalculator.calculate — validation', () {
    test('rejects a negative discount', () {
      expect(
        () => PriceCalculator.calculate(
          lines: [_line(100)],
          currency: Currency.tryLira,
          discount: Money.fromWhole(-1, Currency.tryLira),
        ),
        throwsA(isA<NegativeAmountViolation>()),
      );
    });

    test('rejects a negative fee', () {
      expect(
        () => PriceCalculator.calculate(
          lines: [_line(100)],
          currency: Currency.tryLira,
          deliveryFee: Money.fromWhole(-1, Currency.tryLira),
        ),
        throwsA(isA<NegativeAmountViolation>()),
      );
    });

    test(
        'rejects a discount larger than the gross subtotal (negative grand total prevention)',
        () {
      expect(
        () => PriceCalculator.calculate(
          lines: [_line(50)],
          currency: Currency.tryLira,
          discount: Money.fromWhole(100, Currency.tryLira),
        ),
        throwsA(isA<NegativeTotalViolation>()),
      );
    });

    test('an empty line list produces a zero breakdown', () {
      final breakdown = PriceCalculator.calculate(
        lines: const [],
        currency: Currency.tryLira,
      );

      expect(breakdown.grossSubtotal, Money.zero(Currency.tryLira));
      expect(breakdown.grandTotal, Money.zero(Currency.tryLira));
    });
  });
}
