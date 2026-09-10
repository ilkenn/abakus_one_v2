import 'package:cloud_firestore/cloud_firestore.dart' as fs;

import '../../orders/data/order_firestore_mapper.dart';
import '../../orders/domain/models/order.dart';
import '../../orders/domain/models/order_status.dart';

/// AP-6 Sprint 2 — the `DeliveryOrderDispatchScreen`'s own read path: a
/// direct Firestore stream, mirroring `TakeawayOperationsRepository`'s
/// exact shape (`features/takeaway/data/takeaway_operations_repository.dart`)
/// rather than extending the generic `CanonicalOrderRepository` (which stays
/// minimal/shared across many callers, not screen-specific queries).
///
/// Queries `branchId + channel` only (one composite index,
/// `orders(branchId ASC, channel ASC)`) and filters to the three
/// courier-assignable statuses (`ready`/`readyForPickup`/`outForDelivery` —
/// `readyForPickup` added AP-6 Sprint 3 for consortium orders, which skip
/// `ready` entirely since our own kitchen never touches them) client-side
/// from the small per-branch result set — avoids a 3-field composite index
/// for a list that's never large for one branch.
abstract interface class DeliveryDispatchOrderRepository {
  Stream<List<Order>> watchAssignableDeliveryOrders(String branchId);
}

class FirestoreDeliveryDispatchOrderRepository
    implements DeliveryDispatchOrderRepository {
  FirestoreDeliveryDispatchOrderRepository({fs.FirebaseFirestore? firestore})
      : _providedFirestore = firestore;

  final fs.FirebaseFirestore? _providedFirestore;
  fs.FirebaseFirestore get _firestore =>
      _providedFirestore ?? fs.FirebaseFirestore.instance;

  static const _assignableStatuses = {
    OrderStatus.ready,
    OrderStatus.readyForPickup,
    OrderStatus.outForDelivery,
  };

  @override
  Stream<List<Order>> watchAssignableDeliveryOrders(String branchId) {
    return _firestore
        .collection('orders')
        .where('branchId', isEqualTo: branchId)
        .where('channel', isEqualTo: 'delivery')
        .snapshots()
        .map((snap) => [
              for (final doc in snap.docs)
                OrderFirestoreMapper.fromFirestore(doc.data())
            ].where((order) => _assignableStatuses.contains(order.status)).toList());
  }
}
