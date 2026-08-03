import '../domain/costing_audit_entry.dart';

abstract interface class CostingAuditEntryRepository {
  Future<void> appendEvent(CostingAuditEntry entry);
  Future<List<CostingAuditEntry>> findByTargetEntityId(String targetEntityId);
  Future<List<CostingAuditEntry>> findByOrganizationId(String organizationId);
}

class InMemoryCostingAuditEntryRepository
    implements CostingAuditEntryRepository {
  final List<CostingAuditEntry> _entries = [];

  @override
  Future<void> appendEvent(CostingAuditEntry entry) async {
    _entries.add(entry);
  }

  @override
  Future<List<CostingAuditEntry>> findByTargetEntityId(
      String targetEntityId) async {
    return List.unmodifiable(
      _entries.where((e) => e.targetEntityId == targetEntityId),
    );
  }

  @override
  Future<List<CostingAuditEntry>> findByOrganizationId(
      String organizationId) async {
    return List.unmodifiable(
      _entries.where((e) => e.organizationId == organizationId),
    );
  }
}
