import '../domain/setup_audit_entry.dart';

abstract interface class SetupAuditEntryRepository {
  Future<void> appendEvent(SetupAuditEntry entry);
  Future<List<SetupAuditEntry>> findByTargetEntityId(String targetEntityId);
  Future<List<SetupAuditEntry>> findByBranchId(String branchId);
}

class InMemorySetupAuditEntryRepository implements SetupAuditEntryRepository {
  final List<SetupAuditEntry> _entries = [];

  @override
  Future<void> appendEvent(SetupAuditEntry entry) async {
    _entries.add(entry);
  }

  @override
  Future<List<SetupAuditEntry>> findByTargetEntityId(
      String targetEntityId) async {
    return List.unmodifiable(
      _entries.where((e) => e.targetEntityId == targetEntityId),
    );
  }

  @override
  Future<List<SetupAuditEntry>> findByBranchId(String branchId) async {
    return List.unmodifiable(_entries.where((e) => e.branchId == branchId));
  }
}
