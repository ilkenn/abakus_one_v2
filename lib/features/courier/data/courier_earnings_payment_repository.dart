import '../domain/compensation/courier_earnings_payment.dart';

/// Append-only storage for [CourierEarningsPayment] — no update/delete
/// method. [findByReferencedId] is what `MarkCourierEarningsPaid` uses to
/// guard against paying the same underlying earnings/adjustment id twice
/// across two different payments.
abstract interface class CourierEarningsPaymentRepository {
  Future<void> append(CourierEarningsPayment payment);
  Future<CourierEarningsPayment?> findById(String id);

  Future<List<CourierEarningsPayment>> findByCourierIdAndPeriod({
    required String courierId,
    required DateTime periodStart,
    required DateTime periodEnd,
  });

  /// Every payment that already references [earningsOrAdjustmentId] in any
  /// of its `deliveryEarningsIds`/`shiftEarningsIds`/`adjustmentIds` lists.
  Future<List<CourierEarningsPayment>> findByReferencedId(
      String earningsOrAdjustmentId);
}

class InMemoryCourierEarningsPaymentRepository
    implements CourierEarningsPaymentRepository {
  final List<CourierEarningsPayment> _all = [];

  @override
  Future<void> append(CourierEarningsPayment payment) async {
    _all.add(payment);
  }

  @override
  Future<CourierEarningsPayment?> findById(String id) async {
    for (final p in _all) {
      if (p.id == id) return p;
    }
    return null;
  }

  @override
  Future<List<CourierEarningsPayment>> findByCourierIdAndPeriod({
    required String courierId,
    required DateTime periodStart,
    required DateTime periodEnd,
  }) async {
    return List.unmodifiable(_all.where((p) =>
        p.courierId == courierId &&
        !p.paidAt.isBefore(periodStart) &&
        p.paidAt.isBefore(periodEnd)));
  }

  @override
  Future<List<CourierEarningsPayment>> findByReferencedId(
      String earningsOrAdjustmentId) async {
    return List.unmodifiable(_all.where((p) =>
        p.deliveryEarningsIds.contains(earningsOrAdjustmentId) ||
        p.shiftEarningsIds.contains(earningsOrAdjustmentId) ||
        p.adjustmentIds.contains(earningsOrAdjustmentId)));
  }
}
