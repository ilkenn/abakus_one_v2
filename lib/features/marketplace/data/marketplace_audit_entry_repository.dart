import '../domain/audit/marketplace_audit_entry.dart';

abstract interface class MarketplaceAuditEntryRepository {
  Future<void> appendEvent(MarketplaceAuditEntry entry);
  Future<List<MarketplaceAuditEntry>> findByTargetEntityId(
      String targetEntityId);
  Future<List<MarketplaceAuditEntry>> findByOrganizationId(
      String organizationId);
}

class InMemoryMarketplaceAuditEntryRepository
    implements MarketplaceAuditEntryRepository {
  final List<MarketplaceAuditEntry> _entries = [];

  @override
  Future<void> appendEvent(MarketplaceAuditEntry entry) async {
    _entries.add(entry);
  }

  @override
  Future<List<MarketplaceAuditEntry>> findByTargetEntityId(
      String targetEntityId) async {
    return List.unmodifiable(
      _entries.where((e) => e.targetEntityId == targetEntityId),
    );
  }

  @override
  Future<List<MarketplaceAuditEntry>> findByOrganizationId(
      String organizationId) async {
    return List.unmodifiable(
      _entries.where((e) => e.organizationId == organizationId),
    );
  }
}
