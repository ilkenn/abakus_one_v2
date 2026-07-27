import 'package:abakus_one_v2/features/orders/domain/receipt/foreign_currency_equivalents_calculator.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/exchange_rate_provider.dart';
import 'package:abakus_one_v2/shared/models/exchange_rate_snapshot.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeExchangeRateProvider implements ExchangeRateProvider {
  _FakeExchangeRateProvider(this._rates);

  final Map<String, ExchangeRateSnapshot> _rates;

  @override
  Future<ExchangeRateSnapshot> getTodayRate(Currency currency) async {
    final rate = _rates[currency.isoCode];
    if (rate == null) throw StateError('no rate for ${currency.isoCode}');
    return rate;
  }

  @override
  Future<ExchangeRateSnapshot> getRateAt(Currency currency, DateTime at) =>
      getTodayRate(currency);

  @override
  Future<void> refreshRates() async {}
}

void main() {
  final timestamp = DateTime(2026, 7, 28);

  group('ForeignCurrencyEquivalentsCalculator.build', () {
    test('the worked example: 650.00 TRY produces EUR and USD equivalents',
        () async {
      final provider = _FakeExchangeRateProvider({
        'EUR': ExchangeRateSnapshot.capture(
          sourceCurrency: Currency.eur,
          marketSellingRate: Money.fromWhole(47, Currency.tryLira),
          rateTimestamp: timestamp,
          rateSource: 'manual',
        ),
        'USD': ExchangeRateSnapshot.capture(
          sourceCurrency: Currency.usd,
          marketSellingRate: Money.fromWhole(41, Currency.tryLira),
          rateTimestamp: timestamp,
          rateSource: 'manual',
        ),
      });

      final equivalents = await ForeignCurrencyEquivalentsCalculator.build(
        accountingTotal: Money.fromWhole(650, Currency.tryLira),
        provider: provider,
      );

      expect(equivalents, hasLength(2));
      expect(equivalents.map((e) => e.currency), [Currency.eur, Currency.usd]);
      expect(equivalents.first.amount, const Money(1548, Currency.eur));
    });

    test(
        'defaults to every currency accepted by the business (excluding the accounting currency)',
        () async {
      final provider = _FakeExchangeRateProvider({
        'EUR': ExchangeRateSnapshot.capture(
          sourceCurrency: Currency.eur,
          marketSellingRate: Money.fromWhole(47, Currency.tryLira),
          rateTimestamp: timestamp,
          rateSource: 'manual',
        ),
        'USD': ExchangeRateSnapshot.capture(
          sourceCurrency: Currency.usd,
          marketSellingRate: Money.fromWhole(41, Currency.tryLira),
          rateTimestamp: timestamp,
          rateSource: 'manual',
        ),
      });

      final equivalents = await ForeignCurrencyEquivalentsCalculator.build(
        accountingTotal: Money.fromWhole(100, Currency.tryLira),
        provider: provider,
      );

      expect(
        equivalents.map((e) => e.currency),
        Currency.acceptedForeignCurrencies,
      );
    });

    test(
        'omits a currency whose rate is unavailable rather than fabricating one',
        () async {
      final provider = _FakeExchangeRateProvider({
        'EUR': ExchangeRateSnapshot.capture(
          sourceCurrency: Currency.eur,
          marketSellingRate: Money.fromWhole(47, Currency.tryLira),
          rateTimestamp: timestamp,
          rateSource: 'manual',
        ),
        // No USD rate registered.
      });

      final equivalents = await ForeignCurrencyEquivalentsCalculator.build(
        accountingTotal: Money.fromWhole(100, Currency.tryLira),
        provider: provider,
      );

      expect(equivalents, hasLength(1));
      expect(equivalents.single.currency, Currency.eur);
    });

    test('an explicit currencies list overrides the default set', () async {
      final provider = _FakeExchangeRateProvider({
        'EUR': ExchangeRateSnapshot.capture(
          sourceCurrency: Currency.eur,
          marketSellingRate: Money.fromWhole(47, Currency.tryLira),
          rateTimestamp: timestamp,
          rateSource: 'manual',
        ),
      });

      final equivalents = await ForeignCurrencyEquivalentsCalculator.build(
        accountingTotal: Money.fromWhole(100, Currency.tryLira),
        provider: provider,
        currencies: const [Currency.eur],
      );

      expect(equivalents, hasLength(1));
      expect(equivalents.single.currency, Currency.eur);
    });
  });
}
