import '../../../../shared/models/currency.dart';
import '../../../../shared/models/exchange_rate_provider.dart';
import '../../../../shared/models/money.dart';
import 'foreign_currency_equivalent.dart';

/// Computes the [ForeignCurrencyEquivalent] list every receipt/adisyon
/// must always print (approved receipt-enhancement decision), and that a
/// future cashier-facing "while the order is open" live display would use
/// the same way — this class has no dependency on `Receipt` specifically,
/// only on [Money]/[ExchangeRateProvider], so it's equally usable by both.
///
/// Pure domain logic: no Flutter/Riverpod import. A future UI polls or
/// subscribes to [ExchangeRateProvider] and re-runs [build] to get the
/// "updates automatically whenever exchange rates refresh" behavior — that
/// reactive wiring is presentation-layer work (out of scope this sprint,
/// POS UI is explicitly deferred), not something this class does itself.
abstract final class ForeignCurrencyEquivalentsCalculator {
  ForeignCurrencyEquivalentsCalculator._();

  /// Builds one [ForeignCurrencyEquivalent] per currency in [currencies]
  /// (defaulting to `Currency.acceptedForeignCurrencies` — every currency
  /// the business currently accepts, excluding the accounting currency
  /// itself), using [provider]'s latest known rate for each
  /// (`ExchangeRateProvider.getTodayRate`) — never a stored payment's
  /// historical rate.
  ///
  /// If a given currency's rate isn't currently available (the provider's
  /// future throws), that currency is silently omitted rather than the
  /// whole receipt failing to print — no fabricated estimate is ever
  /// substituted.
  static Future<List<ForeignCurrencyEquivalent>> build({
    required Money accountingTotal,
    required ExchangeRateProvider provider,
    List<Currency>? currencies,
  }) async {
    final targets = currencies ?? Currency.acceptedForeignCurrencies;
    final equivalents = <ForeignCurrencyEquivalent>[];
    for (final currency in targets) {
      try {
        final rate = await provider.getTodayRate(currency);
        equivalents.add(
          ForeignCurrencyEquivalent(
            currency: currency,
            amount: rate.convertFromTry(accountingTotal),
            exchangeRate: rate,
          ),
        );
      } catch (_) {
        // No rate available for this currency right now — omit it, don't
        // block the rest of the receipt or fabricate a number.
        continue;
      }
    }
    return equivalents;
  }
}
