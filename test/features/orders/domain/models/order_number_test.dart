import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_number.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OrderNumber', () {
    test('wraps a non-empty externally supplied value', () {
      expect(OrderNumber('A-042').value, 'A-042');
    });

    test('rejects an empty value', () {
      expect(() => OrderNumber(''), throwsA(isA<EmptyIdentifierViolation>()));
    });

    test('equality is value-based', () {
      expect(OrderNumber('A-042'), OrderNumber('A-042'));
      expect(OrderNumber('A-042') == OrderNumber('A-043'), isFalse);
    });
  });
}
