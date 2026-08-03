/// A Phase 7 module a tenant must separately subscribe to before it is
/// usable — "has the tenant purchased this module?" — a deliberately
/// separate axis from `FeatureFlagsKeys` ("is it technically enabled?")
/// and `PosAuthorizedAction` ("may this actor do it?") — Phase 7
/// (`docs/decisions.md` ADR-024). See `CheckModuleAccess` for where all
/// three combine into one authorization decision.
enum EntitlementModule {
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
}
