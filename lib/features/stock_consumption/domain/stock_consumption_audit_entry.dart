import 'stock_consumption_audit_event_type.dart';

/// Kept as its own type — continues the "separate audit type per
/// bounded context" precedent (`docs/decisions.md` ADR-024).
class StockConsumptionAuditEntry {
  const StockConsumptionAuditEntry({
    required this.id,
    required this.branchId,
    required this.actorId,
    required this.type,
    required this.description,
    required this.targetEntityId,
    required this.timestamp,
  });

  final String id;
  final String branchId;
  final String actorId;
  final StockConsumptionAuditEventType type;
  final String description;
  final String targetEntityId;
  final DateTime timestamp;
}
