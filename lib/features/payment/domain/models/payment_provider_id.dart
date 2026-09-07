/// Identifies a technical payment-processing integration — distinct from
/// [PaymentMethod] (the instrument a cashier selects). See
/// `docs/decisions.md` ADR-012 for why these two concepts are modeled
/// separately: `cash`/`bankTransfer`/`giftVoucher` methods never carry a
/// [PaymentProviderId] at all (manually recorded, no adapter call — see
/// `PaymentMethodSeedData` and `docs/business_rules.md`), while card and
/// meal-card methods map to one of these.
///
/// **Abstraction only, this sprint** — every provider adapter behind these
/// ids returns "not configured" (`PaymentStatus.notConfigured`); no real
/// integration exists.
enum PaymentProviderId {
  iyzico,
  stripe,
  adyen,
  odeal,
  pluxee,
  multinet,
  setcard,
  edenred,
  metropolCard,

  /// AP-4 hardware-unblocking sprint — the physical, card-present PAX
  /// A910SF terminal running the TEB POS Android application, triggered
  /// via an on-device Intent (distinct in kind from the other ids above,
  /// which are all online/API-based processors). **Still a stub, like
  /// every other id here**: `docs/payment_cash_fiscal_architecture.md`
  /// §14/§21 locks the exact PAX/TEB Intent contract (action, package,
  /// extras, result schema) as a `CONTROLLED_EXTERNAL_DEPENDENCY` —
  /// "no vendor protocol detail is written without official vendor
  /// documentation" — so [PaxTebTerminalAdapter] fabricates none of it and
  /// returns `PaymentStatus.notConfigured` until real PAX/TEB integration
  /// documentation is obtained.
  paxTeb,
}
