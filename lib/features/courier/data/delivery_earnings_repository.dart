import '../domain/compensation/delivery_earnings.dart';

/// Append-only storage for [DeliveryEarnings] — no update/delete method;
/// `CalculateDeliveryEarnings` is idempotent by checking
/// [findByDeliveryId] before computing a new one.
abstract interface class DeliveryEarningsRepository {
  Future<void> append(DeliveryEarnings earnings);
  Future<DeliveryEarnings?> findById(String id);
  Future<DeliveryEarnings?> findByDeliveryId(String deliveryId);

  /// Every [DeliveryEarnings] for [courierId] whose [DeliveryEarnings
  /// .calculatedAt] falls within `[periodStart, periodEnd)`.
  Future<List<DeliveryEarnings>> findByCourierIdAndPeriod({
    required String courierId,
    required DateTime periodStart,
    required DateTime periodEnd,
  });
}

class InMemoryDeliveryEarningsRepository implements DeliveryEarningsRepository {
  final List<DeliveryEarnings> _all = [];

  @override
  Future<void> append(DeliveryEarnings earnings) async {
    _all.add(earnings);
  }

  @override
  Future<DeliveryEarnings?> findById(String id) async {
    for (final e in _all) {
      if (e.id == id) return e;
    }
    return null;
  }

  @override
  Future<DeliveryEarnings?> findByDeliveryId(String deliveryId) async {
    for (final e in _all) {
      if (e.deliveryId == deliveryId) return e;
    }
    return null;
  }

  @override
  Future<List<DeliveryEarnings>> findByCourierIdAndPeriod({
    required String courierId,
    required DateTime periodStart,
    required DateTime periodEnd,
  }) async {
    return List.unmodifiable(_all.where((e) =>
        e.courierId == courierId &&
        !e.calculatedAt.isBefore(periodStart) &&
        e.calculatedAt.isBefore(periodEnd)));
  }
}
