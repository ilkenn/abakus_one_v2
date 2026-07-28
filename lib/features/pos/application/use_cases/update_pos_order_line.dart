import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../domain/models/pos_order_session.dart';
import 'calculate_pos_order_totals.dart';

/// Updates the quantity and/or note of an existing line in a
/// [PosOrderSession], identified by its stable
/// `PosOrderLineDraft.id` — never an array index (Phase 3 Sprint 3C,
/// `docs/decisions.md` ADR-012).
class UpdatePosOrderLine {
  const UpdatePosOrderLine({required Clock clock})
      : _clock = clock,
        _calculateTotals = const CalculatePosOrderTotals();

  final Clock _clock;
  final CalculatePosOrderTotals _calculateTotals;

  /// Throws [NonPositiveQuantityViolation] if [quantity] is given and not
  /// positive (use `RemovePosOrderLine` to remove a line instead of
  /// setting its quantity to zero). Throws [UnknownOrderLineDraftViolation]
  /// if no line with [orderLineDraftId] exists in [session] — a real
  /// state-consistency violation now that line identity is stable, not a
  /// caller/UI bug.
  PosOrderSession call({
    required PosOrderSession session,
    required String orderLineDraftId,
    int? quantity,
    String? note,
  }) {
    if (!session.lines.any((draft) => draft.id == orderLineDraftId)) {
      throw UnknownOrderLineDraftViolation(orderLineDraftId: orderLineDraftId);
    }
    if (quantity != null && quantity <= 0) {
      throw NonPositiveQuantityViolation(
        context: 'UpdatePosOrderLine.quantity',
        quantity: quantity,
      );
    }

    final updatedLines = [
      for (final draft in session.lines)
        if (draft.id == orderLineDraftId)
          draft.copyWith(
            item: draft.item.copyWith(
              quantity: quantity ?? draft.item.quantity,
              note: note ?? draft.item.note,
            ),
          )
        else
          draft,
    ];

    final updated = session.copyWith(
      lines: updatedLines,
      lastUpdatedAt: _clock.now(),
    );
    return updated.copyWith(pricing: _calculateTotals(updated));
  }
}
