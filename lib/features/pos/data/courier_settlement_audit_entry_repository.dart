import '../domain/courier_settlement/courier_settlement_audit_entry.dart';

/// Append-only storage for [CourierSettlementAuditEntry] — no update or
/// delete method exists at all, mirroring `CashAuditEntryRepository`.
abstract interface class CourierSettlementAuditEntryRepository {
  Future<void> appendEvent(CourierSettlementAuditEntry entry);

  /// Every audit entry recorded for [settlementSessionId], oldest first.
  Future<List<CourierSettlementAuditEntry>> findBySettlementSessionId(
      String settlementSessionId);

  /// Every audit entry ever recorded for [courierId], across every
  /// settlement session they've ever had, oldest first.
  Future<List<CourierSettlementAuditEntry>> findByCourierId(String courierId);
}

/// In-memory [CourierSettlementAuditEntryRepository] — the only
/// implementation this sprint.
class InMemoryCourierSettlementAuditEntryRepository
    implements CourierSettlementAuditEntryRepository {
  final List<CourierSettlementAuditEntry> _entries = [];

  @override
  Future<void> appendEvent(CourierSettlementAuditEntry entry) async {
    _entries.add(entry);
  }

  @override
  Future<List<CourierSettlementAuditEntry>> findBySettlementSessionId(
      String settlementSessionId) async {
    return List.unmodifiable(
      _entries.where((e) => e.settlementSessionId == settlementSessionId),
    );
  }

  @override
  Future<List<CourierSettlementAuditEntry>> findByCourierId(
      String courierId) async {
    return List.unmodifiable(
      _entries.where((e) => e.courierId == courierId),
    );
  }
}
