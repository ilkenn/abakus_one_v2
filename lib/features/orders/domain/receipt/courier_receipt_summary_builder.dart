import '../../../../shared/models/money.dart';
import '../pricing/price_breakdown.dart';
import 'courier_receipt_summary.dart';

/// Builds a [CourierReceiptSummary] from an order's [PriceBreakdown] and
/// (if a payment collection has started) its [PaymentSession] — a pure
/// function over already-loaded data, mirroring
/// `ForeignCurrencyEquivalentsCalculator`/`ExpeditorProjectionBuilder`'s
/// shape.
///
/// [totalSettled]/[remainingAmount] are passed in directly (as `Money`,
/// not the whole `PaymentSession`) so this builder has no dependency on
/// the `pos` feature — `orders` must not depend on `pos`
/// (`CLAUDE.md` §3's forbidden-dependency-direction rule); the caller
/// (which already has the `PaymentSession`) supplies just the two numbers
/// this needs.
abstract final class CourierReceiptSummaryBuilder {
  CourierReceiptSummaryBuilder._();

  static CourierReceiptSummary build({
    required PriceBreakdown pricing,
    required Money alreadyPaidAmount,
    required Money remainingToCollectAmount,
  }) {
    return CourierReceiptSummary(
      paymentTypeLabel:
          remainingToCollectAmount.isZero ? 'ÖDENDİ' : 'KAPIDA TAHSİLAT',
      subtotal: pricing.grossSubtotal,
      combinedDiscount: pricing.discount,
      deliveryFee: pricing.deliveryFee,
      tip: pricing.tip,
      total: pricing.grandTotal,
      alreadyPaidAmount: alreadyPaidAmount,
      remainingToCollectAmount: remainingToCollectAmount,
    );
  }
}
