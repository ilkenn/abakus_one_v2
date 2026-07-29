import '../domain/events/pending_courier_command.dart';

/// Storage for [PendingCourierCommand]s — the offline command queue.
/// Mutable per-command (status/attempt tracking updates in place; the
/// underlying courier-domain action each command replays is itself always
/// applied through the normal append-only use cases, so no financial/
/// operational history is ever lost by this record being mutable).
abstract interface class PendingCourierCommandRepository {
  Future<void> save(PendingCourierCommand command);
  Future<PendingCourierCommand?> findById(String id);
  Future<PendingCourierCommand?> findByIdempotencyKey(String idempotencyKey);
  Future<List<PendingCourierCommand>> findQueuedByDeviceId(String deviceId);
}

class InMemoryPendingCourierCommandRepository
    implements PendingCourierCommandRepository {
  final Map<String, PendingCourierCommand> _byId = {};

  @override
  Future<void> save(PendingCourierCommand command) async =>
      _byId[command.id] = command;

  @override
  Future<PendingCourierCommand?> findById(String id) async => _byId[id];

  @override
  Future<PendingCourierCommand?> findByIdempotencyKey(
      String idempotencyKey) async {
    for (final command in _byId.values) {
      if (command.idempotencyKey == idempotencyKey) return command;
    }
    return null;
  }

  @override
  Future<List<PendingCourierCommand>> findQueuedByDeviceId(
      String deviceId) async {
    return List.unmodifiable(
      _byId.values.where((c) =>
          c.deviceId == deviceId &&
          c.status == PendingCourierCommandStatus.queued),
    );
  }
}
