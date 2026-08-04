import 'payment_merchant_account_status.dart';

/// One tenant's merchant account with a payment provider, scoped to a
/// specific `Branch` — Phase 8 (`docs/decisions.md` ADR-025), the
/// Payment Hub's own "Payment Provider → Merchant Account → Branch"
/// hierarchy.
///
/// Deliberately a **new, separate bounded context**
/// (`features/payment_hub/`), not an extension of the pre-existing
/// `features/payment/` (Sprint 3C, ADR-012) — that feature is order-
/// time payment *collection* (`PaymentSession`/`PaymentSplit`/
/// `PaymentService`); this one is tenant-level merchant-account
/// *configuration*. Conflating the two would blur exactly the
/// distinction `docs/decisions.md` ADR-012 already drew between
/// `PaymentMethod` (a cashier's instrument) and `PaymentProviderId` (a
/// technical integration).
class PaymentMerchantAccount {
  const PaymentMerchantAccount({
    required this.id,
    required this.organizationId,
    required this.branchId,
    required this.providerId,
    required this.accountLabel,
    this.status = PaymentMerchantAccountStatus.active,
    required this.createdAt,
    required this.revision,
  });

  final String id;
  final String organizationId;
  final String branchId;

  /// References `IntegrationProviderAdapter.providerId` in the
  /// platform registry (Phase 8G) — must be
  /// `IntegrationProviderCategory.payment`, and reuses the exact same
  /// id strings as the pre-existing `PaymentProviderId` enum values
  /// (`features/payment`, Sprint 3C).
  final String providerId;

  final String accountLabel;
  final PaymentMerchantAccountStatus status;
  final DateTime createdAt;
  final int revision;

  PaymentMerchantAccount copyWith({
    String? accountLabel,
    PaymentMerchantAccountStatus? status,
    required int revision,
  }) {
    return PaymentMerchantAccount(
      id: id,
      organizationId: organizationId,
      branchId: branchId,
      providerId: providerId,
      accountLabel: accountLabel ?? this.accountLabel,
      status: status ?? this.status,
      createdAt: createdAt,
      revision: revision,
    );
  }
}
