import '../../../../shared/models/currency.dart';
import '../../../../shared/models/exchange_rate_snapshot.dart';
import '../../../../shared/models/money.dart';

/// One informational "estimated payment equivalent" line at the bottom of
/// a [Receipt] (approved receipt-enhancement decision) — e.g. "EUR: 15.48
/// €" under a 650.00 TRY total.
///
/// **Informational only** — [disclaimer] is fixed, always attached, and
/// must be shown alongside every equivalent: these values are not legally
/// binding or guaranteed, and the actual exchange rate is determined at
/// the moment of payment. [amount] is computed from the order's TRY grand
/// total using [exchangeRate]'s acceptance rate at receipt-issue time —
/// see `Receipt.build`'s doc comment for how it differs from a real
/// foreign-currency [PaymentSplit]'s own snapshot.
class ForeignCurrencyEquivalent {
  const ForeignCurrencyEquivalent({
    required this.currency,
    required this.amount,
    required this.exchangeRate,
  });

  final Currency currency;

  /// The order's TRY grand total converted to [currency] via
  /// [exchangeRate].
  final Money amount;

  final ExchangeRateSnapshot exchangeRate;

  /// Fixed disclaimer text — Turkish, user-facing, never reworded per call
  /// site (`docs/architecture_bible.md` §11: user-facing text is Turkish).
  static const String disclaimer =
      'Bu tutarlar yalnızca bilgilendirme amaçlıdır, bağlayıcı veya garanti '
      'edilen bir kur değildir. Ödeme anında geçerli kur esas alınır.';
}
