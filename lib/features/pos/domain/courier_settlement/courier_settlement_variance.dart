import '../../../../shared/models/money.dart';

/// Whether a [CourierSettlementVariance] is a shortage, an overage, or an
/// exact match.
enum CourierVarianceType { over, short, exact }

/// The gap between the expected amount (sum of a settlement session's
/// [CourierCashCollection]s) and what a courier actually declared — a
/// value object shared by [CourierCashDeclaration] (what the courier
/// declared) and [CourierSettlement] (what a manager reviewed), computed
/// once via [CourierSettlementVariance.compute].
///
/// Deliberately its own type rather than reusing `CashVariance` directly
/// — kept separate (though structurally identical) because it describes a
/// different aggregate (a courier's settlement, not a drawer's cash
/// count); `docs/decisions.md` ADR-015 records this as a considered-and-
/// rejected reuse, not an oversight.
class CourierSettlementVariance {
  const CourierSettlementVariance({required this.amount, required this.type});

  /// Always non-negative — the magnitude of the gap. [type] carries the
  /// direction.
  final Money amount;
  final CourierVarianceType type;

  bool get isExact => type == CourierVarianceType.exact;

  /// `declared - expected`: positive means an overage, negative a
  /// shortage, zero an exact match.
  factory CourierSettlementVariance.compute({
    required Money expectedAmount,
    required Money declaredAmount,
  }) {
    final difference = declaredAmount - expectedAmount;
    if (difference.isZero) {
      return CourierSettlementVariance(
        amount: difference,
        type: CourierVarianceType.exact,
      );
    }
    return CourierSettlementVariance(
      amount: difference.isNegative ? -difference : difference,
      type: difference.isNegative
          ? CourierVarianceType.short
          : CourierVarianceType.over,
    );
  }
}
