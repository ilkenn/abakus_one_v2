import '../../../../core/utils/clock.dart';
import '../../domain/models/pos_order_session.dart';
import 'calculate_pos_order_totals.dart';

/// Removes one line from a [PosOrderSession], identified by its position
/// in [PosOrderSession.lines].
class RemovePosOrderLine {
  const RemovePosOrderLine({required Clock clock})
      : _clock = clock,
        _calculateTotals = const CalculatePosOrderTotals();

  final Clock _clock;
  final CalculatePosOrderTotals _calculateTotals;

  /// Throws a `RangeError` if [lineIndex] is out of bounds — a caller/UI
  /// bug, not a domain business-rule violation.
  PosOrderSession call({
    required PosOrderSession session,
    required int lineIndex,
  }) {
    if (lineIndex < 0 || lineIndex >= session.lines.length) {
      throw RangeError.index(lineIndex, session.lines, 'lineIndex');
    }

    final updatedLines = [
      for (var i = 0; i < session.lines.length; i++)
        if (i != lineIndex) session.lines[i],
    ];

    final updated = session.copyWith(
      lines: updatedLines,
      lastUpdatedAt: _clock.now(),
    );
    return updated.copyWith(pricing: _calculateTotals(updated));
  }
}
