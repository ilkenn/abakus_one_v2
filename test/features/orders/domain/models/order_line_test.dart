import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_line.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_line_modifier_selection.dart';
import 'package:abakus_one_v2/features/orders/domain/pricing/tax_policy.dart';
import 'package:abakus_one_v2/features/orders/domain/pricing/tax_rate.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OrderLine.create — pricing composition', () {
    test(
        'computes lineSubtotal/lineTotal from unitPrice, modifiers, and quantity',
        () {
      final line = OrderLine.create(
        productId: 'p1',
        productName: 'Mexifit Bowl',
        modifiers: [
          const OrderLineModifierSelection(
            groupId: 'protein',
            groupName: 'Protein',
            optionId: 'chicken',
            optionName: 'Tavuk',
            unitExtraPrice: Money(4000, Currency.tryLira),
            quantity: 1,
          ),
        ],
        quantity: 2,
        unitPrice: Money.fromWhole(100, Currency.tryLira),
        taxRate: TaxPolicy.defaultRate,
      );

      // (100.00 + 40.00) * 2 = 280.00
      expect(line.modifierTotal, Money.fromWhole(40, Currency.tryLira));
      expect(line.lineSubtotal, Money.fromWhole(280, Currency.tryLira));
      expect(line.lineTotal, Money.fromWhole(280, Currency.tryLira));
    });

    test('a line discount reduces lineTotal below lineSubtotal', () {
      final line = OrderLine.create(
        productId: 'p1',
        productName: 'Falafel Bowl',
        quantity: 1,
        unitPrice: Money.fromWhole(100, Currency.tryLira),
        lineDiscount: Money.fromWhole(10, Currency.tryLira),
        taxRate: TaxPolicy.defaultRate,
      );

      expect(line.lineSubtotal, Money.fromWhole(100, Currency.tryLira));
      expect(line.lineDiscount, Money.fromWhole(10, Currency.tryLira));
      expect(line.lineTotal, Money.fromWhole(90, Currency.tryLira));
    });

    test(
        'quantity-aware: a modifier with quantity > 1 multiplies its extra price',
        () {
      final line = OrderLine.create(
        productId: 'p1',
        productName: 'Bowl',
        modifiers: [
          const OrderLineModifierSelection(
            groupId: 'extras',
            groupName: 'Ekstra',
            optionId: 'cheese',
            optionName: 'Peynir',
            unitExtraPrice: Money(1000, Currency.tryLira),
            quantity: 2,
          ),
        ],
        quantity: 1,
        unitPrice: Money.fromWhole(50, Currency.tryLira),
        taxRate: TaxPolicy.defaultRate,
      );

      expect(line.modifierTotal, Money.fromWhole(20, Currency.tryLira));
    });
  });

  group('OrderLine.create — tax snapshot', () {
    test('extracts VAT from lineTotal (post line-discount), not lineSubtotal',
        () {
      final line = OrderLine.create(
        productId: 'p1',
        productName: 'Bowl',
        quantity: 1,
        unitPrice: Money.fromWhole(110, Currency.tryLira),
        lineDiscount: Money.fromWhole(11, Currency.tryLira),
        taxRate: TaxPolicy.defaultRate,
      );

      // lineTotal = 99.00, VAT at 10% inclusive = 99 * 10 / 110 = 9.00
      expect(line.lineTotal, Money.fromWhole(99, Currency.tryLira));
      expect(line.tax.vatAmount, Money.fromWhole(9, Currency.tryLira));
      expect(line.tax.taxableBase, Money.fromWhole(90, Currency.tryLira));
    });

    test(
        'the tax snapshot freezes the rate given at construction, independent of TaxPolicy.defaultRate',
        () {
      const twentyPercent = TaxRate.fromBasisPoints(2000);
      final line = OrderLine.create(
        productId: 'p1',
        productName: 'Bowl',
        quantity: 1,
        unitPrice: Money.fromWhole(120, Currency.tryLira),
        taxRate: twentyPercent,
      );

      expect(line.tax.rate, twentyPercent);
      expect(line.tax.rate, isNot(TaxPolicy.defaultRate));
    });
  });

  group('OrderLine.create — validation', () {
    test('rejects a non-positive quantity', () {
      expect(
        () => OrderLine.create(
          productId: 'p1',
          productName: 'Bowl',
          quantity: 0,
          unitPrice: Money.fromWhole(100, Currency.tryLira),
          taxRate: TaxPolicy.defaultRate,
        ),
        throwsA(isA<NonPositiveQuantityViolation>()),
      );
    });

    test('rejects a negative line discount', () {
      expect(
        () => OrderLine.create(
          productId: 'p1',
          productName: 'Bowl',
          quantity: 1,
          unitPrice: Money.fromWhole(100, Currency.tryLira),
          lineDiscount: Money.fromWhole(-1, Currency.tryLira),
          taxRate: TaxPolicy.defaultRate,
        ),
        throwsA(isA<NegativeAmountViolation>()),
      );
    });

    test(
        'rejects a line discount larger than the line subtotal (negative total prevention)',
        () {
      expect(
        () => OrderLine.create(
          productId: 'p1',
          productName: 'Bowl',
          quantity: 1,
          unitPrice: Money.fromWhole(50, Currency.tryLira),
          lineDiscount: Money.fromWhole(100, Currency.tryLira),
          taxRate: TaxPolicy.defaultRate,
        ),
        throwsA(isA<NegativeTotalViolation>()),
      );
    });
  });
}
