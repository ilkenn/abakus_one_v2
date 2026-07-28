import '../../../orders/domain/models/order_actor.dart';
import 'closure_audit_event_type.dart';

/// A single, immutable record of a closure/payment-correction event —
/// same shape as `OrderAuditEntry` (id/type/description/actor/timestamp/
/// previousValue/newValue), reusing [OrderActor] directly, but a distinct
/// type since [ClosureAuditEventType] is about `OrderClosure`/
/// `PaymentSession`, not `Order`'s own status history (see
/// [ClosureAuditEventType]'s own doc comment).
///
/// **Append-only**: never mutated once created —
/// `ClosureAuditEntryRepository` offers no update/delete at all, not just
/// by convention.
class ClosureAuditEntry {
  const ClosureAuditEntry({
    required this.id,
    required this.type,
    required this.description,
    required this.actor,
    required this.timestamp,
    this.previousValue,
    this.newValue,
  });

  final String id;
  final ClosureAuditEventType type;
  final String description;
  final OrderActor actor;
  final DateTime timestamp;
  final String? previousValue;
  final String? newValue;
}
