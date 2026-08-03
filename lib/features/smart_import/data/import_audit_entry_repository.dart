import '../domain/import_audit_entry.dart';

/// Append-only storage for [ImportAuditEntry] — no update or delete
/// method exists at all, matching every other audit repository in this
/// codebase.
abstract interface class ImportAuditEntryRepository {
  Future<void> appendEvent(ImportAuditEntry entry);
  Future<List<ImportAuditEntry>> findByTargetEntityId(String targetEntityId);
  Future<List<ImportAuditEntry>> findByBranchId(String branchId);
}

class InMemoryImportAuditEntryRepository implements ImportAuditEntryRepository {
  final List<ImportAuditEntry> _entries = [];

  @override
  Future<void> appendEvent(ImportAuditEntry entry) async {
    _entries.add(entry);
  }

  @override
  Future<List<ImportAuditEntry>> findByTargetEntityId(
      String targetEntityId) async {
    return List.unmodifiable(
      _entries.where((e) => e.targetEntityId == targetEntityId),
    );
  }

  @override
  Future<List<ImportAuditEntry>> findByBranchId(String branchId) async {
    return List.unmodifiable(_entries.where((e) => e.branchId == branchId));
  }
}
