import '../domain/kds/kitchen_audit_entry.dart';

/// Append-only storage for [KitchenAuditEntry] — no update or delete
/// method exists at all, matching every other audit repository in this
/// codebase.
abstract interface class KitchenAuditEntryRepository {
  Future<void> appendEvent(KitchenAuditEntry entry);

  /// Every audit entry for [orderId], oldest first.
  Future<List<KitchenAuditEntry>> findByOrderId(String orderId);

  /// Every audit entry for [branchId], oldest first — branch-scoped so
  /// branch data never leaks across tenants/branches.
  Future<List<KitchenAuditEntry>> findByBranchId(String branchId);
}

/// In-memory [KitchenAuditEntryRepository] — the only implementation this
/// phase.
class InMemoryKitchenAuditEntryRepository
    implements KitchenAuditEntryRepository {
  final List<KitchenAuditEntry> _entries = [];

  @override
  Future<void> appendEvent(KitchenAuditEntry entry) async {
    _entries.add(entry);
  }

  @override
  Future<List<KitchenAuditEntry>> findByOrderId(String orderId) async {
    return List.unmodifiable(
      _entries.where((e) => e.orderId == orderId),
    );
  }

  @override
  Future<List<KitchenAuditEntry>> findByBranchId(String branchId) async {
    return List.unmodifiable(
      _entries.where((e) => e.branchId == branchId),
    );
  }
}
