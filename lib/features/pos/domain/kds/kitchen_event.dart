import '../../../orders/domain/models/order_id.dart';
import 'kitchen_event_type.dart';

/// One immutable, append-only fact in the branch's kitchen event log — the
/// unit `KitchenEventRepository`/`KitchenSynchronizationService` replay
/// and synchronize from. Distinct from [KitchenAuditEntry]: this is the
/// technical real-time-sync log (includes connectivity events no human
/// audit trail needs); the audit entry is the human-facing operational
/// record, created only for business-meaningful transitions.
class KitchenEvent {
  const KitchenEvent({
    required this.id,
    required this.branchId,
    this.orderId,
    this.kitchenTicketId,
    this.workItemId,
    required this.type,
    required this.idempotencyKey,
    required this.sequence,
    required this.occurredAt,
    this.sourceDeviceId,
    this.payload = const {},
  });

  /// Externally supplied — no id-generation mechanism lives on this class.
  final String id;

  final String branchId;
  final OrderId? orderId;
  final String? kitchenTicketId;
  final String? workItemId;
  final KitchenEventType type;

  /// Deterministic per logical action — what
  /// `KitchenEventRepository.append` checks to reject a duplicate
  /// redelivery/retry rather than logging it twice.
  final String idempotencyKey;

  /// Monotonically increasing per [branchId], assigned by
  /// `KitchenEventRepository.append` — what cursor-based replay
  /// (`KitchenEventCursor.lastProcessedSequence`) orders against, so
  /// per-order processing stays ordered even when events for different
  /// orders interleave.
  final int sequence;

  final DateTime occurredAt;

  /// The device that originated this event, if device-attributable
  /// (`null` for events with no single originating device, e.g. a
  /// server-side delta fire).
  final String? sourceDeviceId;

  /// Small keyed extra data (e.g. `{'reason': '...'}` for a recall) — kept
  /// as `Map<String, String>` rather than typed per event, matching
  /// `OrderAuditEntry`'s existing `previousValue`/`newValue`-as-strings
  /// convention for the same reason (one shared shape, not N event-specific
  /// payload types).
  final Map<String, String> payload;
}
