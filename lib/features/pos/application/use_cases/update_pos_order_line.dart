import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../domain/models/pos_order_session.dart';
import 'calculate_pos_order_totals.dart';

/// Updates the quantity and/or note of an existing line in a
/// [PosOrderSession], identified by its position in
/// [PosOrderSession.lines].
class UpdatePosOrderLine {
  const UpdatePosOrderLine({required Clock clock})
      : _clock = clock,
        _calculateTotals = const CalculatePosOrderTotals();

  final Clock _clock;
  final CalculatePosOrderTotals _calculateTotals;

  /// Throws [NonPositiveQuantityViolation] if [quantity] is given and not
  /// positive (use `RemovePosOrderLine` to remove a line instead of
  /// setting its quantity to zero). Throws [UnknownModifierOptionViolation]-
  /// shaped-but-generic index errors via a plain `RangeError` if
  /// [lineIndex] is out of bounds — that's a caller/UI bug, not a domain
  /// business-rule violation, so it isn't mapped through
  /// [BusinessRuleViolation].
  PosOrderSession call({
    required PosOrderSession session,
    required int lineIndex,
    int? quantity,
    String? note,
  }) {
    if (lineIndex < 0 || lineIndex >= session.lines.length) {
      throw RangeError.index(lineIndex, session.lines, 'lineIndex');
    }
    if (quantity != null && quantity <= 0) {
      throw NonPositiveQuantityViolation(
        context: 'UpdatePosOrderLine.quantity',
        quantity: quantity,
      );
    }

    final updatedLines = [
      for (var i = 0; i < session.lines.length; i++)
        if (i == lineIndex)
          session.lines[i].copyWith(
            quantity: quantity ?? session.lines[i].quantity,
            note: note ?? session.lines[i].note,
          )
        else
          session.lines[i],
    ];

    final updated = session.copyWith(
      lines: updatedLines,
      lastUpdatedAt: _clock.now(),
    );
    return updated.copyWith(pricing: _calculateTotals(updated));
  }
}
