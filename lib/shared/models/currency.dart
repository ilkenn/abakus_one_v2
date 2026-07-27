/// A currency this app can represent a [Money] amount in.
///
/// Named `tryLira` rather than `try` — `try` is a reserved Dart keyword and
/// cannot be an enum value under any capitalization rule this codebase
/// follows.
///
/// Scope (Phase 3 Sprint 3A, approved multi-currency payment decision):
/// accounting and menu pricing remain TRY-based; EUR/USD exist only to
/// represent an actual foreign-currency payment amount and its informational
/// receipt equivalent — see `ExchangeRateSnapshot`. Adding a fourth currency
/// is a new business decision, not a mechanical enum edit.
enum Currency {
  tryLira,
  eur,
  usd;

  /// ISO 4217 alphabetic code.
  String get isoCode {
    switch (this) {
      case Currency.tryLira:
        return 'TRY';
      case Currency.eur:
        return 'EUR';
      case Currency.usd:
        return 'USD';
    }
  }

  /// Number of minor-unit decimal digits (2 for all three currencies this
  /// app supports today — kuruş/cents). Kept as a per-currency lookup
  /// rather than a hardcoded `100` at every call site, since not every
  /// real-world currency uses 2 digits (this codebase just doesn't need
  /// one that doesn't, yet).
  int get minorUnitDigits {
    switch (this) {
      case Currency.tryLira:
      case Currency.eur:
      case Currency.usd:
        return 2;
    }
  }

  /// `10 ^ minorUnitDigits` — how many minor units make one whole unit.
  int get minorUnitsPerWhole {
    switch (this) {
      case Currency.tryLira:
      case Currency.eur:
      case Currency.usd:
        return 100;
    }
  }
}
