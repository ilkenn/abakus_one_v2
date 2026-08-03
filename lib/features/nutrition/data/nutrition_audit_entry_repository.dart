import '../domain/nutrition_audit_entry.dart';

abstract interface class NutritionAuditEntryRepository {
  Future<void> appendEvent(NutritionAuditEntry entry);
  Future<List<NutritionAuditEntry>> findByTargetEntityId(String targetEntityId);
  Future<List<NutritionAuditEntry>> findByOrganizationId(String organizationId);
}

class InMemoryNutritionAuditEntryRepository
    implements NutritionAuditEntryRepository {
  final List<NutritionAuditEntry> _entries = [];

  @override
  Future<void> appendEvent(NutritionAuditEntry entry) async {
    _entries.add(entry);
  }

  @override
  Future<List<NutritionAuditEntry>> findByTargetEntityId(
      String targetEntityId) async {
    return List.unmodifiable(
      _entries.where((e) => e.targetEntityId == targetEntityId),
    );
  }

  @override
  Future<List<NutritionAuditEntry>> findByOrganizationId(
      String organizationId) async {
    return List.unmodifiable(
      _entries.where((e) => e.organizationId == organizationId),
    );
  }
}
