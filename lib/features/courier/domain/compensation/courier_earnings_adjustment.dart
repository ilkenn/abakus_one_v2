import '../../../../shared/models/money.dart';
import 'courier_earnings_adjustment_reason.dart';

/// One immutable, append-only manager correction against a courier's
/// earnings — **never a mutation of an original [DeliveryEarnings]/
/// [ShiftHourlyEarnings] record** (neither type has an update method at
/// all). [amount] may be positive (a top-up) or negative (a deduction).
/// "Locked" (already-paid) earnings are corrected the exact same way —
/// through a new adjustment referencing the same courier — never by
/// reopening a [CourierEarningsPayment].
class CourierEarningsAdjustment {
  const CourierEarningsAdjustment({
    required this.id,
    required this.courierId,
    this.relatedShiftId,
    this.relatedDeliveryId,
    required this.reason,
    required this.amount,
    this.notes = '',
    required this.actorStaffId,
    required this.createdAt,
  });

  final String id;
  final String courierId;
  final String? relatedShiftId;
  final String? relatedDeliveryId;
  final CourierEarningsAdjustmentReason reason;
  final Money amount;
  final String notes;
  final String actorStaffId;
  final DateTime createdAt;
}
