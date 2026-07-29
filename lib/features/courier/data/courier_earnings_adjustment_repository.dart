import '../domain/compensation/courier_earnings_adjustment.dart';

/// Append-only storage for [CourierEarningsAdjustment] — no update/delete
/// method; a correction to an already-recorded adjustment is itself a new
/// adjustment, never a mutation.
abstract interface class CourierEarningsAdjustmentRepository {
  Future<void> append(CourierEarningsAdjustment adjustment);
  Future<CourierEarningsAdjustment?> findById(String id);

  Future<List<CourierEarningsAdjustment>> findByCourierIdAndPeriod({
    required String courierId,
    required DateTime periodStart,
    required DateTime periodEnd,
  });
}

class InMemoryCourierEarningsAdjustmentRepository
    implements CourierEarningsAdjustmentRepository {
  final List<CourierEarningsAdjustment> _all = [];

  @override
  Future<void> append(CourierEarningsAdjustment adjustment) async {
    _all.add(adjustment);
  }

  @override
  Future<CourierEarningsAdjustment?> findById(String id) async {
    for (final a in _all) {
      if (a.id == id) return a;
    }
    return null;
  }

  @override
  Future<List<CourierEarningsAdjustment>> findByCourierIdAndPeriod({
    required String courierId,
    required DateTime periodStart,
    required DateTime periodEnd,
  }) async {
    return List.unmodifiable(_all.where((a) =>
        a.courierId == courierId &&
        !a.createdAt.isBefore(periodStart) &&
        a.createdAt.isBefore(periodEnd)));
  }
}
