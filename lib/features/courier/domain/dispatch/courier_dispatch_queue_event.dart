/// Whether a courier entered or left the branch's FIFO dispatch queue —
/// Sprint 5C. Append-only event log, mirrors every other courier
/// lifecycle history in this feature (`CourierAvailability`,
/// `CourierLocationAvailability`) — "current queue" is always a
/// projection over this log, never a mutable stored list.
enum CourierDispatchQueueEventType { entered, left }

/// Why a courier left the queue — "on break / GPS unavailable / temporary
/// unavailable / active delivery must temporarily leave the queue."
enum CourierDispatchQueueLeaveReason {
  activeDelivery,
  onBreak,
  locationUnavailable,
  shiftEnded,
  manualRemoval,
}

class CourierDispatchQueueEvent {
  const CourierDispatchQueueEvent({
    required this.id,
    required this.branchId,
    required this.courierId,
    required this.type,
    this.leaveReason,
    required this.occurredAt,
  });

  final String id;
  final String branchId;
  final String courierId;
  final CourierDispatchQueueEventType type;

  /// Non-null only when [type] is [CourierDispatchQueueEventType.left].
  final CourierDispatchQueueLeaveReason? leaveReason;
  final DateTime occurredAt;
}
