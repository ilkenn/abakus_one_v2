import 'currency.dart';
import 'money.dart';

/// The one configured constant behind the approved multi-currency payment
/// decision's business acceptance rate: `acceptanceRate = marketSellingRate
/// - fixedMargin`. This is the only place `5.00 TRY` appears — every other
/// file that needs the margin reads [fixedMargin], mirroring how
/// `TaxPolicy.defaultRate` is the one place the VAT rate's `10%` appears.
abstract final class ExchangeRatePolicy {
  ExchangeRatePolicy._();

  static final Money fixedMargin = Money.fromWhole(5, Currency.tryLira);
}
