import '../../../../shared/models/currency.dart';
import '../../../../shared/models/money.dart';
import '../../../orders/domain/mappers/cart_line_mapper.dart';
import '../../../orders/domain/pricing/price_breakdown.dart';
import '../../../orders/domain/pricing/price_calculator.dart';
import '../../../orders/domain/pricing/tax_policy.dart';
import '../../domain/models/pos_order_session.dart';

/// Recomputes a [PosOrderSession]'s [PriceBreakdown] from its current
/// [PosOrderSession.lines]/[PosOrderSession.discount]/
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
/// [PosOrderSession.fees] (a single, undifferentiated amount) is passed
/// through as `PriceCalculator`'s `serviceFee` parameter —
/// `deliveryFee`/`packagingFee` stay zero, since this sprint's session
/// shape doesn't distinguish fee types. The arithmetic is identical
/// regardless of which of the three parameters carries it (`PriceCalculator
/// .calculate` only ever sums them), so this is a labeling choice, not a
/// pricing one.
class CalculatePosOrderTotals {
  const CalculatePosOrderTotals();

  PriceBreakdown call(PosOrderSession session) {
    final currency = Currency.accountingCurrency;
    final orderLines = session.lines
        .map((item) => CartLineMapper.mapLine(item, TaxPolicy.defaultRate))
        .toList();

    Money? discountAmount;
    final discount = session.discount;
    if (discount != null) {
      final grossSubtotal = orderLines.fold<Money>(
        Money.zero(currency),
        (sum, line) => sum + line.lineTotal,
      );
      discountAmount = discount.amountFor(grossSubtotal);
    }

    return PriceCalculator.calculate(
      lines: orderLines,
      currency: currency,
      discount: discountAmount,
      serviceFee: session.fees,
      tip: session.tip,
    );
  }
}
