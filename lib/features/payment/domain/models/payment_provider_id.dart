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
}
