import '../../orders/domain/models/order_id.dart';
import '../domain/delivery/delivery.dart';

/// Append-only storage for [Delivery] revisions, keyed by [Delivery.id].
abstract interface class DeliveryRepository {
  Future<void> save(Delivery delivery);
  Future<Delivery?> findById(String deliveryId);
  Future<Delivery?> findByOrderId(OrderId orderId);

  /// Every non-terminal delivery for [branchId] — the dispatch board's
  /// core query.
  Future<List<Delivery>> findActiveByBranchId(String branchId);

  /// Every delivery currently assigned to [courierId] and not yet
  /// terminal — what a courier's "active delivery" screen reads.
  Future<List<Delivery>> findActiveByCourierId(String courierId);
}

class InMemoryDeliveryRepository implements DeliveryRepository {
  final Map<String, List<Delivery>> _historyById = {};

  @override
  Future<void> save(Delivery delivery) async {
    _historyById.putIfAbsent(delivery.id, () => []).add(delivery);
  }

  @override
  Future<Delivery?> findById(String deliveryId) async {
    final history = _historyById[deliveryId];
    if (history == null || history.isEmpty) return null;
    return history.last;
  }

  @override
  Future<Delivery?> findByOrderId(OrderId orderId) async {
    for (final history in _historyById.values) {
      if (history.isNotEmpty && history.last.orderId == orderId) {
        return history.last;
      }
    }
    return null;
  }

  @override
  Future<List<Delivery>> findActiveByBranchId(String branchId) async {
    final result = <Delivery>[];
    for (final history in _historyById.values) {
      if (history.isEmpty) continue;
      final latest = history.last;
      if (latest.branchId == branchId && !latest.isTerminal) {
        result.add(latest);
      }
    }
    result.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return List.unmodifiable(result);
  }

  @override
  Future<List<Delivery>> findActiveByCourierId(String courierId) async {
    final result = <Delivery>[];
    for (final history in _historyById.values) {
      if (history.isEmpty) continue;
      final latest = history.last;
      if (latest.courierId == courierId && !latest.isTerminal) {
        result.add(latest);
      }
    }
    return List.unmodifiable(result);
  }
}
