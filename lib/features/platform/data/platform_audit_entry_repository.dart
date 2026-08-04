import '../domain/audit/platform_audit_entry.dart';

abstract interface class PlatformAuditEntryRepository {
  Future<void> appendEvent(PlatformAuditEntry entry);
  Future<List<PlatformAuditEntry>> findByTargetEntityId(String targetEntityId);
}

class InMemoryPlatformAuditEntryRepository
    implements PlatformAuditEntryRepository {
  final List<PlatformAuditEntry> _entries = [];

  @override
  Future<void> appendEvent(PlatformAuditEntry entry) async {
    _entries.add(entry);
  }

  @override
  Future<List<PlatformAuditEntry>> findByTargetEntityId(
      String targetEntityId) async {
    return List.unmodifiable(
      _entries.where((e) => e.targetEntityId == targetEntityId),
    );
  }
}
