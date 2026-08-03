import '../domain/allergen_audit_entry.dart';

abstract interface class AllergenAuditEntryRepository {
  Future<void> appendEvent(AllergenAuditEntry entry);
  Future<List<AllergenAuditEntry>> findByTargetEntityId(String targetEntityId);
  Future<List<AllergenAuditEntry>> findByOrganizationId(String organizationId);
}

class InMemoryAllergenAuditEntryRepository
    implements AllergenAuditEntryRepository {
  final List<AllergenAuditEntry> _entries = [];

  @override
  Future<void> appendEvent(AllergenAuditEntry entry) async {
    _entries.add(entry);
  }

  @override
  Future<List<AllergenAuditEntry>> findByTargetEntityId(
      String targetEntityId) async {
    return List.unmodifiable(
      _entries.where((e) => e.targetEntityId == targetEntityId),
    );
  }

  @override
  Future<List<AllergenAuditEntry>> findByOrganizationId(
      String organizationId) async {
    return List.unmodifiable(
      _entries.where((e) => e.organizationId == organizationId),
    );
  }
}
