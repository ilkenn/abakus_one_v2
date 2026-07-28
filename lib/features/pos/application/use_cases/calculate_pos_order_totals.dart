import '../../../../shared/models/currency.dart';
import '../../../../shared/models/money.dart';
import '../../../orders/domain/discounts/discount.dart';
import '../../../orders/domain/mappers/cart_line_mapper.dart';
import '../../../orders/domain/pricing/price_breakdown.dart';
import '../../../orders/domain/pricing/price_calculator.dart';
import '../../../orders/domain/pricing/tax_policy.dart';
import '../../domain/models/discount_snapshot.dart';
import '../../domain/models/pos_order_session.dart';

/// Recomputes a [PosOrderSession]'s [PriceBreakdown] from its current
/// [PosOrderSession.lines]/[PosOrderSession.discounts]/
/// [PosOrderSession.fees]/[PosOrderSession.tip].
///
/// **Never invents an [OrderId]/[OrderNumber]** to get there — per the
/// approved architecture decision, this does not call
/// `CartToOrderMapper.map()` (which requires both). Instead it reuses
/// [CartLineMapper] directly, the exact same per-line snapshot logic
/// `CartToOrderMapper` itself calls — a live totals preview and a real
/// submitted order are guaranteed to price a given set of lines
/// identically, without duplicating that logic.
///
/// Each line's own active line-scoped [DiscountSnapshot] (if any) is
/// applied via `CartLineMapper.mapLine`'s `lineDiscount` parameter — this
/// is the first sprint that parameter is ever actually exercised (Phase 3
/// Sprint 3C). The single order-scoped snapshot (if any) is applied on top
/// of the summed gross subtotal, same as the old single-`Discount?` field
/// did.
///
/// [PosOrderSession.fees] (a single, undifferentiated amount) is passed
/// through as `PriceCalculator`'s `serviceFee` parameter —
/// `deliveryFee`/`packagingFee` stay zero, since this sprint's session
/// shape doesn't distinguish fee types.
class CalculatePosOrderTotals {
  const CalculatePosOrderTotals();

  PriceBreakdown call(PosOrderSession session) {
    final currency = Currency.accountingCurrency;
    final orderLines = [
      for (final draft in session.lines)
        CartLineMapper.mapLine(
          draft.item,
          TaxPolicy.defaultRate,
          lineDiscount: _activeLineDiscount(session.discounts, draft.id)
              ?.discountAmount,
        ),
    ];

    Money? orderDiscountAmount;
    final orderDiscount = _activeOrderDiscount(session.discounts);
    if (orderDiscount != null) {
      orderDiscountAmount = orderDiscount.discountAmount;
    }

    return PriceCalculator.calculate(
      lines: orderLines,
      currency: currency,
      discount: orderDiscountAmount,
      serviceFee: session.fees,
      tip: session.tip,
    );
  }

  static DiscountSnapshot? _activeLineDiscount(
    List<DiscountSnapshot> discounts,
    String orderLineDraftId,
  ) {
    for (final discount in discounts) {
      if (discount.scope == DiscountScope.line &&
          discount.targetOrderLineId == orderLineDraftId) {
        return discount;
      }
    }
    return null;
  }

  static DiscountSnapshot? _activeOrderDiscount(
    List<DiscountSnapshot> discounts,
  ) {
    for (final discount in discounts) {
      if (discount.scope == DiscountScope.order) return discount;
    }
    return null;
  }
}
