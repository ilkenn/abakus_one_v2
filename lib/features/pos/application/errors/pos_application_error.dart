import '../../../../core/errors/business_rule_violation.dart';

/// A typed, POS-application-layer error the controller/UI can switch on —
/// the mapped counterpart of a domain [BusinessRuleViolation] (see
/// [PosValidationError.violation]) plus a few POS-specific conditions
/// (no active session, a submission already in flight, a repository
/// failure) that aren't domain violations at all.
///
/// Closed, `switch`-exhaustive hierarchy, mirroring [BusinessRuleViolation]
/// itself — a call site that branches on a [PosApplicationError] gets an
/// analyzer error if a new subtype is added and left unhandled.
sealed class PosApplicationError {
  const PosApplicationError();

  /// Short, technical, English description — for logs/debugging. Turkish
  /// user-facing copy is the UI layer's job (this type carries the
  /// *category* of failure, not a rendered message), consistent with how
  /// `BusinessRuleViolation` itself draws that line.
  String get description;
}

/// A mutation was attempted with no active [PosOrderSession] (e.g. the
/// controller is still `idle`).
final class PosNoActiveSessionError extends PosApplicationError {
  const PosNoActiveSessionError();

  @override
  String get description => 'No active POS order session';
}

/// [SubmitPosOrder] was called with an empty session, or a second submit
/// was attempted while one was already in flight.
final class PosSubmissionRejectedError extends PosApplicationError {
  const PosSubmissionRejectedError({required this.reason});

  final String reason;

  @override
  String get description => 'Submission rejected: $reason';
}

/// A domain [BusinessRuleViolation] was thrown by a use case — [violation]
/// is preserved verbatim for diagnostics (logs, tests), not discarded
/// behind a generic message.
final class PosValidationError extends PosApplicationError {
  const PosValidationError(this.violation);

  final BusinessRuleViolation violation;

  @override
  String get description => violation.description;
}

/// [PosOrderRepository] failed (draft save/load/delete, or the final
/// submit persistence step).
final class PosRepositoryError extends PosApplicationError {
  const PosRepositoryError({required this.cause});

  final Object cause;

  @override
  String get description => 'Repository operation failed: $cause';
}

/// Anything else — a defensive fallback, never expected to actually
/// trigger, mirroring `ErrorMapper`'s `UnexpectedFailure` shape.
final class PosUnexpectedError extends PosApplicationError {
  const PosUnexpectedError({required this.cause});

  final Object cause;

  @override
  String get description => 'Unexpected error: $cause';
}
