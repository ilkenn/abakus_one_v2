import '../../data/courier_earnings_adjustment_repository.dart';
import '../../data/courier_earnings_payment_repository.dart';
import '../../data/delivery_earnings_repository.dart';
import '../../data/shift_hourly_earnings_repository.dart';
import '../../domain/compensation/courier_earnings_builder.dart';
import '../../domain/compensation/courier_earnings_summary.dart';

/// Wires [CourierEarningsBuilder] to real repositories for one courier
/// over `[periodStart, periodEnd]` — mirrors
/// `BuildCourierPerformanceSnapshot`'s exact "pure builder + I/O-fetching
/// shell" shape.
class BuildCourierEarningsSummary {
  const BuildCourierEarningsSummary({
    required DeliveryEarningsRepository deliveryEarningsRepository,
    required ShiftHourlyEarningsRepository shiftEarningsRepository,
    required CourierEarningsAdjustmentRepository adjustmentRepository,
    required CourierEarningsPaymentRepository paymentRepository,
  })  : _deliveryEarningsRepository = deliveryEarningsRepository,
        _shiftEarningsRepository = shiftEarningsRepository,
        _adjustmentRepository = adjustmentRepository,
        _paymentRepository = paymentRepository;

  final DeliveryEarningsRepository _deliveryEarningsRepository;
  final ShiftHourlyEarningsRepository _shiftEarningsRepository;
  final CourierEarningsAdjustmentRepository _adjustmentRepository;
  final CourierEarningsPaymentRepository _paymentRepository;

  Future<CourierEarningsSummary> call({
    required String courierId,
    required DateTime periodStart,
    required DateTime periodEnd,
  }) async {
    final deliveryEarnings =
        await _deliveryEarningsRepository.findByCourierIdAndPeriod(
      courierId: courierId,
      periodStart: periodStart,
      periodEnd: periodEnd,
    );
    final shiftEarnings =
        await _shiftEarningsRepository.findByCourierIdAndPeriod(
      courierId: courierId,
      periodStart: periodStart,
      periodEnd: periodEnd,
    );
    final adjustments = await _adjustmentRepository.findByCourierIdAndPeriod(
      courierId: courierId,
      periodStart: periodStart,
      periodEnd: periodEnd,
    );
    final payments = await _paymentRepository.findByCourierIdAndPeriod(
      courierId: courierId,
      periodStart: periodStart,
      periodEnd: periodEnd,
    );

    return CourierEarningsBuilder.build(
      courierId: courierId,
      periodStart: periodStart,
      periodEnd: periodEnd,
      deliveryEarnings: deliveryEarnings,
      shiftEarnings: shiftEarnings,
      adjustments: adjustments,
      payments: payments,
    );
  }
}
