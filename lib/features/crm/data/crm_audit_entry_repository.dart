import '../domain/audit/crm_audit_entry.dart';

/// Append-only storage for [CrmAuditEntry] — no update or delete method
/// exists at all, matching every other audit repository in this codebase
/// (`CourierOperationalAuditEntryRepository`, `KitchenAuditEntryRepository`).
abstract interface class CrmAuditEntryRepository {
  Future<void> appendEvent(CrmAuditEntry entry);
  Future<List<CrmAuditEntry>> findByTargetEntityId(String targetEntityId);
  Future<List<CrmAuditEntry>> findByActorId(String actorId);
}

class InMemoryCrmAuditEntryRepository implements CrmAuditEntryRepository {
  final List<CrmAuditEntry> _entries = [];

  @override
  Future<void> appendEvent(CrmAuditEntry entry) async {
    _entries.add(entry);
  }

  @override
  Future<List<CrmAuditEntry>> findByTargetEntityId(
      String targetEntityId) async {
    return List.unmodifiable(
      _entries.where((e) => e.targetEntityId == targetEntityId),
    );
  }

  @override
  Future<List<CrmAuditEntry>> findByActorId(String actorId) async {
    return List.unmodifiable(
      _entries.where((e) => e.actorId == actorId),
    );
  }
}
