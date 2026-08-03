/// Lifecycle status of an [EntitlementGrant] — Phase 7
/// (`docs/decisions.md` ADR-024). [active]/[trial] both count as
/// entitled (see [EntitlementGrant.isCurrentlyEntitled]); [expired]/
/// [revoked] never do, regardless of date range — an explicit status
/// change is authoritative over a date comparison alone.
enum EntitlementStatus {
  active,
  trial,
  expired,
  revoked,
}
