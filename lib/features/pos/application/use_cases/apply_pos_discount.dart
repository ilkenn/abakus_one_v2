import '../../../../core/utils/clock.dart';
import '../../../orders/domain/discounts/discount.dart';
import '../../domain/models/pos_order_session.dart';
import 'calculate_pos_order_totals.dart';

/// Sets or clears a [PosOrderSession]'s single order-level [Discount].
///
/// This session shape has exactly one discount slot — pass `null` to
/// clear it, a non-null [Discount] to set/replace it. There is no
/// stacking to resolve (`DiscountStackingPolicy` isn't invoked here): the
/// data shape itself structurally prevents having more than one
/// candidate at a time.
class ApplyPosDiscount {
  const ApplyPosDiscount({required Clock clock})
      : _clock = clock,
        _calculateTotals = const CalculatePosOrderTotals();

  final Clock _clock;
  final CalculatePosOrderTotals _calculateTotals;

  PosOrderSession call({
    required PosOrderSession session,
    required Discount? discount,
  }) {
    final updated = session.copyWith(
      discount: discount,
      clearDiscount: discount == null,
      lastUpdatedAt: _clock.now(),
    );
    return updated.copyWith(pricing: _calculateTotals(updated));
  }
}
