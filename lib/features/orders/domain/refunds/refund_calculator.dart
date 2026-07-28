import '../../../../core/errors/business_rule_violation.dart';
import '../../../../shared/models/money.dart';

/// Pure domain logic for validating a [RefundIntent] against an order's
/// refundable balance — **never mutates anything, never persists
/// anything**; a future `ProcessRefund` application use case would call
/// this before actually recording a refund (not built this sprint, per
/// the approved refund-foundation-only scope).
abstract final class RefundCalculator {
  RefundCalculator._();

  /// `settledAmount - alreadyRefundedAmount`, never negative — the most a
  /// new refund request may still take.
  static Money refundableAmount({
    required Money settledAmount,
    required Money alreadyRefundedAmount,
  }) {
    final refundable = settledAmount - alreadyRefundedAmount;
    return refundable.isNegative
        ? Money.zero(settledAmount.currency)
        : refundable;
  }

  /// Throws [RefundExceedsRefundableAmountViolation] if [requestedAmount]
  /// exceeds [refundableAmount] for the given [settledAmount]/
  /// [alreadyRefundedAmount] — the one rule both a full and a partial
  /// refund must satisfy (a full refund is simply a request for the
  /// entire refundable amount, not a structurally different case).
  static void validateRefundRequest({
    required Money requestedAmount,
    required Money settledAmount,
    required Money alreadyRefundedAmount,
  }) {
    final refundable = refundableAmount(
      settledAmount: settledAmount,
      alreadyRefundedAmount: alreadyRefundedAmount,
    );
    if (requestedAmount > refundable) {
      throw RefundExceedsRefundableAmountViolation(
        requestedMinorUnits: requestedAmount.minorUnits,
        refundableMinorUnits: refundable.minorUnits,
      );
    }
  }
}
