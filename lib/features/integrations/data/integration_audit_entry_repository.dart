import '../domain/audit/integration_audit_entry.dart';

abstract interface class IntegrationAuditEntryRepository {
  Future<void> appendEvent(IntegrationAuditEntry entry);
  Future<List<IntegrationAuditEntry>> findByTargetEntityId(
      String targetEntityId);
  Future<List<IntegrationAuditEntry>> findByOrganizationId(
      String organizationId);
}

class InMemoryIntegrationAuditEntryRepository
    implements IntegrationAuditEntryRepository {
  final List<IntegrationAuditEntry> _entries = [];

  @override
  Future<void> appendEvent(IntegrationAuditEntry entry) async {
    _entries.add(entry);
  }

  @override
  Future<List<IntegrationAuditEntry>> findByTargetEntityId(
      String targetEntityId) async {
    return List.unmodifiable(
      _entries.where((e) => e.targetEntityId == targetEntityId),
    );
  }

  @override
  Future<List<IntegrationAuditEntry>> findByOrganizationId(
      String organizationId) async {
    return List.unmodifiable(
      _entries.where((e) => e.organizationId == organizationId),
    );
  }
}
