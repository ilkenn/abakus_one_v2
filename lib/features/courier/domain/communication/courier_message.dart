import 'courier_message_type.dart';

/// One manager↔courier message — Sprint 5C Part 8. Immutable, append-only
/// (a message's own content never changes once sent — its delivered/read/
/// acknowledged progress is tracked separately by
/// `CourierMessageStatusEvent`, exactly the same "stable entity + separate
/// event log" split this sprint already used for
/// `CourierDispatchQueueEvent`/`GeofenceTransitionEvent`).
///
/// **Honest real-time boundary**: delivery within this app is real,
/// working same-process/reconnect-sync propagation (`CourierEventBus`,
/// exactly like every other courier-facing real-time update since Phase
/// 4/5 — see `docs/decisions.md` ADR-017's documented same-process
/// boundary) — never a claim of genuine cross-device push, since no
/// backend exists to provide one.
class CourierMessage {
  const CourierMessage({
    required this.id,
    required this.branchId,
    required this.senderStaffId,
    this.recipientCourierId,
    required this.type,
    required this.body,
    required this.sentAt,
  });

  final String id;
  final String branchId;

  /// The manager's (or courier's, for a courier-initiated chat reply)
  /// staff id.
  final String senderStaffId;

  /// `null` for [CourierMessageType.broadcast]/[CourierMessageType
  /// .emergency] sent to every courier on shift — non-null for a
  /// [CourierMessageType.direct] chat message to one specific courier.
  final String? recipientCourierId;

  final CourierMessageType type;
  final String body;
  final DateTime sentAt;
}
