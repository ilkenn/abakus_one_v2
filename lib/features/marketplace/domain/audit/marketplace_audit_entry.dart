import 'marketplace_audit_event_type.dart';

/// One immutable, append-only audit record of a Marketplace Hub
/// mutation — Phase 8 (`docs/decisions.md` ADR-025).
class MarketplaceAuditEntry {
  const MarketplaceAuditEntry({
    required this.id,
    required this.organizationId,
    required this.actorId,
    required this.type,
    required this.description,
    required this.targetEntityId,
    required this.timestamp,
  });

  final String id;
  final String organizationId;
  final String actorId;
  final MarketplaceAuditEventType type;
  final String description;
  final String targetEntityId;
  final DateTime timestamp;
}
