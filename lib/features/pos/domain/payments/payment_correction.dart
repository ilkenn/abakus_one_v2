import '../../../payment/domain/models/payment_method_snapshot.dart';
import 'payment_correction_type.dart';

/// Links an original (now voided) `PaymentSplit` to its replacement — the
/// record of *why* and *how* a payment was corrected, never a mutation of
/// either split (`docs/decisions.md` ADR-012).
///
/// Only [correctionType] == [PaymentCorrectionType.paymentMethodCorrection]
/// is actually produced this sprint, by `CorrectPaymentMethod`; the other
/// four fields' worth of nullable data
/// ([previousPaymentMethodSnapshot]/[newPaymentMethodSnapshot] specifically)
/// exist for that flow — a future amount/reference/merge/split correction
/// would populate a different subset, not add new fields to this class.
///
/// **If the financial total doesn't change**, a payment-method correction
/// is a pure book-keeping fix: [replacementPaymentId] is set once the
/// replacement split is recorded, but no *new* money is collected — the
/// original split's [PaymentVoid] plus this record are the entire
/// correction. If the original was provider-processed, the provider's own
/// void/refund capability must be used (never a direct record edit) —
/// [providerReversalReference] carries that outcome when applicable.
class PaymentCorrection {
  const PaymentCorrection({
    required this.id,
    required this.correctionType,
    required this.originalPaymentId,
    this.replacementPaymentId,
    required this.correctionReferenceId,
    this.previousPaymentMethodSnapshot,
    this.newPaymentMethodSnapshot,
    required this.correctionReason,
    required this.correctedByStaffId,
    required this.correctedAt,
    this.approvedByStaffId,
    this.providerReversalReference,
  });

  final String id;
  final PaymentCorrectionType correctionType;

  /// The `PaymentSplit.id` this correction targets — that split itself is
  /// never mutated; a `PaymentVoid` referencing it is what actually
  /// invalidates it.
  final String originalPaymentId;

  /// The new `PaymentSplit.id` recorded to replace it, once created.
  /// `null` until the replacement split actually exists.
  final String? replacementPaymentId;

  /// A stable id linking this correction to the void/replacement pair it
  /// coordinates — what a future closed-account detail screen would
  /// group by.
  final String correctionReferenceId;

  final PaymentMethodSnapshot? previousPaymentMethodSnapshot;
  final PaymentMethodSnapshot? newPaymentMethodSnapshot;

  final String correctionReason;

  /// Always externally supplied — never generated or guessed.
  final String correctedByStaffId;
  final DateTime correctedAt;

  /// Who approved this correction, if `PosAuthorizedAction.correctPayment`
  /// required approval and it was granted. `null` if no approval was
  /// required or none exists yet.
  final String? approvedByStaffId;

  final String? providerReversalReference;
}
