/// The level an [EntitlementGrant] applies at — Phase 7
/// (`docs/decisions.md` ADR-024). Unlike `LocalizationScopeType` (Phase
/// 6N, deliberately organization/branch only), entitlements are typically
/// purchased per brand/restaurant, so all three levels this codebase has
/// a real entity for are supported here.
enum EntitlementScopeType {
  organization,
  restaurant,
  branch,
}
