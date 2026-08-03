import '../domain/profitability_audit_entry.dart';

abstract interface class ProfitabilityAuditEntryRepository {
  Future<void> appendEvent(ProfitabilityAuditEntry entry);
  Future<List<ProfitabilityAuditEntry>> findByTargetEntityId(
      String targetEntityId);
  Future<List<ProfitabilityAuditEntry>> findByOrganizationId(
      String organizationId);
}

class InMemoryProfitabilityAuditEntryRepository
    implements ProfitabilityAuditEntryRepository {
  final List<ProfitabilityAuditEntry> _entries = [];

  @override
  Future<void> appendEvent(ProfitabilityAuditEntry entry) async {
    _entries.add(entry);
  }

  @override
  Future<List<ProfitabilityAuditEntry>> findByTargetEntityId(
      String targetEntityId) async {
    return List.unmodifiable(
      _entries.where((e) => e.targetEntityId == targetEntityId),
    );
  }

  @override
  Future<List<ProfitabilityAuditEntry>> findByOrganizationId(
      String organizationId) async {
    return List.unmodifiable(
      _entries.where((e) => e.organizationId == organizationId),
    );
  }
}
