/// Outcome of attempting to apply a queued offline command.
enum PendingCourierCommandStatus { queued, applied, failed, conflict }

/// One offline-queued courier action awaiting safe retry — "queued
/// offline commands, safe command retry, conflict detection." A command
/// is identified by [idempotencyKey] so retrying it never double-applies;
/// [expectedRevision] (when the command targets a revisioned record) is
/// what turns a retry that would now be based on stale data into an
/// explicit [PendingCourierCommandStatus.conflict] rather than a silent
/// wrong write.
class PendingCourierCommand {
  const PendingCourierCommand({
    required this.id,
    required this.deviceId,
    required this.courierId,
    required this.commandType,
    this.payload = const {},
    required this.idempotencyKey,
    this.expectedRevision,
    required this.createdAt,
    this.status = PendingCourierCommandStatus.queued,
    this.attemptCount = 0,
    this.lastAttemptAt,
    this.failureReason,
  });

  final String id;
  final String deviceId;
  final String courierId;

  /// Free-text label naming which use case this command replays (e.g.
  /// `'RespondToDeliveryAssignment'`) — not a closed enum, since the set
  /// of retryable actions is an application-layer concern, not a domain
  /// one.
  final String commandType;

  final Map<String, String> payload;
  final String idempotencyKey;
  final int? expectedRevision;
  final DateTime createdAt;
  final PendingCourierCommandStatus status;
  final int attemptCount;
  final DateTime? lastAttemptAt;
  final String? failureReason;

  PendingCourierCommand copyWith({
    PendingCourierCommandStatus? status,
    int? attemptCount,
    DateTime? lastAttemptAt,
    String? failureReason,
  }) {
    return PendingCourierCommand(
      id: id,
      deviceId: deviceId,
      courierId: courierId,
      commandType: commandType,
      payload: payload,
      idempotencyKey: idempotencyKey,
      expectedRevision: expectedRevision,
      createdAt: createdAt,
      status: status ?? this.status,
      attemptCount: attemptCount ?? this.attemptCount,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      failureReason: failureReason ?? this.failureReason,
    );
  }
}
