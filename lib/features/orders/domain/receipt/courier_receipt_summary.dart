import '../../../../shared/models/money.dart';

/// The courier/customer-facing delivery receipt summary — built to make
/// the **remaining amount to collect** the single most prominent number
/// on the slip (rendered large/bold at the print-layer; this is the
/// domain data that layer reads from).
///
/// [combinedDiscount] is [PriceBreakdown.discount] as-is — a single,
/// undifferentiated total. The codebase's [PriceBreakdown] does not
/// currently separate item-level vs. order-level discounts, and no
/// campaign/coupon engine exists to attribute part of it to either
/// (`docs/business_rules.md` BR-PROMO-003/004 remain UNRESOLVED) — this
/// field is not split into fake sub-amounts to satisfy a line-item layout
/// that has no real data behind it.
class CourierReceiptSummary {
  const CourierReceiptSummary({
    required this.paymentTypeLabel,
    required this.subtotal,
    required this.combinedDiscount,
    required this.deliveryFee,
    required this.tip,
    required this.total,
    required this.alreadyPaidAmount,
    required this.remainingToCollectAmount,
  });

  /// "ÖDENDİ" once [remainingToCollectAmount] is zero, "KAPIDA TAHSİLAT"
  /// otherwise. Deliberately not a method-specific label ("CASH AT DOOR"
  /// vs. "CARD AT DOOR") — this codebase has no field recording which
  /// method a courier is expected to collect with before they actually
  /// do; that distinction would need to be added at the point a real
  /// "expected collection method" concept exists, not fabricated here.
  final String paymentTypeLabel;

  final Money subtotal;
  final Money combinedDiscount;
  final Money deliveryFee;
  final Money tip;
  final Money total;
  final Money alreadyPaidAmount;
  final Money remainingToCollectAmount;

  bool get hasRemainingCollection => !remainingToCollectAmount.isZero;
}
