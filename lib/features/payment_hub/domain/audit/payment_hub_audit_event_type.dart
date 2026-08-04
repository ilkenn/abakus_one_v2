/// Every Payment Hub mutation this codebase records — Phase 8
/// (`docs/decisions.md` ADR-025). One shared trail across every
/// sub-concept (merchant account/method mapping/settlement) — mirrors
/// `MarketplaceAuditEntry`'s (8I) and `RestaurantOperationsAuditEntry`'s
/// (Phase 3D) established one-repository-per-bounded-context precedent.
/// A wholly separate trail from `features/payment`'s own order-time
/// payment records (`ClosureAuditEntry` already covers those) — Payment
/// Hub is tenant-configuration, not order-time payment collection.
enum PaymentHubAuditEventType {
  merchantAccountCreated,
  paymentMethodMapped,
  settlementRecorded,
}
