/// Delivered/read/acknowledged progress for one [CourierMessage] —
/// tracked per recipient courier, separately from the message itself, so
/// a broadcast/emergency message sent to five couriers has five
/// independent status trails. Append-only — "Manager sees: Delivered,
/// Read, Acknowledged, Timestamp" is a projection over this log, built by
/// `BuildCourierMessageStatus`.
enum CourierMessageStatusEventType { delivered, read, acknowledged }

class CourierMessageStatusEvent {
  const CourierMessageStatusEvent({
    required this.id,
    required this.messageId,
    required this.courierId,
    required this.type,
    required this.occurredAt,
  });

  final String id;
  final String messageId;
  final String courierId;
  final CourierMessageStatusEventType type;
  final DateTime occurredAt;
}
