import 'courier_availability_status.dart';

/// A courier's current availability standing — **append-only via
/// [revision]** (availability history must remain auditable per the
/// explicit rule), mirrors `CashSession`'s shape.
///
/// [status] reaching [CourierAvailabilityStatus.available] requires an
/// active, approved [CourierShift] — enforced by `SetCourierAvailability`,
/// not by this class itself (it has no way to see the shift).
class CourierAvailability {
  const CourierAvailability({
    required this.courierId,
    required this.shiftId,
    required this.status,
    this.activeAssignmentCount = 0,
    required this.capacity,
    required this.updatedAt,
    required this.revision,
  });

  final String courierId;
  final String shiftId;
  final CourierAvailabilityStatus status;

  /// How many deliveries this courier currently has accepted/in-progress —
  /// authoritative input to `busy`/capacity checks, never independently
  /// recomputed by re-scanning every `Delivery` on every read.
  final int activeAssignmentCount;

  final int capacity;
  final DateTime updatedAt;
  final int revision;

  bool get hasCapacity => activeAssignmentCount < capacity;

  CourierAvailability copyWith({
    CourierAvailabilityStatus? status,
    int? activeAssignmentCount,
    int? capacity,
    required DateTime updatedAt,
    required int revision,
  }) {
    return CourierAvailability(
      courierId: courierId,
      shiftId: shiftId,
      status: status ?? this.status,
      activeAssignmentCount:
          activeAssignmentCount ?? this.activeAssignmentCount,
      capacity: capacity ?? this.capacity,
      updatedAt: updatedAt,
      revision: revision,
    );
  }
}
