import 'courier_event_type.dart';

/// One immutable, append-only fact in the branch's courier-operations
/// event log — mirrors `KitchenEvent`'s shape (Phase 4) as a deliberately
/// separate type (courier domain objects must not couple directly to
/// KDS-specific contracts, per the explicit instruction).
class CourierEvent {
  const CourierEvent({
    required this.id,
    required this.branchId,
    this.courierId,
    this.deliveryId,
    this.assignmentId,
    this.shiftId,
    required this.type,
    required this.idempotencyKey,
    required this.sequence,
    required this.occurredAt,
    this.sourceDeviceId,
    this.payload = const {},
  });

  final String id;
  final String branchId;
  final String? courierId;
  final String? deliveryId;
  final String? assignmentId;
  final String? shiftId;
  final CourierEventType type;

  /// Deterministic per logical action — what `CourierEventRepository
  /// .append` checks to reject a duplicate redelivery/retry.
  final String idempotencyKey;

  /// Monotonically increasing per [branchId], assigned by
  /// `CourierEventRepository.append` — orders replay per delivery even
  /// when events for different deliveries interleave.
  final int sequence;

  final DateTime occurredAt;
  final String? sourceDeviceId;

  /// Small keyed extra data, matching `KitchenEvent.payload`'s same
  /// reasoning (one shared shape, not N event-specific payload types).
  /// Never raw location coordinates or customer contact data — see
  /// `docs/decisions.md` ADR-017's privacy boundary.
  final Map<String, String> payload;
}
