import 'payment_method.dart';
import 'payment_method_reporting_category.dart';
import 'payment_provider_id.dart';

/// The 9 built-in [PaymentMethod]s this app ships with — seed data, not a
/// closed enum (see `PaymentMethod`'s own doc comment). A future Admin
/// Panel is meant to add/edit/reorder/disable entries without any code
/// change; this list is only where the *initial* set comes from.
///
/// **Provider mapping is deliberately conservative**: `creditCard` has no
/// [PaymentMethod.providerId] here — which processor (iyzico/Stripe/Adyen/
/// Ödeal) handles card payments is a business decision this sprint doesn't
/// make, not an oversight. Each meal-card method maps 1:1 to its own
/// same-named [PaymentProviderId] (an unambiguous pairing — Pluxee the
/// method is processed by Pluxee the provider). `cash`/`bankTransfer`/
/// `giftVoucher` never carry a provider at all — manually recorded
/// payments, per `docs/business_rules.md`.
abstract final class PaymentMethodSeedData {
  PaymentMethodSeedData._();

  static const PaymentMethod cash = PaymentMethod(
    id: 'cash',
    name: 'Nakit',
    iconAssetPath: 'assets/images/payment/cash.png',
    brandColorValue: 0xFF2E7D32,
    isActive: true,
    supportsSplitPayment: true,
    supportsRefund: true,
    requiresReferenceNumber: false,
    requiresApproval: false,
    sortOrder: 0,
    reportingCategory: PaymentMethodReportingCategory.cash,
  );

  static const PaymentMethod creditCard = PaymentMethod(
    id: 'credit_card',
    name: 'Kredi/Banka Kartı',
    iconAssetPath: 'assets/images/payment/credit_card.png',
    brandColorValue: 0xFF1565C0,
    isActive: true,
    supportsSplitPayment: true,
    supportsRefund: true,
    requiresReferenceNumber: false,
    requiresApproval: false,
    sortOrder: 1,
    reportingCategory: PaymentMethodReportingCategory.card,
  );

  static const PaymentMethod pluxee = PaymentMethod(
    id: 'pluxee',
    name: 'Pluxee',
    iconAssetPath: 'assets/images/payment/pluxee.png',
    brandColorValue: 0xFFEE2A7B,
    isActive: true,
    supportsSplitPayment: true,
    supportsRefund: true,
    requiresReferenceNumber: false,
    requiresApproval: false,
    sortOrder: 2,
    reportingCategory: PaymentMethodReportingCategory.mealCard,
    providerId: PaymentProviderId.pluxee,
  );

  static const PaymentMethod multinet = PaymentMethod(
    id: 'multinet',
    name: 'Multinet',
    iconAssetPath: 'assets/images/payment/multinet.png',
    brandColorValue: 0xFFF37021,
    isActive: true,
    supportsSplitPayment: true,
    supportsRefund: true,
    requiresReferenceNumber: false,
    requiresApproval: false,
    sortOrder: 3,
    reportingCategory: PaymentMethodReportingCategory.mealCard,
    providerId: PaymentProviderId.multinet,
  );

  static const PaymentMethod setcard = PaymentMethod(
    id: 'setcard',
    name: 'Setcard',
    iconAssetPath: 'assets/images/payment/setcard.png',
    brandColorValue: 0xFF6A1B9A,
    isActive: true,
    supportsSplitPayment: true,
    supportsRefund: true,
    requiresReferenceNumber: false,
    requiresApproval: false,
    sortOrder: 4,
    reportingCategory: PaymentMethodReportingCategory.mealCard,
    providerId: PaymentProviderId.setcard,
  );

  static const PaymentMethod edenred = PaymentMethod(
    id: 'edenred',
    name: 'Edenred',
    iconAssetPath: 'assets/images/payment/edenred.png',
    brandColorValue: 0xFFE30613,
    isActive: true,
    supportsSplitPayment: true,
    supportsRefund: true,
    requiresReferenceNumber: false,
    requiresApproval: false,
    sortOrder: 5,
    reportingCategory: PaymentMethodReportingCategory.mealCard,
    providerId: PaymentProviderId.edenred,
  );

  static const PaymentMethod metropolCard = PaymentMethod(
    id: 'metropol_card',
    name: 'MetropolCard',
    iconAssetPath: 'assets/images/payment/metropol_card.png',
    brandColorValue: 0xFF00838F,
    isActive: true,
    supportsSplitPayment: true,
    supportsRefund: true,
    requiresReferenceNumber: false,
    requiresApproval: false,
    sortOrder: 6,
    reportingCategory: PaymentMethodReportingCategory.mealCard,
    providerId: PaymentProviderId.metropolCard,
  );

  static const PaymentMethod bankTransfer = PaymentMethod(
    id: 'bank_transfer',
    name: 'Banka Transferi / EFT',
    iconAssetPath: 'assets/images/payment/bank_transfer.png',
    brandColorValue: 0xFF37474F,
    isActive: true,
    supportsSplitPayment: true,
    supportsRefund: true,
    requiresReferenceNumber: true,
    requiresApproval: false,
    sortOrder: 7,
    reportingCategory: PaymentMethodReportingCategory.bankTransfer,
  );

  static const PaymentMethod giftVoucher = PaymentMethod(
    id: 'gift_voucher',
    name: 'Hediye Çeki',
    iconAssetPath: 'assets/images/payment/gift_voucher.png',
    brandColorValue: 0xFFF9A825,
    isActive: true,
    supportsSplitPayment: true,
    supportsRefund: true,
    requiresReferenceNumber: true,
    requiresApproval: false,
    sortOrder: 8,
    reportingCategory: PaymentMethodReportingCategory.giftVoucher,
  );

  /// Every built-in method, in seed [PaymentMethod.sortOrder].
  static const List<PaymentMethod> all = [
    cash,
    creditCard,
    pluxee,
    multinet,
    setcard,
    edenred,
    metropolCard,
    bankTransfer,
    giftVoucher,
  ];

  /// [all] with [PaymentMethod.isActive] `true`.
  static List<PaymentMethod> get active =>
      all.where((method) => method.isActive).toList();
}
