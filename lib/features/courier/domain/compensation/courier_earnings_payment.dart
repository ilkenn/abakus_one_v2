import '../../../../shared/models/money.dart';

/// One immutable record marking a specific set of [DeliveryEarnings]/
/// [ShiftHourlyEarnings]/[CourierEarningsAdjustment] ids as paid —
/// "locked earnings become immutable." Locking is structural: neither
/// referenced record type has an update method to begin with, so once an
/// id appears in a [CourierEarningsPayment] the only way to correct it is
/// a brand-new [CourierEarningsAdjustment] — never a mutation of this
/// record or the ones it references. `MarkCourierEarningsPaid` guards
/// against paying the same id twice across two [CourierEarningsPayment]s.
class CourierEarningsPayment {
  const CourierEarningsPayment({
    required this.id,
    required this.courierId,
    required this.periodStart,
    required this.periodEnd,
    required this.totalAmount,
    required this.deliveryEarningsIds,
    required this.shiftEarningsIds,
    required this.adjustmentIds,
    required this.paidByStaffId,
    required this.paidAt,
  });

  final String id;
  final String courierId;
  final DateTime periodStart;
  final DateTime periodEnd;
  final Money totalAmount;
  final List<String> deliveryEarningsIds;
  final List<String> shiftEarningsIds;
  final List<String> adjustmentIds;
  final String paidByStaffId;
  final DateTime paidAt;
}
