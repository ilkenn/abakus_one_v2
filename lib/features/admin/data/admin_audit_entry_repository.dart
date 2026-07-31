import '../domain/audit/admin_audit_entry.dart';

/// Append-only storage for [AdminAuditEntry] — no update or delete method
/// exists at all, matching every other audit repository in this codebase.
abstract interface class AdminAuditEntryRepository {
  Future<void> appendEvent(AdminAuditEntry entry);
  Future<List<AdminAuditEntry>> findByTargetEntityId(String targetEntityId);
  Future<List<AdminAuditEntry>> findByActorId(String actorId);
  Future<List<AdminAuditEntry>> findByBranchId(String branchId);
  Future<List<AdminAuditEntry>> findAll();
}

class InMemoryAdminAuditEntryRepository implements AdminAuditEntryRepository {
  final List<AdminAuditEntry> _entries = [];

  @override
  Future<void> appendEvent(AdminAuditEntry entry) async {
    _entries.add(entry);
  }

  @override
  Future<List<AdminAuditEntry>> findByTargetEntityId(
      String targetEntityId) async {
    return List.unmodifiable(
      _entries.where((e) => e.targetEntityId == targetEntityId),
    );
  }

  @override
  Future<List<AdminAuditEntry>> findByActorId(String actorId) async {
    return List.unmodifiable(_entries.where((e) => e.actorId == actorId));
  }

  @override
  Future<List<AdminAuditEntry>> findByBranchId(String branchId) async {
    return List.unmodifiable(_entries.where((e) => e.branchId == branchId));
  }

  @override
  Future<List<AdminAuditEntry>> findAll() async => List.unmodifiable(_entries);
}
