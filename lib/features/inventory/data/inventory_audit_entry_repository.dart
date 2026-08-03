import '../domain/inventory_audit_entry.dart';

abstract interface class InventoryAuditEntryRepository {
  Future<void> appendEvent(InventoryAuditEntry entry);
  Future<List<InventoryAuditEntry>> findByTargetEntityId(String targetEntityId);
  Future<List<InventoryAuditEntry>> findByBranchId(String branchId);
}

class InMemoryInventoryAuditEntryRepository
    implements InventoryAuditEntryRepository {
  final List<InventoryAuditEntry> _entries = [];

  @override
  Future<void> appendEvent(InventoryAuditEntry entry) async {
    _entries.add(entry);
  }

  @override
  Future<List<InventoryAuditEntry>> findByTargetEntityId(
      String targetEntityId) async {
    return List.unmodifiable(
      _entries.where((e) => e.targetEntityId == targetEntityId),
    );
  }

  @override
  Future<List<InventoryAuditEntry>> findByBranchId(String branchId) async {
    return List.unmodifiable(_entries.where((e) => e.branchId == branchId));
  }
}
