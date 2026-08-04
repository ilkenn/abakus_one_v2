/// Links an existing `PaymentMethod` (`features/payment`, Sprint 3C —
/// the instrument a cashier selects) to a [PaymentMerchantAccount] as
/// the account that actually processes it — Phase 8
/// (`docs/decisions.md` ADR-025), "Merchant Account → Payment Methods."
/// A merchant account may handle multiple payment methods (e.g. one
/// gateway account routing both credit-card and one meal-card brand).
class PaymentMerchantMethodMapping {
  const PaymentMerchantMethodMapping({
    required this.id,
    required this.merchantAccountId,
    required this.paymentMethodId,
    required this.createdAt,
    required this.revision,
  });

  final String id;
  final String merchantAccountId;

  /// References `PaymentMethod.id` (`features/payment`).
  final String paymentMethodId;

  final DateTime createdAt;
  final int revision;
}
