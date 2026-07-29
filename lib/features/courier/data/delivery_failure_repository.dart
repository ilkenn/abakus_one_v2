import '../domain/delivery/delivery_failure.dart';

/// Append-only storage for [DeliveryFailure] — no update/delete method.
abstract interface class DeliveryFailureRepository {
  Future<void> append(DeliveryFailure failure);
  Future<List<DeliveryFailure>> findByDeliveryId(String deliveryId);

  /// Every failure ever recorded that traces back to a courier's
  /// deliveries — used for `CourierPerformanceBuilder`.
  Future<List<DeliveryFailure>> findAll();
}

class InMemoryDeliveryFailureRepository implements DeliveryFailureRepository {
  final List<DeliveryFailure> _failures = [];

  @override
  Future<void> append(DeliveryFailure failure) async {
    _failures.add(failure);
  }

  @override
  Future<List<DeliveryFailure>> findByDeliveryId(String deliveryId) async {
    return List.unmodifiable(
      _failures.where((f) => f.deliveryId == deliveryId),
    );
  }

  @override
  Future<List<DeliveryFailure>> findAll() async => List.unmodifiable(_failures);
}
