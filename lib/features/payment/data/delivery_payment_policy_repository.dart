import '../domain/models/delivery_payment_policy.dart';
import '../domain/models/payment_method_seed_data.dart';

/// Admin-editable storage for [DeliveryPaymentPolicy] — the future
/// "Teslimat Ödeme Yöntemleri" admin screen's data layer, Faz P.1. No UI
/// reads or writes this yet (out of this phase's scope); only the
/// in-memory seed below does, standing in for that screen's future
/// defaults. Mirrors `ChannelPricingPolicyRepository`'s shape: a
/// repository over a small, admin-configurable ruleset, not a hardcoded
/// constant baked into checkout code — so a future admin can enable
/// online payment for delivery one method at a time via
/// [setEnabledForDeliveryCheckout], without a code change.
abstract interface class DeliveryPaymentPolicyRepository {
  /// The full current policy — read once by a caller rather than queried
  /// method-by-method, so one checkout screen's read is consistent even
  /// if this repository is mutated concurrently.
  Future<DeliveryPaymentPolicy> current();

  Future<void> setEnabledForDeliveryCheckout(
    String paymentMethodId,
    bool enabled,
  );
}

/// Today's only implementation — in-memory, seeded with exactly the 7
/// LOCKED COD method ids (`docs/business_rules.md` — Faz P.1): `cash`,
/// `credit_card`, `pluxee`, `multinet`, `setcard`, `edenred`,
/// `metropol_card`. `bank_transfer` and `gift_voucher` are deliberately
/// absent — every other current/future [PaymentMethodSeedData] entry
/// defaults to disabled for delivery until an admin explicitly enables
/// it.
class InMemoryDeliveryPaymentPolicyRepository
    implements DeliveryPaymentPolicyRepository {
  InMemoryDeliveryPaymentPolicyRepository()
      : _enabledMethodIds = {
          PaymentMethodSeedData.cash.id,
          PaymentMethodSeedData.creditCard.id,
          PaymentMethodSeedData.pluxee.id,
          PaymentMethodSeedData.multinet.id,
          PaymentMethodSeedData.setcard.id,
          PaymentMethodSeedData.edenred.id,
          PaymentMethodSeedData.metropolCard.id,
        };

  final Set<String> _enabledMethodIds;

  @override
  Future<DeliveryPaymentPolicy> current() async {
    return DeliveryPaymentPolicy(
      enabledMethodIds: Set.unmodifiable(_enabledMethodIds),
    );
  }

  @override
  Future<void> setEnabledForDeliveryCheckout(
    String paymentMethodId,
    bool enabled,
  ) async {
    if (enabled) {
      _enabledMethodIds.add(paymentMethodId);
    } else {
      _enabledMethodIds.remove(paymentMethodId);
    }
  }
}
