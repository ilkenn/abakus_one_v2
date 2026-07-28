import '../../../../shared/models/money.dart';

/// Whether a [CashVariance] is a shortage, an overage, or an exact match.
enum CashVarianceType { over, short, exact }

/// The gap between an expected and an actually-declared cash amount — a
/// value object shared by [CashCount] (what was found) and
/// [CashReconciliation] (what a manager reviewed), computed once via
/// [CashVariance.compute] rather than independently reimplemented at each
/// call site.
class CashVariance {
  const CashVariance({required this.amount, required this.type});

  /// Always non-negative — the magnitude of the gap. [type] carries the
  /// direction.
  final Money amount;
  final CashVarianceType type;

  bool get isExact => type == CashVarianceType.exact;

  /// `actual - expected`: positive means an overage, negative a shortage,
  /// zero an exact match.
  factory CashVariance.compute({
    required Money expectedAmount,
    required Money actualAmount,
  }) {
    final difference = actualAmount - expectedAmount;
    if (difference.isZero) {
      return CashVariance(amount: difference, type: CashVarianceType.exact);
    }
    return CashVariance(
      amount: difference.isNegative ? -difference : difference,
      type: difference.isNegative
          ? CashVarianceType.short
          : CashVarianceType.over,
    );
  }
}
