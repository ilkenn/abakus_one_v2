import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_number.dart';
import 'package:abakus_one_v2/features/orders/domain/pricing/price_calculator.dart';
import 'package:abakus_one_v2/features/orders/domain/receipt/foreign_currency_equivalent.dart';
import 'package:abakus_one_v2/features/orders/domain/receipt/payment_summary_line.dart';
import 'package:abakus_one_v2/features/orders/domain/receipt/receipt.dart';
import 'package:abakus_one_v2/features/payment/domain/models/payment_enums.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/exchange_rate_snapshot.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final summary = PriceCalculator.calculate(
    lines: const [],
    currency: Currency.tryLira,
  );

  group('Receipt construction', () {
    test('rejects an empty receipt number', () {
      expect(
        () => Receipt(
          receiptNumber: '',
          orderId: OrderId('order-1'),
          orderNumber: OrderNumber('A-001'),
          issuedAt: DateTime(2026, 7, 28),
          summary: summary,
        ),
        throwsA(isA<EmptyIdentifierViolation>()),
      );
    });

    test('defaults to empty payment summary and informational equivalents', () {
      final receipt = Receipt(
        receiptNumber: 'R-001',
        orderId: OrderId('order-1'),
        orderNumber: OrderNumber('A-001'),
        issuedAt: DateTime(2026, 7, 28),
        summary: summary,
      );

      expect(receipt.paymentSummary, isEmpty);
      expect(receipt.informationalEquivalents, isEmpty);
      expect(receipt.businessDetails.legalBusinessName, '');
    });
  });

  group('Receipt — foreign currency payment summary', () {
    test(
        'a foreign-currency payment line carries market rate, margin, acceptance rate, and TRY settlement',
        () {
      final snapshot = ExchangeRateSnapshot.capture(
        sourceCurrency: Currency.eur,
        marketSellingRate: Money.fromWhole(47, Currency.tryLira),
        rateTimestamp: DateTime(2026, 7, 28),
        rateSource: 'manual',
      );
      final receipt = Receipt(
        receiptNumber: 'R-001',
        orderId: OrderId('order-1'),
        orderNumber: OrderNumber('A-001'),
        issuedAt: DateTime(2026, 7, 28),
        summary: summary,
        paymentSummary: [
          PaymentSummaryLine(
            method: PaymentMethodType.creditCard,
            amount: Money.fromWhole(20, Currency.eur),
            settlementAmount: Money.fromWhole(840, Currency.tryLira),
            exchangeRate: snapshot,
          ),
        ],
      );

      final line = receipt.paymentSummary.single;
      expect(line.amount, Money.fromWhole(20, Currency.eur));
      expect(line.exchangeRate!.marketSellingRate,
          Money.fromWhole(47, Currency.tryLira));
      expect(
          line.exchangeRate!.fixedMargin, Money.fromWhole(5, Currency.tryLira));
      expect(line.exchangeRate!.acceptanceRate,
          Money.fromWhole(42, Currency.tryLira));
      expect(line.settlementAmount, Money.fromWhole(840, Currency.tryLira));
    });
  });

  group('Receipt — informational EUR/USD equivalents', () {
    test('carries the fixed, non-binding disclaimer', () {
      expect(ForeignCurrencyEquivalent.disclaimer, isNotEmpty);
      expect(
        ForeignCurrencyEquivalent.disclaimer.toLowerCase(),
        contains('bilgilendirme'),
      );
    });

    test(
        'the worked receipt example: 650.00 TRY total converts to EUR/USD equivalents',
        () {
      final eurSnapshot = ExchangeRateSnapshot.capture(
        sourceCurrency: Currency.eur,
        marketSellingRate: Money.fromWhole(47, Currency.tryLira),
        rateTimestamp: DateTime(2026, 7, 28),
        rateSource: 'manual',
      );
      // acceptanceRate 42.00 TRY/EUR; 650.00 TRY / 42.00 ~= 15.4761... EUR
      final totalTry = Money.fromWhole(650, Currency.tryLira);
      final eurAmount = Money(
        (totalTry.minorUnits * 100) ~/ eurSnapshot.acceptanceRate.minorUnits,
        Currency.eur,
      );

      final receipt = Receipt(
        receiptNumber: 'R-001',
        orderId: OrderId('order-1'),
        orderNumber: OrderNumber('A-001'),
        issuedAt: DateTime(2026, 7, 28),
        summary: summary,
        informationalEquivalents: [
          ForeignCurrencyEquivalent(
            currency: Currency.eur,
            amount: eurAmount,
            exchangeRate: eurSnapshot,
          ),
        ],
      );

      expect(receipt.informationalEquivalents.single.currency, Currency.eur);
      expect(receipt.informationalEquivalents.single.amount.currency,
          Currency.eur);
    });
  });
}
