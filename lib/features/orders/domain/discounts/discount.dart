import '../../../../shared/models/money.dart';

/// How a [Discount]'s value is expressed.
enum DiscountType { fixedAmount, percentage }

/// What a [Discount] reduces.
enum DiscountScope { line, order }

/// A single discount value object — a fixed TRY amount or a percentage,
/// applied at line or order level. **Value object only**: no coupon
/// lookup, eligibility check, or campaign engine exists here or is
/// implied — see `DiscountStackingPolicy` for why more than one
/// `Discount` on an order isn't resolved by this sprint, and
/// `docs/business_rules.md` BR-PROMO-003/004/005 for the still-open
/// business questions (coupon+Boncuk stacking, multi-discount stacking,
/// campaign eligibility scope).
class Discount {
  const Discount.fixedAmount({
    required this.id,
    required this.scope,
    required Money amount,
    this.reason = '',
  })  : type = DiscountType.fixedAmount,
        _fixedAmount = amount,
        _percentageBasisPoints = null;

  /// [percentageBasisPoints]: hundredths of a percent (10.00% = 1000),
  /// matching `TaxRate`'s convention — never a `double` percent.
  const Discount.percentage({
    required this.id,
    required this.scope,
    required int percentageBasisPoints,
    this.reason = '',
  })  : type = DiscountType.percentage,
        _fixedAmount = null,
        _percentageBasisPoints = percentageBasisPoints,
        assert(percentageBasisPoints >= 0 && percentageBasisPoints <= 10000,
            'percentageBasisPoints must be within [0, 10000]');

  final String id;
  final DiscountType type;
  final DiscountScope scope;
  final String reason;

  final Money? _fixedAmount;
  final int? _percentageBasisPoints;

  /// The reduction this discount applies to [base] (a line's gross
  /// subtotal, or an order's gross subtotal, depending on [scope]) —
  /// never more than [base] itself (a discount can't make a line/order
  /// negative on its own; see `PriceCalculator` for the grand-total-level
  /// negative-total check this composes with).
  Money amountFor(Money base) {
    final raw = switch (type) {
      DiscountType.fixedAmount => _fixedAmount!,
      DiscountType.percentage => base.scaledBy(_percentageBasisPoints!, 10000),
    };
    return raw > base ? base : raw;
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is Discount &&
            other.id == id &&
            other.type == type &&
            other.scope == scope &&
            other._fixedAmount == _fixedAmount &&
            other._percentageBasisPoints == _percentageBasisPoints);
  }

  @override
  int get hashCode =>
      Object.hash(id, type, scope, _fixedAmount, _percentageBasisPoints);
}
