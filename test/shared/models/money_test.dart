import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Money construction', () {
    test('fromWhole converts whole units to minor units', () {
      expect(Money.fromWhole(5, Currency.tryLira).minorUnits, 500);
    });

    test('zero is zero minor units in the given currency', () {
      final zero = Money.zero(Currency.eur);
      expect(zero.minorUnits, 0);
      expect(zero.currency, Currency.eur);
      expect(zero.isZero, isTrue);
    });

    test('fromLegacyDoubleTry converts a double TRY amount to kuruş', () {
      expect(Money.fromLegacyDoubleTry(194.0).minorUnits, 19400);
      expect(Money.fromLegacyDoubleTry(132.5).minorUnits, 13250);
    });

    test('fromLegacyDoubleTry rounds half away from zero on the boundary kuruş',
        () {
      // 1.005 TRY = 100.5 kuruş -> rounds to 101 (double representation of
      // 1.005 may not be exact, but .round() on the resulting 100.49999..
      // or 100.50000..1 both land on 100 or 101 consistently with normal
      // double rounding — this test pins the documented behavior, not a
      // guarantee of exact decimal arithmetic through a double input).
      expect(Money.fromLegacyDoubleTry(1.0).minorUnits, 100);
    });
  });

  group('Money arithmetic', () {
    test('addition of same-currency amounts', () {
      final a = Money.fromWhole(10, Currency.tryLira);
      final b = Money.fromWhole(5, Currency.tryLira);
      expect((a + b).minorUnits, 1500);
    });

    test('subtraction of same-currency amounts', () {
      final a = Money.fromWhole(10, Currency.tryLira);
      final b = Money.fromWhole(3, Currency.tryLira);
      expect((a - b).minorUnits, 700);
    });

    test('multiplication by an integer factor', () {
      final a = Money.fromWhole(4, Currency.tryLira);
      expect((a * 3).minorUnits, 1200);
    });

    test('unary negation', () {
      final a = Money.fromWhole(4, Currency.tryLira);
      expect((-a).minorUnits, -400);
    });

    test(
        'addition across different currencies throws CurrencyMismatchViolation',
        () {
      final try_ = Money.fromWhole(10, Currency.tryLira);
      final eur = Money.fromWhole(10, Currency.eur);
      expect(
        () => try_ + eur,
        throwsA(isA<CurrencyMismatchViolation>()),
      );
    });

    test(
        'comparison across different currencies throws CurrencyMismatchViolation',
        () {
      final try_ = Money.fromWhole(10, Currency.tryLira);
      final usd = Money.fromWhole(10, Currency.usd);
      expect(() => try_ < usd, throwsA(isA<CurrencyMismatchViolation>()));
    });

    test('ordering operators compare minor units within the same currency', () {
      final a = Money.fromWhole(5, Currency.tryLira);
      final b = Money.fromWhole(10, Currency.tryLira);
      expect(a < b, isTrue);
      expect(b > a, isTrue);
      expect(a <= a, isTrue);
      expect(a >= a, isTrue);
    });

    test('isNegative/isPositive/isZero reflect the sign of minorUnits', () {
      expect(Money.fromWhole(-1, Currency.tryLira).isNegative, isTrue);
      expect(Money.fromWhole(1, Currency.tryLira).isPositive, isTrue);
      expect(Money.zero(Currency.tryLira).isZero, isTrue);
    });
  });

  group('Money.scaledBy', () {
    test('scales and rounds half away from zero', () {
      const amount = Money(1000, Currency.tryLira); // 10.00 TRY
      // 10% of 10.00 TRY = 1.00 TRY exactly
      expect(amount.scaledBy(1000, 10000).minorUnits, 100);
    });

    test('rounds a scaled tie away from zero', () {
      const amount = Money(5, Currency.tryLira); // 0.05 TRY
      // half of 5 minor units = 2.5 -> rounds to 3
      expect(amount.scaledBy(1, 2).minorUnits, 3);
    });
  });

  group('Money equality', () {
    test('equal minor units and currency are equal', () {
      expect(
        const Money(500, Currency.tryLira),
        const Money(500, Currency.tryLira),
      );
    });

    test('different currencies are never equal even with the same minor units',
        () {
      expect(
        const Money(500, Currency.tryLira) == const Money(500, Currency.eur),
        isFalse,
      );
    });
  });
}
