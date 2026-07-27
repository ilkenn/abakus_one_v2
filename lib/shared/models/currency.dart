/// A currency this app can represent a [Money] amount in.
///
/// **Extensible model** (approved architecture refinement, Phase 3 Sprint
/// 3A): every currency is a data instance, not an enum branch — no domain
/// code (`Money`, `TaxRate`, `PriceCalculator`, `ExchangeRateSnapshot`,
/// `PaymentSplit`, ...) ever switches on *which* currency it is. Adding a
/// future currency (GBP, CHF, SAR, AED, ...) is purely a matter of adding
/// one more `static const Currency` entry (and to [all]) — no business
/// logic anywhere needs to change, since every consumer reads only the
/// generic fields below.
///
/// `tryLira` rather than `try` as the identifier — `try` is a reserved
/// Dart keyword and cannot be used under any capitalization this codebase
/// follows.
///
/// Scope (approved multi-currency payment decision): accounting and menu
/// pricing remain TRY-based; only currencies with [isAcceptedByBusiness]
/// `true` may ever be tendered as payment or shown as an informational
/// receipt equivalent — see `ExchangeRateSnapshot`/`PaymentSplit`.
class Currency {
  /// Public — a [Currency] is a genuine value type (like [Money]), not a
  /// closed catalog only constructible from this file. The canonical set
  /// this app actually treats as "known" is [all]; constructing one
  /// ad hoc (e.g. a not-yet-`isAcceptedByBusiness` fixture in a test) is
  /// supported but doesn't itself register the currency anywhere.
  const Currency({
    required this.isoCode,
    required this.displayName,
    required this.symbol,
    required this.decimalDigits,
    required this.isDefault,
    required this.isActive,
    required this.isAcceptedByBusiness,
  });

  /// ISO 4217 alphabetic code (e.g. `'TRY'`).
  final String isoCode;

  /// Human-readable name (e.g. `'Türk Lirası'`) — display-layer text, kept
  /// here rather than hardcoded per-screen so it has exactly one owner.
  final String displayName;

  /// Currency symbol (e.g. `'₺'`).
  final String symbol;

  /// Number of minor-unit decimal digits (2 for kuruş/cents). Not every
  /// real-world currency uses 2 — kept per-currency rather than a
  /// hardcoded `100` at every call site.
  final int decimalDigits;

  /// Whether this is the app's single accounting/menu-pricing currency.
  /// Exactly one [Currency] in [all] has this `true` (TRY) — `Money`/
  /// `Order`/`PriceCalculator` figures are always in this currency; see
  /// `docs/business_rules.md` BR-PAY-006.
  final bool isDefault;

  /// Whether this currency is enabled in the system at all (known to the
  /// app, shown in configuration/reporting). A currency can be [isActive]
  /// without being [isAcceptedByBusiness] (e.g. configured but not yet
  /// approved for the till).
  final bool isActive;

  /// Whether the business currently accepts this currency as payment (and
  /// shows it as an informational receipt/cashier equivalent). Gates
  /// `PaymentSplit.foreignCurrency` and every foreign-currency-equivalent
  /// computation — never assumed from [isActive] alone.
  final bool isAcceptedByBusiness;

  /// `10 ^ decimalDigits` — how many minor units make one whole unit.
  int get minorUnitsPerWhole {
    var result = 1;
    for (var i = 0; i < decimalDigits; i++) {
      result *= 10;
    }
    return result;
  }

  static const Currency tryLira = Currency(
    isoCode: 'TRY',
    displayName: 'Türk Lirası',
    symbol: '₺',
    decimalDigits: 2,
    isDefault: true,
    isActive: true,
    isAcceptedByBusiness: true,
  );

  static const Currency eur = Currency(
    isoCode: 'EUR',
    displayName: 'Euro',
    symbol: '€',
    decimalDigits: 2,
    isDefault: false,
    isActive: true,
    isAcceptedByBusiness: true,
  );

  static const Currency usd = Currency(
    isoCode: 'USD',
    displayName: 'ABD Doları',
    symbol: '\$',
    decimalDigits: 2,
    isDefault: false,
    isActive: true,
    isAcceptedByBusiness: true,
  );

  /// Every currency configured in this app, initially TRY/EUR/USD.
  /// Enabling a new one is adding it here — the sole place a currency's
  /// existence is declared.
  static const List<Currency> all = [tryLira, eur, usd];

  /// [all] currencies with [isActive] `true`.
  static List<Currency> get active =>
      all.where((currency) => currency.isActive).toList();

  /// [all] currencies with [isAcceptedByBusiness] `true`.
  static List<Currency> get acceptedByBusiness =>
      all.where((currency) => currency.isAcceptedByBusiness).toList();

  /// The app's single accounting/menu-pricing currency — the [Currency]
  /// in [all] with [isDefault] `true` (TRY today).
  static Currency get accountingCurrency =>
      all.firstWhere((currency) => currency.isDefault);

  /// Currencies the business accepts as payment, excluding
  /// [accountingCurrency] itself — the set a foreign-currency payment or
  /// an informational receipt/cashier equivalent may use.
  static List<Currency> get acceptedForeignCurrencies => acceptedByBusiness
      .where((currency) => currency != accountingCurrency)
      .toList();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Currency && other.isoCode == isoCode);

  @override
  int get hashCode => isoCode.hashCode;

  @override
  String toString() => isoCode;
}
