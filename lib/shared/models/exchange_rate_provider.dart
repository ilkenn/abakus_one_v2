import 'currency.dart';
import 'exchange_rate_snapshot.dart';

/// Source of exchange rates for a foreign [Currency] against the
/// accounting currency (`Currency.accountingCurrency`, TRY today).
///
/// **Abstraction only** — no implementation exists this sprint. Daily rate
/// retrieval/provider integration is explicitly out of scope for Phase 3
/// Sprint 3A (see `docs/feature_status.md`); this interface exists so
/// payment, receipt, and (future) cashier-display code that needs "the
/// current rate" or "the rate as of some date" has one seam to depend on,
/// rather than being written against a concrete vendor that doesn't exist
/// yet. Pure Dart — no Flutter/Riverpod import, so nothing about how a
/// caller reacts to a refreshed rate (e.g. a future UI polling/subscribing
/// to it) lives here.
abstract interface class ExchangeRateProvider {
  /// The latest known [ExchangeRateSnapshot] for [currency] — used for
  /// current receipt estimations and any live cashier display. Always the
  /// most recently refreshed rate, never a stored historical one.
  Future<ExchangeRateSnapshot> getTodayRate(Currency currency);

  /// The [ExchangeRateSnapshot] that was in effect for [currency] at
  /// [at] — for historical lookups (e.g. reporting) only.
  ///
  /// **Never used to recompute a historical payment.** A `PaymentSplit`
  /// always uses its own already-captured `ExchangeRateSnapshot`
  /// (`PaymentSplit.exchangeRate`); this method exists for other
  /// historical-rate questions, not for re-deriving a past payment's
  /// amount.
  Future<ExchangeRateSnapshot> getRateAt(Currency currency, DateTime at);

  /// Forces this provider to fetch fresh rates from its underlying source.
  /// Every subsequent [getTodayRate] call reflects the refreshed value.
  Future<void> refreshRates();
}
