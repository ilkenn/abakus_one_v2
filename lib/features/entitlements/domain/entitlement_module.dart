/// A module a tenant must separately subscribe to before it is usable —
/// "has the tenant purchased this module?" — a deliberately separate
/// axis from `FeatureFlagsKeys` ("is it technically enabled?") and
/// `PosAuthorizedAction` ("may this actor do it?") — Phase 7
/// (`docs/decisions.md` ADR-024), extended Phase 8 (ADR-025) to cover
/// every module a white-label tenant can purchase, not only the Phase
/// 7 food-intelligence set. See `CheckModuleAccess` for where all three
/// axes combine into one authorization decision.
enum EntitlementModule {
  // Phase 7 — Smart Restaurant Setup, Inventory & Food Intelligence.
  smartRestaurantSetup,
  menuImport,
  inventory,
  recipes,
  nutrition,
  allergens,
  purchasing,
  suppliers,
  costing,
  profitability,
  advancedReporting,
  // Phase 8 — Platform, Integrations & White-Label Ecosystem
  // (`docs/decisions.md` ADR-025). Named to match the kickoff's own
  // 16-module purchasable list: QR Menu, Reservations, CRM, Loyalty,
  // POS, KDS, Courier, Marketplace, Payments, AI — the remaining 6
  // (Inventory, Recipes, Nutrition, Allergens, Reports, Smart Import)
  // already exist above (`advancedReporting`/`menuImport` cover
  // Reports/Smart Import respectively; no rename, per "never silently
  // modify roadmap items").
  qrMenu,
  reservations,
  crm,
  loyalty,
  pos,
  kds,
  courier,
  marketplace,
  payments,
  ai,
}
