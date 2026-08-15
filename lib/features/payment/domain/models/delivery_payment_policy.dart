import 'payment_method.dart';

/// Which payment methods a customer may choose from at Paket Servis
/// (delivery) checkout — Faz P.1, LOCKED §2/§3: the initial release is
/// COD-only, exactly the 7 methods a
/// [DeliveryPaymentPolicyRepository] seeds by default; online payment,
/// bank transfer, and gift voucher are explicitly excluded.
///
/// **Deliberately independent of [PaymentMethod.isActive]** — that flag
/// controls whether a method exists/works at all, on any channel; this
/// policy controls whether an already-active method is additionally
/// permitted on the delivery channel specifically. A method must satisfy
/// both to actually be offered to a delivery customer — see
/// [isAvailableForDeliveryCheckout]. Never invokes a
/// `PaymentProviderAdapter` — every currently-enabled method is a
/// manually recorded, cash-on-delivery-style instrument.
class DeliveryPaymentPolicy {
  const DeliveryPaymentPolicy({required this.enabledMethodIds});

  /// The [PaymentMethod.id]s currently permitted at delivery checkout.
  final Set<String> enabledMethodIds;

  bool isEnabledForDeliveryCheckout(String paymentMethodId) =>
      enabledMethodIds.contains(paymentMethodId);

  /// The combined check a checkout screen must use — both this policy's
  /// own enablement AND the method's own [PaymentMethod.isActive] must
  /// hold. See this class's own doc comment for why the two are kept
  /// structurally separate rather than collapsed into one flag.
  bool isAvailableForDeliveryCheckout(PaymentMethod method) =>
      method.isActive && isEnabledForDeliveryCheckout(method.id);
}
