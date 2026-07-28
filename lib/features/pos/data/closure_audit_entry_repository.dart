import '../../orders/domain/models/order_id.dart';
import '../domain/audit/closure_audit_entry.dart';

/// Append-only storage for [ClosureAuditEntry] events, keyed by the
/// order they concern.
///
/// **No update or delete method exists at all** — not just an unused
/// capability, the interface itself cannot express mutating a past audit
/// event, structurally enforcing the append-only requirement rather than
/// relying on convention (`docs/decisions.md` ADR-012).
abstract interface class ClosureAuditEntryRepository {
  Future<void> appendEvent(OrderId orderId, ClosureAuditEntry entry);

  /// Every event ever appended for [orderId], oldest first.
  Future<List<ClosureAuditEntry>> findByOrderId(OrderId orderId);
}

/// In-memory [ClosureAuditEntryRepository] — the only implementation this
/// sprint.
class InMemoryClosureAuditEntryRepository implements ClosureAuditEntryRepository {
  final Map<String, List<ClosureAuditEntry>> _eventsByOrderId = {};

  @override
  Future<void> appendEvent(OrderId orderId, ClosureAuditEntry entry) async {
    _eventsByOrderId.putIfAbsent(orderId.value, () => []).add(entry);
  }

  @override
  Future<List<ClosureAuditEntry>> findByOrderId(OrderId orderId) async {
    return List.unmodifiable(_eventsByOrderId[orderId.value] ?? const []);
  }
}
