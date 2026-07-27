import '../../../../shared/models/money.dart';
import 'tax_rate.dart';

/// The VAT breakdown frozen onto one [OrderLine] at order-creation time.
///
/// Bundled as one value object (rather than three loose fields on
/// [OrderLine]) for the same reason `OrderCancellationInfo` bundles
/// reason/actor/timestamp: [rate], [taxableBase], and [vatAmount] must
/// never independently disagree — a line either has one complete,
/// internally-consistent snapshot or none.
class TaxSnapshot {
  const TaxSnapshot({
    required this.rate,
    required this.taxableBase,
    required this.vatAmount,
  });

  /// Builds a [TaxSnapshot] for a VAT-inclusive [grossAmount] under
  /// [rate] — the only place `TaxRate.vatAmountOf`/`taxableBaseOf` are
  /// called together, so the two always come from the same [grossAmount]
  /// and [rate].
  factory TaxSnapshot.fromGrossAmount(Money grossAmount, TaxRate rate) {
    return TaxSnapshot(
      rate: rate,
      taxableBase: rate.taxableBaseOf(grossAmount),
      vatAmount: rate.vatAmountOf(grossAmount),
    );
  }

  /// The VAT rate applied — frozen at the value it had when this snapshot
  /// was built, independent of `TaxPolicy.defaultRate` afterward.
  final TaxRate rate;

  /// The line's gross amount minus [vatAmount].
  final Money taxableBase;

  /// The VAT portion of the line's gross amount.
  final Money vatAmount;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is TaxSnapshot &&
            other.rate == rate &&
            other.taxableBase == taxableBase &&
            other.vatAmount == vatAmount);
  }

  @override
  int get hashCode => Object.hash(rate, taxableBase, vatAmount);
}
