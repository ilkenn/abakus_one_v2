import 'dart:async';

import '../../orders/domain/models/order_id.dart';
import '../domain/kds/kitchen_work_item.dart';

/// Append-only storage for [KitchenWorkItem] revisions — the *projection*
/// state materialized from the branch's [KitchenEvent] log (event-
/// sourcing terminology: `KitchenEventRepository` holds the source-of-
/// truth log, this holds the current derived state per item). Keyed by
/// [KitchenWorkItem.id], mirrors `CashSessionRepository`'s shape.
abstract interface class KitchenProjectionRepository {
  Future<void> save(KitchenWorkItem item);

  /// Creates a brand-new work item (`revision == 1`, `status == queued`)
  /// — what [EnqueueKitchenWorkItems] calls, distinct from [save]'s use for
  /// persisting a transition. AP-5 Sprint 1: the Firestore-backed
  /// implementation's [save] is a documented no-op (every transition goes
  /// through the real `transitionKitchenWorkItem` callable instead), so
  /// the one legitimate client write — materializing the initial item —
  /// needs its own interface method rather than overloading [save]'s
  /// meaning.
  Future<void> createInitial(KitchenWorkItem item);

  /// The latest revision for [workItemId], or `null` if unknown.
  Future<KitchenWorkItem?> findById(String workItemId);

  /// The work item whose `idempotencyKey` matches, if any — what
  /// `EnqueueKitchenWorkItems` checks before creating a new item, so a
  /// duplicate delta/re-fire never creates duplicate kitchen work.
  Future<KitchenWorkItem?> findByIdempotencyKey(String idempotencyKey);

  /// Every work item currently active (any station) for [orderId] —
  /// what `KitchenOrderView.build` reads to derive order-level readiness.
  Future<List<KitchenWorkItem>> findByOrderId(OrderId orderId);

  /// A live view of [findByOrderId] for [orderId] — re-emits whenever the
  /// order's kitchen work items change. Every implementation must emit the
  /// current snapshot immediately on subscription, matching
  /// `KitchenTicketRepository.watchActiveByBranch`'s own contract.
  Stream<List<KitchenWorkItem>> watchByOrderId(OrderId orderId);

  /// Every work item for [branchId], optionally filtered to [stationName]
  /// (`KitchenStation.name`, `null` = every station) — what a KDS screen's
  /// board query reads.
  Future<List<KitchenWorkItem>> findByBranch({
    required String branchId,
    String? stationName,
  });
}

/// In-memory [KitchenProjectionRepository] — the only implementation this
/// phase.
class InMemoryKitchenProjectionRepository
    implements KitchenProjectionRepository {
  final Map<String, List<KitchenWorkItem>> _historyById = {};
  final _orderControllers =
      <String, StreamController<List<KitchenWorkItem>>>{};

  @override
  Future<void> save(KitchenWorkItem item) async {
    _historyById.putIfAbsent(item.id, () => []).add(item);
    await _emitOrder(item.orderId);
  }

  @override
  Future<void> createInitial(KitchenWorkItem item) => save(item);

  @override
  Future<KitchenWorkItem?> findById(String workItemId) async {
    final history = _historyById[workItemId];
    if (history == null || history.isEmpty) return null;
    return history.last;
  }

  @override
  Future<KitchenWorkItem?> findByIdempotencyKey(String idempotencyKey) async {
    for (final history in _historyById.values) {
      if (history.isNotEmpty && history.last.idempotencyKey == idempotencyKey) {
        return history.last;
      }
    }
    return null;
  }

  @override
  Future<List<KitchenWorkItem>> findByOrderId(OrderId orderId) async {
    final result = <KitchenWorkItem>[];
    for (final history in _historyById.values) {
      if (history.isNotEmpty && history.last.orderId == orderId) {
        result.add(history.last);
      }
    }
    result.sort((a, b) => a.queuedAt.compareTo(b.queuedAt));
    return List.unmodifiable(result);
  }

  @override
  Stream<List<KitchenWorkItem>> watchByOrderId(OrderId orderId) {
    final controller = _orderControllers.putIfAbsent(
      orderId.value,
      () => StreamController<List<KitchenWorkItem>>.broadcast(),
    );
    scheduleMicrotask(() async {
      if (controller.hasListener) {
        controller.add(await findByOrderId(orderId));
      }
    });
    return controller.stream;
  }

  Future<void> _emitOrder(OrderId orderId) async {
    final controller = _orderControllers[orderId.value];
    if (controller == null || !controller.hasListener) return;
    controller.add(await findByOrderId(orderId));
  }

  @override
  Future<List<KitchenWorkItem>> findByBranch({
    required String branchId,
    String? stationName,
  }) async {
    final result = <KitchenWorkItem>[];
    for (final history in _historyById.values) {
      if (history.isEmpty) continue;
      final latest = history.last;
      if (latest.branchId != branchId) continue;
      if (stationName != null && latest.station.name != stationName) {
        continue;
      }
      result.add(latest);
    }
    result.sort((a, b) => a.queuedAt.compareTo(b.queuedAt));
    return List.unmodifiable(result);
  }
}
