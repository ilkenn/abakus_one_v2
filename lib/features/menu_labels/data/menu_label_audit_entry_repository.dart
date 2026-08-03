import '../domain/menu_label_audit_entry.dart';

abstract interface class MenuLabelAuditEntryRepository {
  Future<void> appendEvent(MenuLabelAuditEntry entry);
  Future<List<MenuLabelAuditEntry>> findByTargetEntityId(String targetEntityId);
  Future<List<MenuLabelAuditEntry>> findByOrganizationId(String organizationId);
}

class InMemoryMenuLabelAuditEntryRepository
    implements MenuLabelAuditEntryRepository {
  final List<MenuLabelAuditEntry> _entries = [];

  @override
  Future<void> appendEvent(MenuLabelAuditEntry entry) async {
    _entries.add(entry);
  }

  @override
  Future<List<MenuLabelAuditEntry>> findByTargetEntityId(
      String targetEntityId) async {
    return List.unmodifiable(
      _entries.where((e) => e.targetEntityId == targetEntityId),
    );
  }

  @override
  Future<List<MenuLabelAuditEntry>> findByOrganizationId(
      String organizationId) async {
    return List.unmodifiable(
      _entries.where((e) => e.organizationId == organizationId),
    );
  }
}
