import '../../../core/errors/business_rule_violation.dart';
import '../domain/events/courier_event.dart';

/// Append-only storage for the branch's [CourierEvent] log — mirrors
/// `KitchenEventRepository`'s shape exactly (sequence assignment,
/// duplicate-key rejection) as a deliberately separate type.
abstract interface class CourierEventRepository {
  Future<CourierEvent> append(CourierEvent event);

  Future<CourierEvent?> findByIdempotencyKey({
    required String branchId,
    required String idempotencyKey,
  });

  Future<List<CourierEvent>> findSince({
    required String branchId,
    required int afterSequence,
  });

  Future<int> latestSequence(String branchId);
}

class InMemoryCourierEventRepository implements CourierEventRepository {
  final Map<String, List<CourierEvent>> _eventsByBranch = {};
  final Map<String, Set<String>> _idempotencyKeysByBranch = {};

  @override
  Future<CourierEvent> append(CourierEvent event) async {
    final keys = _idempotencyKeysByBranch.putIfAbsent(event.branchId, () => {});
    if (keys.contains(event.idempotencyKey)) {
      throw DuplicateCourierEventViolation(
        idempotencyKey: event.idempotencyKey,
      );
    }
    keys.add(event.idempotencyKey);

    final branchEvents = _eventsByBranch.putIfAbsent(event.branchId, () => []);
    final nextSequence =
        branchEvents.isEmpty ? 1 : branchEvents.last.sequence + 1;
    final stored = CourierEvent(
      id: event.id,
      branchId: event.branchId,
      courierId: event.courierId,
      deliveryId: event.deliveryId,
      assignmentId: event.assignmentId,
      shiftId: event.shiftId,
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
  Future<CourierEvent?> findByIdempotencyKey({
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
  Future<List<CourierEvent>> findSince({
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
