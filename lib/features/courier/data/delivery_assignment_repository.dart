import '../domain/delivery/delivery_assignment.dart';

/// Append-only storage for [DeliveryAssignment] revisions.
abstract interface class DeliveryAssignmentRepository {
  Future<void> save(DeliveryAssignment assignment);
  Future<DeliveryAssignment?> findById(String assignmentId);

  /// Every assignment ever offered for [deliveryId], oldest first — full
  /// reassignment history, preserved across every reassignment.
  Future<List<DeliveryAssignment>> findByDeliveryId(String deliveryId);

  Future<List<DeliveryAssignment>> findByCourierId(String courierId);
}

class InMemoryDeliveryAssignmentRepository
    implements DeliveryAssignmentRepository {
  final Map<String, List<DeliveryAssignment>> _historyById = {};

  @override
  Future<void> save(DeliveryAssignment assignment) async {
    _historyById.putIfAbsent(assignment.id, () => []).add(assignment);
  }

  @override
  Future<DeliveryAssignment?> findById(String assignmentId) async {
    final history = _historyById[assignmentId];
    if (history == null || history.isEmpty) return null;
    return history.last;
  }

  @override
  Future<List<DeliveryAssignment>> findByDeliveryId(String deliveryId) async {
    final result = <DeliveryAssignment>[];
    for (final history in _historyById.values) {
      if (history.isNotEmpty && history.last.deliveryId == deliveryId) {
        result.add(history.last);
      }
    }
    result.sort((a, b) => a.offeredAt.compareTo(b.offeredAt));
    return List.unmodifiable(result);
  }

  @override
  Future<List<DeliveryAssignment>> findByCourierId(String courierId) async {
    final result = <DeliveryAssignment>[];
    for (final history in _historyById.values) {
      if (history.isNotEmpty && history.last.courierId == courierId) {
        result.add(history.last);
      }
    }
    return List.unmodifiable(result);
  }
}
