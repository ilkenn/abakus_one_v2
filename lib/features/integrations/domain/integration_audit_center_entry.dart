/// One row of the unified Integration Audit Center read-model — Phase 8
/// (`docs/decisions.md` ADR-025), "Integration Audit." Mirrors
/// `AuditCenterEntry`'s (Phase 6M) exact projection shape: a normalized
/// view over several independently-typed, independently-repo'd audit
/// trails, tagged by which one each row came from. Read-only, never
/// written back to any source repository.
class IntegrationAuditCenterEntry {
  const IntegrationAuditCenterEntry({
    required this.id,
    required this.domain,
    required this.organizationId,
    required this.actorId,
    required this.description,
    required this.targetEntityId,
    required this.timestamp,
  });

  final String id;

  /// Which bounded context this entry came from — `'integration'`
  /// (Integration Hub enable/disable, credentials, webhooks),
  /// `'marketplace'` (Marketplace Hub), or `'payment-hub'` (Payment
  /// Hub).
  final String domain;

  final String organizationId;
  final String actorId;
  final String description;
  final String targetEntityId;
  final DateTime timestamp;
}
