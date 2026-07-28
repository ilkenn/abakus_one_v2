import '../../../../core/errors/business_rule_violation.dart';
import '../../domain/models/payment_session.dart';
import '../../domain/models/payment_session_status.dart';

/// Removes one [PaymentSplit] from a [PaymentSession] by its id — e.g. the
/// cashier entered the wrong amount and wants to redo it before
/// completion (not to be confused with `VoidPayment`/`PaymentCorrection`,
/// which correct an already-*completed* session's settled split).
///
/// Recomputes [PaymentSessionStatus] after removal, same as
/// [AddPaymentSplit] — `readyToComplete -> collecting` the moment removal
/// drops `remainingAmount` back above zero.
class RemovePaymentSplit {
  const RemovePaymentSplit();

  /// Throws [PaymentSessionNotEditableViolation] if [session] is not
  /// `collecting`/`readyToComplete`, or [UnknownPaymentSplitViolation] if
  /// no split with [splitId] exists.
  PaymentSession call({
    required PaymentSession session,
    required String splitId,
  }) {
    if (session.status != PaymentSessionStatus.collecting &&
        session.status != PaymentSessionStatus.readyToComplete) {
      throw PaymentSessionNotEditableViolation(statusName: session.status.name);
    }
    if (!session.splits.any((split) => split.id == splitId)) {
      throw UnknownPaymentSplitViolation(splitId: splitId);
    }

    final updated = session.copyWith(
      splits: [
        for (final split in session.splits)
          if (split.id != splitId) split,
      ],
      revision: session.revision + 1,
    );
    return updated.copyWith(
      status: updated.isFullySettled
          ? PaymentSessionStatus.readyToComplete
          : PaymentSessionStatus.collecting,
    );
  }
}
