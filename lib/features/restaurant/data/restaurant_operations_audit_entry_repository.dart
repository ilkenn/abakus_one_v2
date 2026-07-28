import '../domain/audit/restaurant_operations_audit_entry.dart';

/// Append-only storage for [RestaurantOperationsAuditEntry] events, keyed
/// by the branch they concern.
///
/// **No update or delete method exists at all** — mirrors
/// `ClosureAuditEntryRepository`'s structurally-append-only interface
/// shape exactly.
abstract interface class RestaurantOperationsAuditEntryRepository {
  Future<void> appendEvent(RestaurantOperationsAuditEntry entry);

  /// Every event ever appended for [branchId], oldest first.
  Future<List<RestaurantOperationsAuditEntry>> findByBranchId(String branchId);
}

/// In-memory [RestaurantOperationsAuditEntryRepository] — the only
/// implementation this sprint.
class InMemoryRestaurantOperationsAuditEntryRepository
    implements RestaurantOperationsAuditEntryRepository {
  final Map<String, List<RestaurantOperationsAuditEntry>> _eventsByBranchId =
      {};

  @override
  Future<void> appendEvent(RestaurantOperationsAuditEntry entry) async {
    _eventsByBranchId.putIfAbsent(entry.branchId, () => []).add(entry);
  }

  @override
  Future<List<RestaurantOperationsAuditEntry>> findByBranchId(
      String branchId) async {
    return List.unmodifiable(_eventsByBranchId[branchId] ?? const []);
  }
}
