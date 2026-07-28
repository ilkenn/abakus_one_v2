import '../../../../core/errors/business_rule_violation.dart';

/// Maps a `PaymentSession` use-case failure into a controller/UI-facing
/// error — the payment-flow counterpart of `PosApplicationError`, kept as
/// its own small hierarchy rather than folded into that one (a payment
/// session is a conceptually distinct flow from the POS order session,
/// same reasoning as keeping `PaymentSession` itself out of
/// `orders/domain/payment/`, see `docs/decisions.md` ADR-012).
sealed class PaymentApplicationError {
  const PaymentApplicationError();

  String get description;
}

/// A `BusinessRuleViolation` thrown by a payment-session use case —
/// preserves the original violation for diagnostics.
final class PaymentValidationError extends PaymentApplicationError {
  const PaymentValidationError(this.violation);

  final BusinessRuleViolation violation;

  @override
  String get description => violation.description;
}

/// A `PaymentSessionRepository` call threw — wraps whatever the
/// infrastructure layer actually threw.
final class PaymentRepositoryError extends PaymentApplicationError {
  const PaymentRepositoryError({required this.cause});

  final Object cause;

  @override
  String get description => 'Repository error: $cause';
}

/// An action was attempted with no active `PaymentSession`.
final class PaymentNoActiveSessionError extends PaymentApplicationError {
  const PaymentNoActiveSessionError();

  @override
  String get description => 'No active payment session';
}
