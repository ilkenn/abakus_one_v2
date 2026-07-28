import 'payment_void_status.dart';

/// A request to void one already-*completed* `PaymentSplit` — never a
/// mutation of the split itself (`docs/decisions.md` ADR-012's
/// append-only-financial-record principle). The original split stays
/// exactly as recorded; this is a separate, linked record that says "this
/// one is no longer valid."
///
/// Distinct from a refund (`RefundIntent`, domain-only foundation this
/// sprint) — a void corrects a mistake made *while* recording the
/// payment (wrong method, wrong amount typed), a refund reverses money
/// after the fact for an otherwise-correct payment.
class PaymentVoid {
  const PaymentVoid({
    required this.id,
    required this.originalSplitId,
    required this.reason,
    required this.requestedByStaffId,
    required this.requestedAt,
    required this.status,
    this.providerReversalReference,
  });

  final String id;
  final String originalSplitId;
  final String reason;

  /// Always externally supplied — never generated or guessed.
  final String requestedByStaffId;
  final DateTime requestedAt;

  final PaymentVoidStatus status;

  /// The provider's own reference for the reversal, if the original split
  /// was provider-processed and the reversal call succeeded.
  final String? providerReversalReference;

  PaymentVoid copyWith({
    PaymentVoidStatus? status,
    String? providerReversalReference,
  }) {
    return PaymentVoid(
      id: id,
      originalSplitId: originalSplitId,
      reason: reason,
      requestedByStaffId: requestedByStaffId,
      requestedAt: requestedAt,
      status: status ?? this.status,
      providerReversalReference:
          providerReversalReference ?? this.providerReversalReference,
    );
  }
}
