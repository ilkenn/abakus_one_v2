import 'payment_method_reporting_category.dart';
import 'payment_provider_id.dart';

/// A payment instrument a cashier can select — extensible data, never a
/// closed enum (see `docs/decisions.md` ADR-012). [PaymentMethodSeedData]
/// provides the 9 built-in methods this app ships with; a future Admin
/// Panel adds/edits/reorders/disables entries here without any code
/// change, exactly mirroring how [Currency] (`shared/models/currency.dart`)
/// was made extensible in ADR-010.
///
/// **Distinct from [PaymentProviderId]** (the technical integration that
/// might process this method) — `cash`/`bankTransfer`/`giftVoucher` have
/// no [providerId] at all and are always manually recorded
/// (`docs/business_rules.md` — manual methods never call
/// `PaymentProviderAdapter`).
///
/// Public constructor — a genuine value type, like [Currency]/[Money] —
/// not restricted to this file.
class PaymentMethod {
  const PaymentMethod({
    required this.id,
    required this.name,
    required this.iconAssetPath,
    required this.brandColorValue,
    required this.isActive,
    required this.supportsSplitPayment,
    required this.supportsRefund,
    required this.requiresReferenceNumber,
    required this.requiresApproval,
    required this.sortOrder,
    required this.reportingCategory,
    this.providerId,
  });

  /// Stable identifier — never reused for a different method once seeded/
  /// admin-created. What [PaymentMethodSnapshot]/[DiscountSnapshot]-style
  /// historical records key against.
  final String id;

  final String name;

  /// Asset reference (e.g. `'assets/images/payment/pluxee.png'`) —
  /// resolved through a presentation-layer seam
  /// (`paymentMethodIconSourceProvider`), never a hardcoded `Icon`/`Image`
  /// literal at a call site. No real brand asset files are supplied this
  /// sprint (see ADR-012's logo-fallback note) — every seed entry's path
  /// currently resolves to nothing, which the resolver treats the same as
  /// any other missing asset: a graceful tinted-icon fallback, not an
  /// error, mirroring `ProductImage`'s existing pattern exactly.
  final String iconAssetPath;

  /// ARGB color value (`Color(brandColorValue)` at the presentation layer)
  /// — kept as a plain `int` here since domain code never imports Flutter
  /// (`CLAUDE.md` §3).
  final int brandColorValue;

  final bool isActive;
  final bool supportsSplitPayment;
  final bool supportsRefund;

  /// Whether recording a payment with this method requires a
  /// caller-supplied reference number (e.g. a bank transfer's transaction
  /// reference) — enforced by `CompletePaymentSession`, never assumed.
  final bool requiresReferenceNumber;

  /// Whether completing a payment with this method requires a manager
  /// approval result to be present — enforced by `CompletePaymentSession`
  /// via the (foundation-only) authorization/approval contracts.
  final bool requiresApproval;

  final int sortOrder;

  final PaymentMethodReportingCategory reportingCategory;

  /// `null` for a manually recorded method (cash, bank transfer, gift
  /// voucher) — no [PaymentProviderAdapter] is ever invoked for those.
  /// Non-null for a method a provider actually processes (card, meal
  /// cards).
  final PaymentProviderId? providerId;

  /// Whether this method is ever routed through a
  /// [PaymentProviderAdapter] at all.
  bool get requiresProvider => providerId != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is PaymentMethod && other.id == id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'PaymentMethod($id)';
}
