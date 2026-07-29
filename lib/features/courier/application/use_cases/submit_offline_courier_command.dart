import '../../../../core/utils/clock.dart';
import '../../data/pending_courier_command_repository.dart';
import '../../domain/events/pending_courier_command.dart';
import '../identity/pending_courier_command_id_generator.dart';

/// Enqueues one offline-issued courier action for later safe retry —
/// "queued offline commands." **Idempotent by [idempotencyKey]**: a
/// caller retrying the same submission (e.g. after a crash before the
/// server ack was received) gets back the already-queued/already-
/// processed command rather than a duplicate entry.
class SubmitOfflineCourierCommand {
  const SubmitOfflineCourierCommand({
    required Clock clock,
    required PendingCourierCommandIdGenerator idGenerator,
    required PendingCourierCommandRepository repository,
  })  : _clock = clock,
        _idGenerator = idGenerator,
        _repository = repository;

  final Clock _clock;
  final PendingCourierCommandIdGenerator _idGenerator;
  final PendingCourierCommandRepository _repository;

  Future<PendingCourierCommand> call({
    required String deviceId,
    required String courierId,
    required String commandType,
    Map<String, String> payload = const {},
    required String idempotencyKey,
    int? expectedRevision,
  }) async {
    final existing = await _repository.findByIdempotencyKey(idempotencyKey);
    if (existing != null) return existing;

    final command = PendingCourierCommand(
      id: _idGenerator.nextCommandId(),
      deviceId: deviceId,
      courierId: courierId,
      commandType: commandType,
      payload: payload,
      idempotencyKey: idempotencyKey,
      expectedRevision: expectedRevision,
      createdAt: _clock.now(),
    );
    await _repository.save(command);
    return command;
  }
}
