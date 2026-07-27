import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OrderId', () {
    test('wraps a non-empty externally supplied value', () {
      expect(OrderId('order-1').value, 'order-1');
    });

    test('rejects an empty value', () {
      expect(() => OrderId(''), throwsA(isA<EmptyIdentifierViolation>()));
    });

    test('equality is value-based', () {
      expect(OrderId('a'), OrderId('a'));
      expect(OrderId('a') == OrderId('b'), isFalse);
    });

    test('toString returns the raw value', () {
      expect(OrderId('order-42').toString(), 'order-42');
    });
  });
}
