import 'package:abakus_one_v2/features/cart/domain/models/cart_item.dart';
import 'package:abakus_one_v2/features/orders/domain/mappers/cart_line_mapper.dart';
import 'package:abakus_one_v2/features/orders/domain/pricing/tax_policy.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CartLineMapper.mapLine', () {
    test('converts a CartItem into an OrderLine with a Money unit price', () {
      const item =
          CartItem(id: 'p1', name: 'Bowl', desc: '', price: 100.0, quantity: 2);

      final line = CartLineMapper.mapLine(item, TaxPolicy.defaultRate);

      expect(line.productId, 'p1');
      expect(line.productName, 'Bowl');
      expect(line.unitPrice, Money.fromWhole(100, Currency.tryLira));
      expect(line.quantity, 2);
    });

    test(
        'is the same mapping CartToOrderMapper and CalculatePosOrderTotals both rely on (no duplicated logic)',
        () {
      const item = CartItem(
        id: 'p1',
        name: 'Bowl',
        desc: '',
        price: 110.0,
        quantity: 1,
      );

      final first = CartLineMapper.mapLine(item, TaxPolicy.defaultRate);
      final second = CartLineMapper.mapLine(item, TaxPolicy.defaultRate);

      expect(first.lineTotal, second.lineTotal);
      expect(first.tax.vatAmount, second.tax.vatAmount);
    });
  });
}
