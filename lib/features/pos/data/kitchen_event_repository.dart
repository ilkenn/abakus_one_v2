import '../../../core/errors/business_rule_violation.dart';
import '../domain/kds/kitchen_event.dart';

/// Append-only storage for the branch's [KitchenEvent] log — the
/// source-of-truth sequence `KitchenSynchronizationService` replays from.
/// No update or delete method exists at all.
///
/// [append] assigns [KitchenEvent.sequence] itself (monotonically
/// increasing per branch, ignoring whatever the caller passed) and throws
/// [DuplicateKitchenEventViolation] if `idempotencyKey` is already
/// recorded for the branch — structural duplicate-event rejection.
abstract interface class KitchenEventRepository {
  Future<KitchenEvent> append(KitchenEvent event);

  Future<KitchenEvent?> findByIdempotencyKey({
    required String branchId,
    required String idempotencyKey,
  });

  /// Every event for [branchId] with `sequence > afterSequence`, in
  /// ascending sequence order — what replay/reconnect synchronization
  /// reads.
  Future<List<KitchenEvent>> findSince({
    required String branchId,
    required int afterSequence,
  });

  /// The highest `sequence` currently recorded for [branchId], or `0` if
  /// none.
  Future<int> latestSequence(String branchId);
}

/// In-memory [KitchenEventRepository] — the only implementation this
/// phase. Sequence assignment and duplicate-key rejection are both
/// enforced structurally here, not left to caller discipline.
class InMemoryKitchenEventRepository implements KitchenEventRepository {
  final Map<String, List<KitchenEvent>> _eventsByBranch = {};
  final Map<String, Set<String>> _idempotencyKeysByBranch = {};

  @override
  Future<KitchenEvent> append(KitchenEvent event) async {
    final keys = _idempotencyKeysByBranch.putIfAbsent(event.branchId, () => {});
    if (keys.contains(event.idempotencyKey)) {
      throw DuplicateKitchenEventViolation(
        idempotencyKey: event.idempotencyKey,
      );
    }
    keys.add(event.idempotencyKey);

    final branchEvents = _eventsByBranch.putIfAbsent(event.branchId, () => []);
    final nextSequence =
        branchEvents.isEmpty ? 1 : branchEvents.last.sequence + 1;
    final stored = KitchenEvent(
      id: event.id,
      branchId: event.branchId,
      orderId: event.orderId,
      kitchenTicketId: event.kitchenTicketId,
      workItemId: event.workItemId,
      type: event.type,
      idempotencyKey: event.idempotencyKey,
      sequence: nextSequence,
      occurredAt: event.occurredAt,
      sourceDeviceId: event.sourceDeviceId,
      payload: event.payload,
    );
    branchEvents.add(stored);
    return stored;
  }

  @override
  Future<KitchenEvent?> findByIdempotencyKey({
    required String branchId,
    required String idempotencyKey,
  }) async {
    final branchEvents = _eventsByBranch[branchId];
    if (branchEvents == null) return null;
    for (final event in branchEvents) {
      if (event.idempotencyKey == idempotencyKey) return event;
    }
    return null;
  }

  @override
  Future<List<KitchenEvent>> findSince({
    required String branchId,
    required int afterSequence,
  }) async {
    final branchEvents = _eventsByBranch[branchId] ?? const [];
    return List.unmodifiable(
      branchEvents.where((e) => e.sequence > afterSequence),
    );
  }

  @override
  Future<int> latestSequence(String branchId) async {
    final branchEvents = _eventsByBranch[branchId];
    if (branchEvents == null || branchEvents.isEmpty) return 0;
    return branchEvents.last.sequence;
  }
}
