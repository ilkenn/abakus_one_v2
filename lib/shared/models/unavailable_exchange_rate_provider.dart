import 'currency.dart';
import 'exchange_rate_provider.dart';
import 'exchange_rate_snapshot.dart';

/// The production-default [ExchangeRateProvider] — **never returns an
/// invented rate**. Every method fails, which is exactly what makes it
/// safe as the default: no real daily-rate source is integrated yet (see
/// `docs/business_rules.md` BR-PAY-009, ROADMAP), and a plausible-looking
/// but fabricated number would be worse than an honest "unavailable"
/// state.
///
/// `ForeignCurrencyEquivalentsCalculator.build` already catches a failing
/// [getTodayRate] call per-currency and omits that currency rather than
/// propagating the failure — so wiring this provider in by default makes
/// the cashier UI's "rates unavailable" state the natural, honest
/// out-of-the-box behavior, not a special case the UI has to detect
/// itself.
class UnavailableExchangeRateProvider implements ExchangeRateProvider {
  const UnavailableExchangeRateProvider();

  @override
  Future<ExchangeRateSnapshot> getTodayRate(Currency currency) {
    throw StateError(
      'No exchange rate source is configured for ${currency.isoCode}.',
    );
  }

  @override
  Future<ExchangeRateSnapshot> getRateAt(Currency currency, DateTime at) {
    throw StateError(
      'No exchange rate source is configured for ${currency.isoCode}.',
    );
  }

  @override
  Future<void> refreshRates() async {}
}
