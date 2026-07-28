import 'payment_method.dart';
import 'payment_method_reporting_category.dart';
import 'payment_provider_id.dart';

/// A frozen, historical record of everything about a [PaymentMethod] that
/// mattered at the moment one specific payment was recorded — captured
/// once via [PaymentMethodSnapshot.capture], never re-derived from the
/// live [PaymentMethod] catalog afterward.
///
/// **Why this exists** (`docs/decisions.md` ADR-012): a [PaymentMethod] is
/// admin-editable — its name, icon, brand color, or capability flags can
/// change after a payment referencing it was recorded. Every historical
/// payment record (`PaymentSplit`, `PaymentSummaryLine`, a receipt) must
/// keep reporting exactly what was true *then*, so it stores this snapshot
/// instead of a live reference/id lookup. This is the payment-domain
/// counterpart to how `OrderLine` freezes product name/price at order time
/// rather than re-reading the menu later (`docs/business_rules.md`
/// BR-ORDER-002).
///
/// [transactionReference]/[authorizationCode]/[terminalId] are all
/// optional and unused by any method this sprint (no real provider
/// integration exists) — reserved for meal-card/POS-terminal processing
/// once a real [PaymentProviderAdapter] is wired.
class PaymentMethodSnapshot {
  const PaymentMethodSnapshot({
    required this.paymentMethodId,
    required this.displayName,
    required this.iconAssetPath,
    required this.brandColorValue,
    required this.reportingCategory,
    this.providerId,
    required this.supportsSplitPaymentAtCapture,
    required this.supportsRefundAtCapture,
    required this.requiresReferenceNumberAtCapture,
    required this.requiresApprovalAtCapture,
    this.transactionReference,
    this.authorizationCode,
    this.terminalId,
  });

  /// Freezes every field this snapshot needs directly off the given, live
  /// [method] — the one sanctioned way to build a [PaymentMethodSnapshot].
  factory PaymentMethodSnapshot.capture(
    PaymentMethod method, {
    String? transactionReference,
    String? authorizationCode,
    String? terminalId,
  }) {
    return PaymentMethodSnapshot(
      paymentMethodId: method.id,
      displayName: method.name,
      iconAssetPath: method.iconAssetPath,
      brandColorValue: method.brandColorValue,
      reportingCategory: method.reportingCategory,
      providerId: method.providerId,
      supportsSplitPaymentAtCapture: method.supportsSplitPayment,
      supportsRefundAtCapture: method.supportsRefund,
      requiresReferenceNumberAtCapture: method.requiresReferenceNumber,
      requiresApprovalAtCapture: method.requiresApproval,
      transactionReference: transactionReference,
      authorizationCode: authorizationCode,
      terminalId: terminalId,
    );
  }

  final String paymentMethodId;
  final String displayName;
  final String iconAssetPath;
  final int brandColorValue;
  final PaymentMethodReportingCategory reportingCategory;
  final PaymentProviderId? providerId;

  final bool supportsSplitPaymentAtCapture;
  final bool supportsRefundAtCapture;
  final bool requiresReferenceNumberAtCapture;
  final bool requiresApprovalAtCapture;

  /// The processor's own reference for this transaction (e.g. a meal-card
  /// authorization's transaction id), if any.
  final String? transactionReference;

  /// The processor's authorization code, if any.
  final String? authorizationCode;

  /// Which physical POS terminal processed this, if any.
  final String? terminalId;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is PaymentMethodSnapshot &&
            other.paymentMethodId == paymentMethodId &&
            other.displayName == displayName &&
            other.iconAssetPath == iconAssetPath &&
            other.brandColorValue == brandColorValue &&
            other.reportingCategory == reportingCategory &&
            other.providerId == providerId &&
            other.supportsSplitPaymentAtCapture ==
                supportsSplitPaymentAtCapture &&
            other.supportsRefundAtCapture == supportsRefundAtCapture &&
            other.requiresReferenceNumberAtCapture ==
                requiresReferenceNumberAtCapture &&
            other.requiresApprovalAtCapture == requiresApprovalAtCapture &&
            other.transactionReference == transactionReference &&
            other.authorizationCode == authorizationCode &&
            other.terminalId == terminalId);
  }

  @override
  int get hashCode => Object.hash(
        paymentMethodId,
        displayName,
        iconAssetPath,
        brandColorValue,
        reportingCategory,
        providerId,
        supportsSplitPaymentAtCapture,
        supportsRefundAtCapture,
        requiresReferenceNumberAtCapture,
        requiresApprovalAtCapture,
        transactionReference,
        authorizationCode,
        terminalId,
      );
}
