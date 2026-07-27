import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BusinessRuleViolation', () {
    test('is throwable and catchable as Exception', () {
      expect(
        () => throw const NegativeTotalViolation(
          minorUnits: -100,
          currencyCode: 'TRY',
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('toString includes the runtime type and description', () {
      const violation = CurrencyMismatchViolation(
        expectedCurrencyCode: 'TRY',
        actualCurrencyCode: 'EUR',
      );

      expect(violation.toString(), contains('CurrencyMismatchViolation'));
      expect(violation.toString(), contains('TRY'));
      expect(violation.toString(), contains('EUR'));
    });

    test('every subtype exposes a non-empty description', () {
      const violations = <BusinessRuleViolation>[
        NegativeTotalViolation(minorUnits: -1, currencyCode: 'TRY'),
        CurrencyMismatchViolation(
          expectedCurrencyCode: 'TRY',
          actualCurrencyCode: 'EUR',
        ),
        InvalidOrderStatusTransitionViolation(
          fromStatusName: 'created',
          toStatusName: 'preparing',
        ),
        EmptyIdentifierViolation(identifierName: 'OrderId'),
        EmptyOrderViolation(),
        MultipleDiscountsNotSupportedViolation(discountCount: 2),
      ];

      for (final violation in violations) {
        expect(violation.description, isNotEmpty);
      }
    });
  });
}
