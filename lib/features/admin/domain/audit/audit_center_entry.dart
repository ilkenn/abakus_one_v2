/// One row of the unified Audit Center read-model — Phase 6M
/// (`docs/decisions.md` ADR-023). A normalized projection over several
/// independently-typed, independently-repo'd audit trails (see
/// `BuildAuditCenterProjection`'s own doc comment for exactly which
/// ones, and why not all 8 that exist in this codebase are included).
/// Read-only, never written back to any source repository.
class AuditCenterEntry {
  const AuditCenterEntry({
    required this.id,
    required this.domain,
    this.branchId,
    required this.actorId,
    this.actorRole,
    required this.description,
    required this.targetEntityId,
    required this.timestamp,
  });

  final String id;

  /// Which bounded context this entry came from — `'courier'`,
  /// `'kitchen'`, `'restaurant-operations'`, or `'admin'`.
  final String domain;

  final String? branchId;
  final String actorId;
  final String? actorRole;
  final String description;
  final String targetEntityId;
  final DateTime timestamp;
}
