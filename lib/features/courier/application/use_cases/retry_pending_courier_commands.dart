import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../data/pending_courier_command_repository.dart';
import '../../domain/events/pending_courier_command.dart';

/// Attempts to apply every still-[PendingCourierCommandStatus.queued]
/// command for [deviceId] — "safe command retry, conflict detection,"
/// "reconnect sync."
///
/// [applyCommand] is an injected closure that replays one command through
/// whichever real use case its `commandType` names (the mapping from
/// `commandType` string to use case call is an application/UI-layer
/// concern, deliberately kept out of this generic retry loop). A
/// [StaleCourierRevisionViolation] thrown by [applyCommand] is treated as
/// [PendingCourierCommandStatus.conflict] (the caller's queued view is out
/// of date — never silently retried into a wrong write); any other
/// [BusinessRuleViolation] is [PendingCourierCommandStatus.failed].
/// Anything else propagates uncaught — a genuine infrastructure error, not
/// an expected outcome for this loop to swallow.
class RetryPendingCourierCommands {
  const RetryPendingCourierCommands({
    required Clock clock,
    required PendingCourierCommandRepository repository,
  })  : _clock = clock,
        _repository = repository;

  final Clock _clock;
  final PendingCourierCommandRepository _repository;

  Future<List<PendingCourierCommand>> call({
    required String deviceId,
    required Future<void> Function(PendingCourierCommand command) applyCommand,
  }) async {
    final queued = await _repository.findQueuedByDeviceId(deviceId);
    final results = <PendingCourierCommand>[];

    for (final command in queued) {
      final now = _clock.now();
      PendingCourierCommand outcome;
      try {
        await applyCommand(command);
        outcome = command.copyWith(
          status: PendingCourierCommandStatus.applied,
          attemptCount: command.attemptCount + 1,
          lastAttemptAt: now,
        );
      } on StaleCourierRevisionViolation catch (e) {
        outcome = command.copyWith(
          status: PendingCourierCommandStatus.conflict,
          attemptCount: command.attemptCount + 1,
          lastAttemptAt: now,
          failureReason: e.description,
        );
      } on BusinessRuleViolation catch (e) {
        outcome = command.copyWith(
          status: PendingCourierCommandStatus.failed,
          attemptCount: command.attemptCount + 1,
          lastAttemptAt: now,
          failureReason: e.description,
        );
      }
      await _repository.save(outcome);
      results.add(outcome);
    }

    return results;
  }
}
