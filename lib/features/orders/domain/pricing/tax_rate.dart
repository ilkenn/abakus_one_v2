import '../../../../shared/models/money.dart';
import '../../../../shared/models/money_rounding.dart';

/// A VAT rate, stored as basis points (1 bp = 0.01%) to stay integer-exact
/// — `TaxRate.fromBasisPoints(1000)` is 10.00%. Never a `double` percent.
///
/// Approved architecture decision (Phase 3 Sprint 3A): all menu and sales
/// prices are VAT-**inclusive** (gross). VAT is therefore *extracted* from
/// a gross amount, never added on top:
///
/// ```text
/// vatAmount    = grossAmount * rate / (100 + rate)
/// taxableBase  = grossAmount - vatAmount
/// ```
///
/// expressed here in basis points as
/// `grossMinorUnits * basisPoints / (10000 + basisPoints)`, rounded half
/// away from zero to the nearest minor unit.
class TaxRate {
  const TaxRate.fromBasisPoints(this.basisPoints)
      : assert(basisPoints >= 0, 'basisPoints must not be negative');

  /// The rate in hundredths of a percent (10.00% = 1000).
  final int basisPoints;

  /// The VAT portion of [grossAmount], extracted per this rate — see this
  /// class's own doc comment for the formula. [grossAmount] is assumed
  /// VAT-inclusive.
  Money vatAmountOf(Money grossAmount) {
    final vatMinorUnits = MoneyRounding.halfAwayFromZero(
      grossAmount.minorUnits * basisPoints,
      10000 + basisPoints,
    );
    return Money(vatMinorUnits, grossAmount.currency);
  }

  /// `grossAmount - vatAmountOf(grossAmount)`.
  Money taxableBaseOf(Money grossAmount) {
    return grossAmount - vatAmountOf(grossAmount);
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is TaxRate && other.basisPoints == basisPoints);
  }

  @override
  int get hashCode => basisPoints.hashCode;

  @override
  String toString() {
    final whole = basisPoints ~/ 100;
    final fraction = (basisPoints % 100).toString().padLeft(2, '0');
    return '$whole.$fraction%';
  }
}
