import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../domain/models/pos_order_session.dart';
import 'calculate_pos_order_totals.dart';

/// Removes one line from a [PosOrderSession], identified by its stable
/// `PosOrderLineDraft.id` — never an array index (Phase 3 Sprint 3C,
/// `docs/decisions.md` ADR-012).
///
/// Also drops any [DiscountSnapshot] whose `targetOrderLineId` matches the
/// removed line — a line discount pointing at a line that no longer
/// exists would be meaningless, and leaving it in `session.discounts`
/// would let a later re-add of a line accidentally "inherit" a stale
/// discount if ids were ever reused (they aren't, but this is defensive
/// regardless).
class RemovePosOrderLine {
  const RemovePosOrderLine({required Clock clock})
      : _clock = clock,
        _calculateTotals = const CalculatePosOrderTotals();

  final Clock _clock;
  final CalculatePosOrderTotals _calculateTotals;

  /// Throws [UnknownOrderLineDraftViolation] if no line with
  /// [orderLineDraftId] exists in [session].
  PosOrderSession call({
    required PosOrderSession session,
    required String orderLineDraftId,
  }) {
    if (!session.lines.any((draft) => draft.id == orderLineDraftId)) {
      throw UnknownOrderLineDraftViolation(orderLineDraftId: orderLineDraftId);
    }

    final updatedLines = [
      for (final draft in session.lines)
        if (draft.id != orderLineDraftId) draft,
    ];
    final updatedDiscounts = [
      for (final discount in session.discounts)
        if (discount.targetOrderLineId != orderLineDraftId) discount,
    ];

    final updated = session.copyWith(
      lines: updatedLines,
      discounts: updatedDiscounts,
      lastUpdatedAt: _clock.now(),
    );
    return updated.copyWith(pricing: _calculateTotals(updated));
  }
}
