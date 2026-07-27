import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/exchange_rate_provider.dart';
import 'package:abakus_one_v2/shared/models/exchange_rate_snapshot.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

/// A minimal fake proving [ExchangeRateProvider]'s three-method shape is
/// implementable and usable without any real vendor — [getTodayRate]
/// always returns [current], [getRateAt] always returns [historical]
/// (proving the two are genuinely independent lookups), and
/// [refreshRates] swaps [current] for a new value, which the next
/// [getTodayRate] call reflects.
class _FakeExchangeRateProvider implements ExchangeRateProvider {
  _FakeExchangeRateProvider({required this.current, required this.historical});

  ExchangeRateSnapshot current;
  final ExchangeRateSnapshot historical;
  int refreshCount = 0;

  @override
  Future<ExchangeRateSnapshot> getTodayRate(Currency currency) async => current;

  @override
  Future<ExchangeRateSnapshot> getRateAt(
          Currency currency, DateTime at) async =>
      historical;

  @override
  Future<void> refreshRates() async {
    refreshCount++;
    current = ExchangeRateSnapshot.capture(
      sourceCurrency: current.sourceCurrency,
      marketSellingRate:
          current.marketSellingRate + Money.fromWhole(1, Currency.tryLira),
      rateTimestamp: current.rateTimestamp.add(const Duration(minutes: 1)),
      rateSource: current.rateSource,
    );
  }
}

ExchangeRateSnapshot _snapshotAt(DateTime timestamp, int marketRateWhole) {
  return ExchangeRateSnapshot.capture(
    sourceCurrency: Currency.eur,
    marketSellingRate: Money.fromWhole(marketRateWhole, Currency.tryLira),
    rateTimestamp: timestamp,
    rateSource: 'manual',
  );
}

void main() {
  group('ExchangeRateProvider', () {
    test('getTodayRate returns the current rate', () async {
      final provider = _FakeExchangeRateProvider(
        current: _snapshotAt(DateTime(2026, 7, 28), 47),
        historical: _snapshotAt(DateTime(2026, 7, 1), 44),
      );

      final rate = await provider.getTodayRate(Currency.eur);

      expect(rate.marketSellingRate, Money.fromWhole(47, Currency.tryLira));
    });

    test('getRateAt returns a rate independent of getTodayRate', () async {
      final provider = _FakeExchangeRateProvider(
        current: _snapshotAt(DateTime(2026, 7, 28), 47),
        historical: _snapshotAt(DateTime(2026, 7, 1), 44),
      );

      final historicalRate =
          await provider.getRateAt(Currency.eur, DateTime(2026, 7, 1));

      expect(historicalRate.marketSellingRate,
          Money.fromWhole(44, Currency.tryLira));
    });

    test('refreshRates changes what a subsequent getTodayRate call returns',
        () async {
      final provider = _FakeExchangeRateProvider(
        current: _snapshotAt(DateTime(2026, 7, 28), 47),
        historical: _snapshotAt(DateTime(2026, 7, 1), 44),
      );

      final before = await provider.getTodayRate(Currency.eur);
      await provider.refreshRates();
      final after = await provider.getTodayRate(Currency.eur);

      expect(after.marketSellingRate, isNot(before.marketSellingRate));
      expect(provider.refreshCount, 1);
    });
  });
}
