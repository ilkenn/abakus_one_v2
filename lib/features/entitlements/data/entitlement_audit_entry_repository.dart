import '../domain/audit/entitlement_audit_entry.dart';

/// Append-only storage for [EntitlementAuditEntry] — no update or delete
/// method exists at all, matching every other audit repository in this
/// codebase.
abstract interface class EntitlementAuditEntryRepository {
  Future<void> appendEvent(EntitlementAuditEntry entry);
  Future<List<EntitlementAuditEntry>> findByTargetEntityId(
      String targetEntityId);
  Future<List<EntitlementAuditEntry>> findAll();
}

class InMemoryEntitlementAuditEntryRepository
    implements EntitlementAuditEntryRepository {
  final List<EntitlementAuditEntry> _entries = [];

  @override
  Future<void> appendEvent(EntitlementAuditEntry entry) async {
    _entries.add(entry);
  }

  @override
  Future<List<EntitlementAuditEntry>> findByTargetEntityId(
      String targetEntityId) async {
    return List.unmodifiable(
      _entries.where((e) => e.targetEntityId == targetEntityId),
    );
  }

  @override
  Future<List<EntitlementAuditEntry>> findAll() async =>
      List.unmodifiable(_entries);
}
