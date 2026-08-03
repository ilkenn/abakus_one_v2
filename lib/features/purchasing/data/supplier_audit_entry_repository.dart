import '../domain/supplier_audit_entry.dart';

abstract interface class SupplierAuditEntryRepository {
  Future<void> appendEvent(SupplierAuditEntry entry);
  Future<List<SupplierAuditEntry>> findByTargetEntityId(String targetEntityId);
  Future<List<SupplierAuditEntry>> findByOrganizationId(String organizationId);
}

class InMemorySupplierAuditEntryRepository
    implements SupplierAuditEntryRepository {
  final List<SupplierAuditEntry> _entries = [];

  @override
  Future<void> appendEvent(SupplierAuditEntry entry) async {
    _entries.add(entry);
  }

  @override
  Future<List<SupplierAuditEntry>> findByTargetEntityId(
      String targetEntityId) async {
    return List.unmodifiable(
      _entries.where((e) => e.targetEntityId == targetEntityId),
    );
  }

  @override
  Future<List<SupplierAuditEntry>> findByOrganizationId(
      String organizationId) async {
    return List.unmodifiable(
      _entries.where((e) => e.organizationId == organizationId),
    );
  }
}
