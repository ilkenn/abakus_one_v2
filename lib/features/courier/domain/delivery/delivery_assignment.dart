import 'delivery_assignment_status.dart';

/// One courier's offer/acceptance record for a [Delivery] — append-only
/// via [revision]. **One delivery cannot have two active accepted
/// couriers**: enforced by `RespondToDeliveryAssignment`/
/// `ManuallyAssignDelivery` checking `Delivery.currentAssignmentId`, not
/// by this class itself. Reassignment always creates a **new**
/// `DeliveryAssignment` record rather than mutating this one — full
/// assignment history is preserved across reassignments.
class DeliveryAssignment {
  const DeliveryAssignment({
    required this.id,
    required this.deliveryId,
    required this.courierId,
    required this.status,
    required this.offeredAt,
    this.respondedAt,
    this.rejectionReasonCode,
    this.isManualOverride = false,
    this.overrideReason,
    this.overriddenByStaffId,
    required this.revision,
  });

  final String id;
  final String deliveryId;
  final String courierId;
  final DeliveryAssignmentStatus status;
  final DateTime offeredAt;
  final DateTime? respondedAt;

  /// A predefined `CourierFeedbackTag`-style reason code — never free-text
  /// (per "courier rejection requires a predefined reason tag").
  final String? rejectionReasonCode;

  /// `true` for `ManuallyAssignDelivery` — bypasses dispatch scoring;
  /// requires [overrideReason]/[overriddenByStaffId] (actor + reason are
  /// mandatory for any manual override, per the explicit rule).
  final bool isManualOverride;
  final String? overrideReason;
  final String? overriddenByStaffId;

  final int revision;

  DeliveryAssignment copyWith({
    DeliveryAssignmentStatus? status,
    DateTime? respondedAt,
    String? rejectionReasonCode,
    required int revision,
  }) {
    return DeliveryAssignment(
      id: id,
      deliveryId: deliveryId,
      courierId: courierId,
      status: status ?? this.status,
      offeredAt: offeredAt,
      respondedAt: respondedAt ?? this.respondedAt,
      rejectionReasonCode: rejectionReasonCode ?? this.rejectionReasonCode,
      isManualOverride: isManualOverride,
      overrideReason: overrideReason,
      overriddenByStaffId: overriddenByStaffId,
      revision: revision,
    );
  }
}
