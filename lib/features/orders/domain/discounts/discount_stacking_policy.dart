import '../../../../core/errors/business_rule_violation.dart';
import 'discount.dart';

/// Decides which of several candidate order-level [Discount]s (a coupon, a
/// Boncuk redemption, a campaign, ...) may actually apply together to one
/// order.
///
/// **Abstraction only, per explicit sprint scope** — no real stacking rule
/// is implemented. `docs/business_rules.md` BR-PROMO-003 (coupon + Boncuk),
/// BR-PROMO-004 (multiple discounts/campaigns), and BR-PROMO-005 (campaign
/// eligibility scope) are all UNRESOLVED; this interface exists so
/// `PriceCalculator`/`CartToOrderMapper` have one seam to depend on
/// without guessing an answer to any of them.
abstract interface class DiscountStackingPolicy {
  /// Returns the subset/ordering of [candidates] this policy allows to
  /// apply together. May throw a [BusinessRuleViolation] if [candidates]
  /// is not a combination this policy accepts.
  List<Discount> resolve(List<Discount> candidates);
}

/// The only [DiscountStackingPolicy] implemented this sprint: refuses more
/// than one order-level discount outright, rather than silently guessing a
/// stacking rule that hasn't been decided. Zero or one discount passes
/// through unchanged.
class SingleDiscountOnlyPolicy implements DiscountStackingPolicy {
  const SingleDiscountOnlyPolicy();

  @override
  List<Discount> resolve(List<Discount> candidates) {
    if (candidates.length > 1) {
      throw MultipleDiscountsNotSupportedViolation(
        discountCount: candidates.length,
      );
    }
    return candidates;
  }
}
