import 'package:cloud_firestore/cloud_firestore.dart' as fs;

import '../../orders/data/order_firestore_mapper.dart';
import '../../orders/domain/models/order.dart';
import '../../orders/domain/models/order_id.dart';
import '../domain/kitchen/kitchen_ticket.dart';
import '../domain/kitchen/kitchen_ticket_mapper.dart';
import '../domain/kitchen/kitchen_ticket_type.dart';
import 'kitchen_ticket_repository.dart';

/// Faz R.3C — the real, production KDS repository. The canonical source of
/// truth for "what's on the kitchen board" is the `orders` collection
/// itself, never a separately-persisted ticket document: a [KitchenTicket]
/// is derived, read-only, from whichever [Order] documents are currently
/// in a kitchen-eligible [_kitchenEligibleStatuses] status for a branch.
/// This means the reservation-preorder release sweep
/// (`reservationPreorderKdsRelease` / `reservationSweep`, which flips an
/// Order from `pendingConfirmation` to `confirmed` directly in Firestore)
/// requires **no reservation-specific KDS code at all** — the very next
/// `orders` snapshot this repository is watching already reflects the new
/// status, the same generic pipeline every other channel already goes
/// through.
///
/// **Why not [FireKitchenTicket]/a persisted `kitchenTickets` collection**:
/// confirmed unused in any real app code path (only its own unit test
/// calls it) — building the production KDS path on top of a parallel,
/// never-actually-written collection would leave the real path just as
/// disconnected as the mock repository it replaces. Deriving tickets live
/// from `orders` means there is exactly one place an order's kitchen
/// state can drift out of sync with its own canonical status: nowhere.
///
/// **[save] is an intentional, documented no-op.** Nothing should ever
/// call it against this implementation in production — `orders` is
/// written exclusively through the existing order-lifecycle callables/
/// repositories, never through this class. It exists only to satisfy the
/// [KitchenTicketRepository] interface without special-casing every
/// existing caller (`FireKitchenTicket`, already dead in production code,
/// remains free to keep calling `save` against
/// [InMemoryKitchenTicketRepository] in tests/dev).
///
/// **Ticket identity**: deterministically `'kt-${order.id.value}'` — never
/// a fresh/random id per snapshot — so any future per-ticket work-item
/// tracking correlates a live-derived ticket across successive Firestore
/// snapshots of the same order, exactly like a real fired ticket would.
///
/// **`restaurantName`/`branchName`**: this repository has no restaurant/
/// branch lookup dependency (deliberately, to avoid an additional async
/// join on every snapshot) — both header fields are filled with
/// [Order.branchId]-derived placeholder strings. [KitchenTicketHeader]
/// requires non-null strings; the KDS board today
/// (`KitchenDisplayBoardScreen`) does not render either field, so this is
/// a disclosed, currently-inert limitation, not a hidden one.
///
/// **Authorization boundary — audited Faz R.3C.1, hardened Faz R.3C.2.**
/// The `branchId` filter in [_query] is, and remains, a **query scope, not
/// an authorization boundary** — it decides which orders this particular
/// screen instance asks for, not which orders a given staff member is
/// *allowed* to read. That real boundary is entirely `firestore.rules`'s
/// `orders` `read` rule, never this class.
///
/// **Faz R.3C.1 found organization membership alone (`isOrgMember`) was
/// the only check** — any staff member in an organization could read
/// every branch's orders, including branches they had no operational
/// reason to see. Confirmed at the time to be this codebase's existing,
/// pre-existing policy (`StaffMembership.branchAccess` tracked as data but
/// never propagated into custom claims), not a gap introduced by KDS —
/// but judged, on its own explicit audit, unacceptable for the intended
/// multi-branch SaaS architecture regardless of precedent.
///
/// **Faz R.3C.2 closes it for real.** `firestore.rules`'s `orders` `read`
/// rule now also requires `hasBranchAccess(organizationId, branchId)` —
/// `branchAccess` is a new custom claim (`Record<organizationId,
/// branchId[]>`, mirrors `roles`'s exact shape), synced from the same
/// `memberships.branchAccess` field `grantStaffBranchAccess`/
/// `revokeStaffBranchAccess` already wrote (`functions/src/staffMembership
/// .ts`'s `resyncClaimsForUid`) — no second authorization store, no
/// invented role-based bypass (this membership model has no wildcard/
/// "all branches" semantics for any role, including admin/tenantOwner). A
/// staff member's Firestore-authorized read set now genuinely matches
/// their canonical branch grants, not just their organization membership.
/// See `firestore-tests/rules.test.js`'s "KDS/Orders branch authorization"
/// tests for the proof.
class FirestoreKitchenTicketRepository implements KitchenTicketRepository {
  FirestoreKitchenTicketRepository({fs.FirebaseFirestore? firestore})
      : _firestore = firestore ?? fs.FirebaseFirestore.instance;

  final fs.FirebaseFirestore _firestore;

  /// Kitchen-relevant window of the canonical Order state machine
  /// (`order_status.dart`): after `pendingConfirmation` (not yet
  /// kitchen-ready — a reservation preorder waiting for its release
  /// boundary must stay invisible here) and before `served`/`completed`/
  /// `cancelled`/`rejected`/`refunded` (past kitchen or terminal).
  static const _kitchenEligibleStatuses = ['confirmed', 'preparing', 'ready'];

  @override
  Future<void> save(KitchenTicket ticket) async {
    // Deliberate no-op — see class doc comment.
  }

  @override
  Future<KitchenTicket?> findById(String ticketId) async {
    if (!ticketId.startsWith('kt-')) return null;
    final orderId = ticketId.substring('kt-'.length);
    final doc = await _firestore.collection('orders').doc(orderId).get();
    if (!doc.exists) return null;
    final order = OrderFirestoreMapper.fromFirestore(doc.data()!);
    if (!_kitchenEligibleStatuses.contains(order.status.name)) return null;
    return _toTicket(order);
  }

  @override
  Future<List<KitchenTicket>> findByOrderId(OrderId orderId) async {
    final doc = await _firestore.collection('orders').doc(orderId.value).get();
    if (!doc.exists) return const [];
    final order = OrderFirestoreMapper.fromFirestore(doc.data()!);
    return [_toTicket(order)];
  }

  @override
  Future<List<KitchenTicket>> findActiveByBranch(String branchId) async {
    final snapshot = await _query(branchId).get();
    return _mapSnapshot(snapshot);
  }

  @override
  Stream<List<KitchenTicket>> watchActiveByBranch(String branchId) {
    return _query(branchId).snapshots().map(_mapSnapshot);
  }

  fs.Query<Map<String, dynamic>> _query(String branchId) {
    return _firestore
        .collection('orders')
        .where('branchId', isEqualTo: branchId)
        .where('status', whereIn: _kitchenEligibleStatuses);
  }

  List<KitchenTicket> _mapSnapshot(
      fs.QuerySnapshot<Map<String, dynamic>> snapshot) {
    final tickets = [
      for (final doc in snapshot.docs)
        _toTicket(OrderFirestoreMapper.fromFirestore(doc.data())),
    ];
    tickets.sort((a, b) => a.firedAt.compareTo(b.firedAt));
    return List.unmodifiable(tickets);
  }

  KitchenTicket _toTicket(Order order) {
    final firedAt = order.timestamps.confirmed ?? order.timestamps.created;
    return KitchenTicketMapper.fromOrder(
      ticketId: 'kt-${order.id.value}',
      order: order,
      type: KitchenTicketType.initial,
      restaurantName: order.restaurantId,
      branchName: order.branchId,
      firedAt: firedAt,
    );
  }
}
