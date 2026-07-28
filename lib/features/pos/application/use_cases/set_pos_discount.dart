import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../../../shared/models/money.dart';
import '../../../orders/domain/discounts/discount.dart';
import '../../../orders/domain/mappers/cart_line_mapper.dart';
import '../../../orders/domain/pricing/tax_policy.dart';
import '../../domain/models/discount_preset.dart';
import '../../domain/models/discount_snapshot.dart';
import '../../domain/models/pos_order_session.dart';
import 'calculate_pos_order_totals.dart';

/// Sets — or, with `preset: null`, clears — the single active discount for
/// one target (a specific line, or the whole order) in a [PosOrderSession].
///
/// **Replaces, never stacks**: any existing [DiscountSnapshot] for the
/// same `(scope, targetOrderLineId)` pair is removed before the new one
/// (if any) is added — so a line can never accumulate more than one
/// active discount, and the session can never carry more than one
/// order-scoped discount (renamed from `ApplyPosDiscount`, Phase 3 Sprint
/// 3C, to reflect this "set" — not "stack" — semantics; see
/// `docs/decisions.md` ADR-012).
///
/// [appliedByStaffId] is always required, whether setting or clearing —
/// never generated or guessed by this use case.
///
/// All financial computation (the percentage-of-base math) happens here,
/// not in the UI — the cashier screen only ever calls this with a
/// [DiscountPreset] and a target.
class SetPosDiscount {
  const SetPosDiscount({required Clock clock})
      : _clock = clock,
        _calculateTotals = const CalculatePosOrderTotals();

  final Clock _clock;
  final CalculatePosOrderTotals _calculateTotals;

  /// Throws [LineDiscountMissingTargetViolation] if [scope] is
  /// [DiscountScope.line] and [targetOrderLineId] is `null`, or
  /// [OrderDiscountMustNotTargetLineViolation] if [scope] is
  /// [DiscountScope.order] and [targetOrderLineId] is given. Throws
  /// [UnknownOrderLineDraftViolation] if [targetOrderLineId] doesn't match
  /// any line in [session].
  PosOrderSession call({
    required PosOrderSession session,
    required DiscountScope scope,
    String? targetOrderLineId,
    required DiscountPreset? preset,
    required String appliedByStaffId,
  }) {
    if (scope == DiscountScope.line) {
      if (targetOrderLineId == null) {
        throw const LineDiscountMissingTargetViolation();
      }
      if (!session.lines.any((draft) => draft.id == targetOrderLineId)) {
        throw UnknownOrderLineDraftViolation(
          orderLineDraftId: targetOrderLineId,
        );
      }
    } else if (targetOrderLineId != null) {
      throw const OrderDiscountMustNotTargetLineViolation();
    }

    final withoutExisting = session.copyWith(
      discounts: [
        for (final discount in session.discounts)
          if (!(discount.scope == scope &&
              discount.targetOrderLineId == targetOrderLineId))
            discount,
      ],
    );

    final now = _clock.now();

    if (preset == null) {
      final cleared = withoutExisting.copyWith(lastUpdatedAt: now);
      return cleared.copyWith(pricing: _calculateTotals(cleared));
    }

    final baseAmount = scope == DiscountScope.line
        ? _lineGrossAmount(withoutExisting, targetOrderLineId!)
        : _calculateTotals(withoutExisting).grossSubtotal;
    final discountAmount =
        baseAmount.scaledBy(preset.percentageBasisPoints, 10000);

    final snapshot = DiscountSnapshot.percentage(
      discountId: preset.id,
      discountName: preset.name,
      percentageBasisPoints: preset.percentageBasisPoints,
      discountAmount: discountAmount,
      scope: scope,
      targetOrderLineId: targetOrderLineId,
      appliedByStaffId: appliedByStaffId,
      appliedAt: now,
    );

    final updated = withoutExisting.copyWith(
      discounts: [...withoutExisting.discounts, snapshot],
      lastUpdatedAt: now,
    );
    return updated.copyWith(pricing: _calculateTotals(updated));
  }

  Money _lineGrossAmount(PosOrderSession session, String orderLineDraftId) {
    final draft = session.lines.firstWhere((d) => d.id == orderLineDraftId);
    return CartLineMapper.mapLine(draft.item, TaxPolicy.defaultRate).lineTotal;
  }
}
