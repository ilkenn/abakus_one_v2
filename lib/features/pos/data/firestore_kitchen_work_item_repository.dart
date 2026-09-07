import 'package:cloud_firestore/cloud_firestore.dart' as fs;

import '../../../../core/config/current_organization.dart';
import '../../orders/domain/models/order_id.dart';
import '../domain/kds/kitchen_line_status.dart';
import '../domain/kds/kitchen_station.dart';
import '../domain/kds/kitchen_work_item.dart';
import 'kitchen_projection_repository.dart';

/// AP-5 Sprint 1 — the real, Firestore-backed [KitchenProjectionRepository],
/// mirroring [FirestoreKitchenTicketRepository]'s exact shape and the same
/// reasoning: `kitchenWorkItems` is a real collection now, not a purely
/// client-local simulation.
///
/// **[save] is an intentional, documented no-op — same precedent as
/// [FirestoreKitchenTicketRepository.save].** `firestore.rules` allows a
/// client `create` (matching [EnqueueKitchenWorkItems]'s existing,
/// idempotent, deterministic-by-ticket-line behavior) but denies every
/// `update`/`delete` — every state **transition** goes through the real
/// `transitionKitchenWorkItem` Cloud Function (`KitchenActionGateway`),
/// never through this repository. [EnqueueKitchenWorkItems] calls
/// [createInitial] (part of [KitchenProjectionRepository] itself, AP-5
/// Sprint 1) instead of [save] for exactly this reason.
class FirestoreKitchenWorkItemRepository
    implements KitchenProjectionRepository {
  FirestoreKitchenWorkItemRepository({fs.FirebaseFirestore? firestore})
      : _firestore = firestore ?? fs.FirebaseFirestore.instance;

  final fs.FirebaseFirestore _firestore;

  static const _collection = 'kitchenWorkItems';

  @override
  Future<void> save(KitchenWorkItem item) async {
    // Deliberate no-op — see class doc comment. Only a fresh (`revision
    // == 1`, `status == queued`) item may ever be written by a client at
    // all, and that goes through [createInitial], not this generic
    // interface method every `KitchenProjectionRepository` caller shares.
  }

  /// The one real client write this repository performs — creating the
  /// initial `queued` work item, exactly matching `firestore.rules`'
  /// `kitchenWorkItems` `create` rule (`status == 'queued'`,
  /// `revision == 1`). [EnqueueKitchenWorkItems] calls this instead of
  /// [save] once Firebase is ready.
  @override
  Future<void> createInitial(KitchenWorkItem item) async {
    assert(item.revision == 1 && item.status == KitchenLineStatus.queued);
    await _firestore
        .collection(_collection)
        .doc(item.id)
        .set(_toFirestore(item));
  }

  @override
  Future<KitchenWorkItem?> findById(String workItemId) async {
    final doc = await _firestore.collection(_collection).doc(workItemId).get();
    if (!doc.exists) return null;
    return _fromFirestore(workItemId, doc.data()!);
  }

  @override
  Future<KitchenWorkItem?> findByIdempotencyKey(String idempotencyKey) async {
    final snapshot = await _firestore
        .collection(_collection)
        .where('idempotencyKey', isEqualTo: idempotencyKey)
        .limit(1)
        .get();
    if (snapshot.docs.isEmpty) return null;
    return _fromFirestore(snapshot.docs.first.id, snapshot.docs.first.data());
  }

  @override
  Future<List<KitchenWorkItem>> findByOrderId(OrderId orderId) async {
    final snapshot = await _firestore
        .collection(_collection)
        .where('orderId', isEqualTo: orderId.value)
        .get();
    final items = [
      for (final doc in snapshot.docs) _fromFirestore(doc.id, doc.data()),
    ];
    items.sort((a, b) => a.queuedAt.compareTo(b.queuedAt));
    return List.unmodifiable(items);
  }

  @override
  Future<List<KitchenWorkItem>> findByBranch({
    required String branchId,
    String? stationName,
  }) async {
    fs.Query<Map<String, dynamic>> query = _firestore
        .collection(_collection)
        .where('branchId', isEqualTo: branchId);
    if (stationName != null) {
      query = query.where('station', isEqualTo: stationName);
    }
    final snapshot = await query.get();
    final items = [
      for (final doc in snapshot.docs) _fromFirestore(doc.id, doc.data()),
    ];
    items.sort((a, b) => a.queuedAt.compareTo(b.queuedAt));
    return List.unmodifiable(items);
  }

  Map<String, dynamic> _toFirestore(KitchenWorkItem item) {
    return {
      // AP-5 Sprint 2 fix: this field is required by `firestore.rules`'
      // `kitchenWorkItems` `create` rule (`isOrgMember(request.resource
      // .data.organizationId)`) but was never written in Sprint 1 — every
      // real client create was silently guaranteed to fail (masked by the
      // rules test, which supplied `organizationId` itself as synthetic
      // seed data). `KitchenWorkItem` itself carries no organizationId
      // field (this app is single-tenant today), so the constant is
      // supplied here at the persistence boundary, mirroring
      // `SINGLE_TENANT_ORGANIZATION_ID`'s existing TS-side usage exactly.
      'organizationId': kSingleTenantOrganizationId,
      'branchId': item.branchId,
      'station': item.station.name,
      'orderId': item.orderId.value,
      'kitchenTicketId': item.kitchenTicketId,
      'kitchenTicketLineId': item.kitchenTicketLineId,
      'quantity': item.quantity,
      'readyQuantity': item.readyQuantity,
      'status': item.status.name,
      'queuedAt': fs.Timestamp.fromDate(item.queuedAt),
      'acknowledgedAt': _toTimestamp(item.acknowledgedAt),
      'preparingStartedAt': _toTimestamp(item.preparingStartedAt),
      'readyAt': _toTimestamp(item.readyAt),
      'cancelledAt': _toTimestamp(item.cancelledAt),
      'unavailableAt': _toTimestamp(item.unavailableAt),
      'recalledAt': _toTimestamp(item.recalledAt),
      'wastedAt': _toTimestamp(item.wastedAt),
      'revision': item.revision,
      'idempotencyKey': item.idempotencyKey,
      'sourceEventId': item.sourceEventId,
    };
  }

  KitchenWorkItem _fromFirestore(String id, Map<String, dynamic> data) {
    return KitchenWorkItem(
      id: id,
      branchId: data['branchId'] as String,
      station: KitchenStation.values.byName(data['station'] as String),
      orderId: OrderId(data['orderId'] as String),
      kitchenTicketId: data['kitchenTicketId'] as String,
      kitchenTicketLineId: data['kitchenTicketLineId'] as String,
      quantity: data['quantity'] as int,
      readyQuantity: data['readyQuantity'] as int? ?? 0,
      status: KitchenLineStatus.values.byName(data['status'] as String),
      queuedAt: _fromTimestamp(data['queuedAt'])!,
      acknowledgedAt: _fromTimestamp(data['acknowledgedAt']),
      preparingStartedAt: _fromTimestamp(data['preparingStartedAt']),
      readyAt: _fromTimestamp(data['readyAt']),
      cancelledAt: _fromTimestamp(data['cancelledAt']),
      unavailableAt: _fromTimestamp(data['unavailableAt']),
      recalledAt: _fromTimestamp(data['recalledAt']),
      wastedAt: _fromTimestamp(data['wastedAt']),
      revision: data['revision'] as int,
      idempotencyKey: data['idempotencyKey'] as String,
      sourceEventId: data['sourceEventId'] as String?,
    );
  }

  fs.Timestamp? _toTimestamp(DateTime? value) =>
      value == null ? null : fs.Timestamp.fromDate(value);

  DateTime? _fromTimestamp(Object? value) =>
      value == null ? null : (value as fs.Timestamp).toDate();
}
