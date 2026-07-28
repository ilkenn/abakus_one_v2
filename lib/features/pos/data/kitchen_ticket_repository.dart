import '../domain/kitchen/kitchen_ticket.dart';
import '../../orders/domain/models/order_id.dart';

/// Append-only storage for [KitchenTicket] revisions, keyed by
/// [KitchenTicket.id].
abstract interface class KitchenTicketRepository {
  Future<void> save(KitchenTicket ticket);

  /// The latest revision for [ticketId], or `null` if unknown.
  Future<KitchenTicket?> findById(String ticketId);

  /// Every ticket ever fired for [orderId] (latest revision of each),
  /// oldest first — the initial ticket plus every delta/cancellation.
  Future<List<KitchenTicket>> findByOrderId(OrderId orderId);

  /// The latest revision of every ticket currently fired for [branchId]
  /// — what the main kitchen screen (KDS) queries.
  Future<List<KitchenTicket>> findActiveByBranch(String branchId);
}

/// In-memory [KitchenTicketRepository] — the only implementation this
/// sprint.
class InMemoryKitchenTicketRepository implements KitchenTicketRepository {
  final Map<String, List<KitchenTicket>> _historyById = {};

  @override
  Future<void> save(KitchenTicket ticket) async {
    _historyById.putIfAbsent(ticket.id, () => []).add(ticket);
  }

  @override
  Future<KitchenTicket?> findById(String ticketId) async {
    final history = _historyById[ticketId];
    if (history == null || history.isEmpty) return null;
    return history.last;
  }

  @override
  Future<List<KitchenTicket>> findByOrderId(OrderId orderId) async {
    final result = <KitchenTicket>[];
    for (final history in _historyById.values) {
      if (history.isNotEmpty && history.last.orderId == orderId) {
        result.add(history.last);
      }
    }
    result.sort((a, b) => a.firedAt.compareTo(b.firedAt));
    return List.unmodifiable(result);
  }

  @override
  Future<List<KitchenTicket>> findActiveByBranch(String branchId) async {
    final result = <KitchenTicket>[];
    for (final history in _historyById.values) {
      if (history.isNotEmpty && history.last.branchId == branchId) {
        result.add(history.last);
      }
    }
    result.sort((a, b) => a.firedAt.compareTo(b.firedAt));
    return List.unmodifiable(result);
  }
}
