import '../../../../shared/models/money.dart';

/// The full, itemized result of [PriceCalculator.calculate] — every figure
/// a receipt, a POS summary screen, or Kitchen/Admin needs, computed once
/// and frozen.
///
/// **Tax scope, explicit and deliberate** (approved architecture decision):
/// [taxableBase] and [vatAmount] are the sum of each [OrderLine]'s own
/// frozen [TaxSnapshot] — they reflect VAT exactly as extracted from what
/// each line itself charges (which already accounts for that line's own
/// [OrderLine.lineDiscount]). [discount] (an order-level [Discount],
/// applied on top of the summed lines), [serviceFee], [deliveryFee],
/// [packagingFee], and [tip] do **not** feed back into [taxableBase]/
/// [vatAmount] in this sprint — their tax treatment is explicitly
/// unresolved (see `docs/business_rules.md` BR-TAX-004/005/006). This is a
/// documented, minimal choice, not a hidden assumption: nothing here
/// claims an order-level discount or a fee is or isn't VAT-relevant: it
/// simply isn't modeled as affecting the VAT figures yet.
class PriceBreakdown {
  const PriceBreakdown({
    required this.grossSubtotal,
    required this.discount,
    required this.taxableBase,
    required this.vatAmount,
    required this.serviceFee,
    required this.deliveryFee,
    required this.packagingFee,
    required this.tip,
    required this.grandTotal,
  });

  /// Sum of every [OrderLine.lineTotal] — gross, VAT-inclusive, each
  /// already net of its own line-level discount.
  final Money grossSubtotal;

  /// The order-level [Discount] amount (zero if none), applied on top of
  /// [grossSubtotal].
  final Money discount;

  /// Sum of every line's [TaxSnapshot.taxableBase].
  final Money taxableBase;

  /// Sum of every line's [TaxSnapshot.vatAmount].
  final Money vatAmount;

  final Money serviceFee;
  final Money deliveryFee;
  final Money packagingFee;
  final Money tip;

  /// `grossSubtotal - discount + serviceFee + deliveryFee + packagingFee +
  /// tip` — validated non-negative by [PriceCalculator.calculate].
  final Money grandTotal;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is PriceBreakdown &&
            other.grossSubtotal == grossSubtotal &&
            other.discount == discount &&
            other.taxableBase == taxableBase &&
            other.vatAmount == vatAmount &&
            other.serviceFee == serviceFee &&
            other.deliveryFee == deliveryFee &&
            other.packagingFee == packagingFee &&
            other.tip == tip &&
            other.grandTotal == grandTotal);
  }

  @override
  int get hashCode => Object.hash(
        grossSubtotal,
        discount,
        taxableBase,
        vatAmount,
        serviceFee,
        deliveryFee,
        packagingFee,
        tip,
        grandTotal,
      );
}
