import '../../../../core/errors/business_rule_violation.dart';
import '../../../../shared/models/currency.dart';
import '../../../../shared/models/money.dart';
import '../models/order_line.dart';
import 'price_breakdown.dart';

/// Deterministically computes a [PriceBreakdown] from a set of
/// [OrderLine]s plus order-level adjustments.
///
/// **Not authoritative.** Per `docs/domain_architecture.md`'s "money math
/// never lives on the mobile client" principle and the already-DECIDED
/// `docs/business_rules.md` BR-PRICE-002 ("server-authoritative pricing...
/// enforcement is ROADMAP, no backend exists"), this calculator exists for
/// immediate client-side feedback and offline POS order-taking (see
/// `docs/module_catalog.md`'s POS offline requirement) — every total it
/// produces must still be independently confirmed server-side once a
/// backend exists. Nothing in this codebase currently treats its output as
/// final.
abstract final class PriceCalculator {
  PriceCalculator._();

  /// Throws [NegativeAmountViolation] if [discount]/[serviceFee]/
  /// [deliveryFee]/[packagingFee]/[tip] is negative, or
  /// [NegativeTotalViolation] if the resulting grand total would be
  /// negative. Throws [CurrencyMismatchViolation] if [lines] and the
  /// supplied adjustments don't all share [currency].
  static PriceBreakdown calculate({
    required List<OrderLine> lines,
    required Currency currency,
    Money? discount,
    Money? serviceFee,
    Money? deliveryFee,
    Money? packagingFee,
    Money? tip,
  }) {
    final zero = Money.zero(currency);
    final resolvedDiscount = discount ?? zero;
    final resolvedServiceFee = serviceFee ?? zero;
    final resolvedDeliveryFee = deliveryFee ?? zero;
    final resolvedPackagingFee = packagingFee ?? zero;
    final resolvedTip = tip ?? zero;

    for (final entry in {
      'discount': resolvedDiscount,
      'serviceFee': resolvedServiceFee,
      'deliveryFee': resolvedDeliveryFee,
      'packagingFee': resolvedPackagingFee,
      'tip': resolvedTip,
    }.entries) {
      if (entry.value.isNegative) {
        throw NegativeAmountViolation(
          context: entry.key,
          minorUnits: entry.value.minorUnits,
          currencyCode: entry.value.currency.isoCode,
        );
      }
    }

    var grossSubtotal = zero;
    var taxableBase = zero;
    var vatAmount = zero;
    for (final line in lines) {
      grossSubtotal = grossSubtotal + line.lineTotal;
      taxableBase = taxableBase + line.tax.taxableBase;
      vatAmount = vatAmount + line.tax.vatAmount;
    }

    final grandTotal = grossSubtotal -
        resolvedDiscount +
        resolvedServiceFee +
        resolvedDeliveryFee +
        resolvedPackagingFee +
        resolvedTip;
    if (grandTotal.isNegative) {
      throw NegativeTotalViolation(
        minorUnits: grandTotal.minorUnits,
        currencyCode: grandTotal.currency.isoCode,
      );
    }

    return PriceBreakdown(
      grossSubtotal: grossSubtotal,
      discount: resolvedDiscount,
      taxableBase: taxableBase,
      vatAmount: vatAmount,
      serviceFee: resolvedServiceFee,
      deliveryFee: resolvedDeliveryFee,
      packagingFee: resolvedPackagingFee,
      tip: resolvedTip,
      grandTotal: grandTotal,
    );
  }
}
