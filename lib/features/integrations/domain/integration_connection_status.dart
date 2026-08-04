/// The generic health/configuration state of any Integration Hub
/// provider adapter — Phase 8 (`docs/decisions.md` ADR-025). Shared
/// across every category ([IntegrationProviderCategory]) so Provider
/// Health Monitoring (8M) and the Integration Hub's own status list can
/// render one consistent status shape regardless of whether the
/// underlying provider is a marketplace, a payment gateway, or a
/// future category.
///
/// Mirrors `PaymentStatus.notConfigured`'s existing precedent
/// (`features/payment`, Sprint 3C) generalized beyond payments —
/// [notConfigured] is the only status any adapter in this codebase
/// reports until a real vendor integration is wired, per every prior
/// provider-adapter precedent (`ExchangeRateProvider`,
/// `ReceiptPrintProvider`, `PaymentProviderAdapter`).
enum IntegrationConnectionStatus {
  /// No credentials/configuration exist for this provider yet — the
  /// honest default for every adapter in this codebase today.
  notConfigured,

  /// Configuration exists but has not been used to establish a live
  /// connection/handshake yet.
  configured,

  /// A live connection/handshake has succeeded.
  connected,

  /// A configured provider's last connection attempt failed.
  error,

  /// Explicitly turned off by a tenant/platform administrator, distinct
  /// from never having been configured at all.
  disabled,
}
