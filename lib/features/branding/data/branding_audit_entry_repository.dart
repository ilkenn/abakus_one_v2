import '../domain/audit/branding_audit_entry.dart';

abstract interface class BrandingAuditEntryRepository {
  Future<void> appendEvent(BrandingAuditEntry entry);
  Future<List<BrandingAuditEntry>> findByTargetEntityId(String targetEntityId);
}

class InMemoryBrandingAuditEntryRepository
    implements BrandingAuditEntryRepository {
  final List<BrandingAuditEntry> _entries = [];

  @override
  Future<void> appendEvent(BrandingAuditEntry entry) async {
    _entries.add(entry);
  }

  @override
  Future<List<BrandingAuditEntry>> findByTargetEntityId(
      String targetEntityId) async {
    return List.unmodifiable(
      _entries.where((e) => e.targetEntityId == targetEntityId),
    );
  }
}
