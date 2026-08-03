import '../domain/recipe_audit_entry.dart';

abstract interface class RecipeAuditEntryRepository {
  Future<void> appendEvent(RecipeAuditEntry entry);
  Future<List<RecipeAuditEntry>> findByTargetEntityId(String targetEntityId);
  Future<List<RecipeAuditEntry>> findByOrganizationId(String organizationId);
}

class InMemoryRecipeAuditEntryRepository implements RecipeAuditEntryRepository {
  final List<RecipeAuditEntry> _entries = [];

  @override
  Future<void> appendEvent(RecipeAuditEntry entry) async {
    _entries.add(entry);
  }

  @override
  Future<List<RecipeAuditEntry>> findByTargetEntityId(
      String targetEntityId) async {
    return List.unmodifiable(
      _entries.where((e) => e.targetEntityId == targetEntityId),
    );
  }

  @override
  Future<List<RecipeAuditEntry>> findByOrganizationId(
      String organizationId) async {
    return List.unmodifiable(
      _entries.where((e) => e.organizationId == organizationId),
    );
  }
}
