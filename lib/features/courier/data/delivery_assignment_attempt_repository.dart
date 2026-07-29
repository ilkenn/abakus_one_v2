import '../domain/delivery/delivery_assignment_attempt.dart';

/// Append-only storage for [DeliveryAssignmentAttempt] — the permanent
/// dispatch-attempt log, never pruned or edited.
abstract interface class DeliveryAssignmentAttemptRepository {
  Future<void> append(DeliveryAssignmentAttempt attempt);
  Future<List<DeliveryAssignmentAttempt>> findByDeliveryId(String deliveryId);
}

class InMemoryDeliveryAssignmentAttemptRepository
    implements DeliveryAssignmentAttemptRepository {
  final List<DeliveryAssignmentAttempt> _attempts = [];

  @override
  Future<void> append(DeliveryAssignmentAttempt attempt) async {
    _attempts.add(attempt);
  }

  @override
  Future<List<DeliveryAssignmentAttempt>> findByDeliveryId(
      String deliveryId) async {
    return List.unmodifiable(
      _attempts.where((a) => a.deliveryId == deliveryId),
    );
  }
}
