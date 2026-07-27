import 'tax_rate.dart';

/// The one configured place the default VAT rate's `10` appears anywhere
/// in this codebase. Every other file that needs "the default VAT rate"
/// reads [defaultRate] — never a literal `10`/`1000`.
///
/// [defaultRate] is what a new [OrderLine]'s [TaxSnapshot] is built from
/// at order-creation time — see `CartToOrderMapper`. Once frozen onto a
/// line, a later change to [defaultRate] never alters that line: this
/// class is only ever consulted when a *new* order is created, matching
/// the approved requirement that historical orders remain unchanged if
/// the default rate changes later.
abstract final class TaxPolicy {
  TaxPolicy._();

  static const TaxRate defaultRate = TaxRate.fromBasisPoints(1000);
}
