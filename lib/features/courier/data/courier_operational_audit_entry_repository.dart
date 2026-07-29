import '../domain/audit/courier_operational_audit_entry.dart';

/// Append-only storage for [CourierOperationalAuditEntry] — no update or
/// delete method exists at all, matching every other audit repository in
/// this codebase.
abstract interface class CourierOperationalAuditEntryRepository {
  Future<void> appendEvent(CourierOperationalAuditEntry entry);
  Future<List<CourierOperationalAuditEntry>> findByCourierId(String courierId);
  Future<List<CourierOperationalAuditEntry>> findByDeliveryId(
      String deliveryId);
  Future<List<CourierOperationalAuditEntry>> findByBranchId(String branchId);
}

class InMemoryCourierOperationalAuditEntryRepository
    implements CourierOperationalAuditEntryRepository {
  final List<CourierOperationalAuditEntry> _entries = [];

  @override
  Future<void> appendEvent(CourierOperationalAuditEntry entry) async {
    _entries.add(entry);
  }

  @override
  Future<List<CourierOperationalAuditEntry>> findByCourierId(
      String courierId) async {
    return List.unmodifiable(
      _entries.where((e) => e.courierId == courierId),
    );
  }

  @override
  Future<List<CourierOperationalAuditEntry>> findByDeliveryId(
      String deliveryId) async {
    return List.unmodifiable(
      _entries.where((e) => e.deliveryId == deliveryId),
    );
  }

  @override
  Future<List<CourierOperationalAuditEntry>> findByBranchId(
      String branchId) async {
    return List.unmodifiable(
      _entries.where((e) => e.branchId == branchId),
    );
  }
}
