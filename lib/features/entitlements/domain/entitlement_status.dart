/// Lifecycle status of an [EntitlementGrant] — Phase 7
/// (`docs/decisions.md` ADR-024), extended AP-2 final wiring with [grace]/
/// [suspended] to match `entitlementAdmin.ts`'s real `EntitlementStatus`
/// union exactly (`functions/src/entitlementAdmin.ts`'s own 6-value type:
/// `trial|active|grace|suspended|expired|revoked`). [active]/[trial]/
/// [grace] all count as entitled (see [EntitlementGrant.isCurrentlyEntitled]
/// — mirrors the backend's own `requireModuleEntitlement`'s entitled-status
/// set exactly, "grace still works, by design"); [suspended]/[expired]/
/// [revoked] never do, regardless of date range — an explicit status
/// change is authoritative over a date comparison alone.
enum EntitlementStatus {
  active,
  trial,

  /// A real, fixed 72-hour window after [suspended] the backend enters
  /// automatically (`suspendEntitlement`'s `GRACE_PERIOD_DAYS = 3`) —
  /// module access is NOT yet cut off during this window.
  grace,

  /// Reached automatically once a [grace] window's `graceEndsAt` passes
  /// (`sweepExpiredEntitlementGracePeriods`), never set directly by any
  /// client action.
  suspended,

  expired,
  revoked,
}
