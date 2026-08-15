import 'dart:async';

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

  /// Faz R.3C — a live view of [findActiveByBranch], re-emitting whenever
  /// the underlying active-ticket set for [branchId] changes, so the KDS
  /// board updates without a manual refresh/app restart. Every
  /// implementation must emit the current snapshot immediately on
  /// subscription (not wait for the first subsequent change).
  Stream<List<KitchenTicket>> watchActiveByBranch(String branchId);
}

/// In-memory [KitchenTicketRepository] — the only implementation this
/// sprint.
class InMemoryKitchenTicketRepository implements KitchenTicketRepository {
  final Map<String, List<KitchenTicket>> _historyById = {};
  final _activeBranchControllers =
      <String, StreamController<List<KitchenTicket>>>{};

  @override
  Future<void> save(KitchenTicket ticket) async {
    _historyById.putIfAbsent(ticket.id, () => []).add(ticket);
    await _emitActive(ticket.branchId);
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

  @override
  Stream<List<KitchenTicket>> watchActiveByBranch(String branchId) {
    final controller = _activeBranchControllers.putIfAbsent(
      branchId,
      () => StreamController<List<KitchenTicket>>.broadcast(
        onListen: null,
      ),
    );
    // Emit the current snapshot for this new subscriber before anything
    // else changes, matching the interface's "current snapshot on
    // subscription" contract.
    scheduleMicrotask(() async {
      if (controller.hasListener) {
        controller.add(await findActiveByBranch(branchId));
      }
    });
    return controller.stream;
  }

  Future<void> _emitActive(String branchId) async {
    final controller = _activeBranchControllers[branchId];
    if (controller == null || !controller.hasListener) return;
    controller.add(await findActiveByBranch(branchId));
  }
}
