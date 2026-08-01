import '../../../courier/data/courier_operational_audit_entry_repository.dart';
import '../../../pos/data/kitchen_audit_entry_repository.dart';
import '../../../restaurant/data/restaurant_operations_audit_entry_repository.dart';
import '../../data/admin_audit_entry_repository.dart';
import '../../domain/audit/audit_center_entry.dart';

/// Builds a unified, read-only [AuditCenterEntry] projection — Phase 6M
/// (`docs/decisions.md` ADR-023). Merges 4 of this codebase's 8
/// independently-typed audit trails: courier operations, kitchen (KDS),
/// restaurant operations, and admin platform — every one of these
/// already supports a branch-scoped query
/// (`findByBranchId`/equivalent).
///
/// **Deliberately excludes** cash (`CashAuditEntryRepository`, drawer/
/// session-scoped only), closure (`ClosureAuditEntryRepository`, order-
/// scoped only), courier-settlement
/// (`CourierSettlementAuditEntryRepository`, settlement-session-scoped
/// only), and CRM (`CrmAuditEntryRepository`, actor/target-scoped only)
/// — none of these four support a branch-scoped or "get everything"
/// query today, and retrofitting one onto each is separate, larger work
/// each domain owner should do, not a Phase 6 change ("without
/// retrofitting date-range query methods onto all of them"). Those four
/// remain viewable within their own existing screens
/// (`CashReconciliationScreen`, order-closure flows,
/// `ManagerSettlementReviewScreen`) — CRM has no dedicated audit viewer
/// anywhere yet, a real, honestly-reported gap.
///
/// **No server-side date-range/actor/domain filtering exists** — every
/// filter here is applied client-side, after fetching each source's
/// full branch-scoped history. "Future backend query seam": a real
/// backend would push these filters down to the query itself instead.
class BuildAuditCenterProjection {
  const BuildAuditCenterProjection({
    required CourierOperationalAuditEntryRepository courierAuditRepository,
    required KitchenAuditEntryRepository kitchenAuditRepository,
    required RestaurantOperationsAuditEntryRepository
        restaurantOperationsAuditRepository,
    required AdminAuditEntryRepository adminAuditRepository,
  })  : _courierAuditRepository = courierAuditRepository,
        _kitchenAuditRepository = kitchenAuditRepository,
        _restaurantOperationsAuditRepository =
            restaurantOperationsAuditRepository,
        _adminAuditRepository = adminAuditRepository;

  final CourierOperationalAuditEntryRepository _courierAuditRepository;
  final KitchenAuditEntryRepository _kitchenAuditRepository;
  final RestaurantOperationsAuditEntryRepository
      _restaurantOperationsAuditRepository;
  final AdminAuditEntryRepository _adminAuditRepository;

  Future<List<AuditCenterEntry>> call({
    required String branchId,
    String? actorId,
    String? domain,
    DateTime? from,
    DateTime? to,
    int limit = 100,
  }) async {
    final entries = <AuditCenterEntry>[];

    final courierEntries =
        await _courierAuditRepository.findByBranchId(branchId);
    entries.addAll(courierEntries.map((e) => AuditCenterEntry(
          id: e.id,
          domain: 'courier',
          branchId: e.branchId,
          actorId: e.actorStaffId,
          actorRole: e.actorRole,
          description: e.description,
          targetEntityId: e.deliveryId ?? e.courierId ?? e.orderId ?? e.id,
          timestamp: e.timestamp,
        )));

    final kitchenEntries = await _kitchenAuditRepository.findByBranchId(
      branchId,
    );
    entries.addAll(kitchenEntries.map((e) => AuditCenterEntry(
          id: e.id,
          domain: 'kitchen',
          branchId: e.branchId,
          actorId: e.actorStaffId,
          description: e.description,
          targetEntityId: e.orderId,
          timestamp: e.timestamp,
        )));

    final restaurantOpsEntries =
        await _restaurantOperationsAuditRepository.findByBranchId(branchId);
    entries.addAll(restaurantOpsEntries.map((e) => AuditCenterEntry(
          id: e.id,
          domain: 'restaurant-operations',
          branchId: e.branchId,
          actorId: e.actorStaffId,
          description: e.description,
          targetEntityId: e.id,
          timestamp: e.timestamp,
        )));

    final adminEntries = await _adminAuditRepository.findByBranchId(branchId);
    entries.addAll(adminEntries.map((e) => AuditCenterEntry(
          id: e.id,
          domain: 'admin',
          branchId: e.branchId,
          actorId: e.actorId,
          actorRole: e.actorRole,
          description: e.description,
          targetEntityId: e.targetEntityId,
          timestamp: e.timestamp,
        )));

    var filtered = entries.where((e) {
      if (actorId != null && e.actorId != actorId) return false;
      if (domain != null && e.domain != domain) return false;
      if (from != null && e.timestamp.isBefore(from)) return false;
      if (to != null && e.timestamp.isAfter(to)) return false;
      return true;
    }).toList();

    filtered.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    if (filtered.length > limit) {
      filtered = filtered.sublist(0, limit);
    }
    return filtered;
  }
}
