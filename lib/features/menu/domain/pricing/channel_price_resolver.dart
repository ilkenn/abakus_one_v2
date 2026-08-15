import '../../../../core/errors/business_rule_violation.dart';
import '../../../../shared/models/money.dart';
import '../../../orders/domain/models/order_channel.dart';
import '../models/menu_product.dart';
import 'channel_price_rule.dart';
import 'channel_pricing_policy.dart';

/// Resolves the final, channel-adjusted unit price a customer is charged
/// for one product — the one place `MenuProduct.basePrice`/a Bowl Builder
/// ingredient sum and a [ChannelPricingPolicy] combine into a single
/// [Money]. Pure and synchronous: every input is already resolved (a live
/// policy snapshot, not a repository), matching `PriceCalculator`'s "given
/// already-resolved Money, compute deterministically" shape.
///
/// **Not authoritative** — same caveat as `PriceCalculator`'s own doc
/// comment: this exists for immediate client-side pricing (menu display,
/// cart, checkout preview); nothing here is claimed to be server-enforced
/// yet (`docs/business_rules.md` BR-PRICE-002).
///
/// **Snapshot discipline**: every value this returns is meant to be read
/// once and frozen into an `OrderLine.unitPrice` at cart-to-order mapping
/// time (`CartLineMapper`) — like every other price in this codebase, a
/// later change to `MenuProduct.basePrice` or the policy must never
/// retroactively alter an already-placed order. This resolver has no
/// notion of "already placed" itself; it is the caller's job to call it
/// once, at submission time, never to re-resolve against a live order.
abstract final class ChannelPriceResolver {
  ChannelPriceResolver._();

  /// The channel-adjusted unit price for [product] in [categoryId] on
  /// [channel], per [policy].
  ///
  /// Resolution order: [product]'s own `MenuProduct.channelPriceOverrides`
  /// entry for [channel] (if any) wins outright — [ChannelExplicitPrice]
  /// replaces the price entirely, [ChannelFixedAdjustment] adds to
  /// `basePrice`, [UseChannelDefault] (or no entry at all) falls through to
  /// [policy]'s category override, then its channel default, then zero.
  ///
  /// Throws [NegativeAmountViolation] if the resolved price would be
  /// negative (a misconfigured explicit price or adjustment) — matches
  /// every other price-computing type in this codebase never producing a
  /// silently-clamped negative amount.
  static Money resolveProductUnitPrice({
    required MenuProduct product,
    required String categoryId,
    required OrderChannel channel,
    required ChannelPricingPolicy policy,
  }) {
    final baseline = Money.fromLegacyDoubleTry(product.basePrice);
    final override = product.channelPriceOverrides[channel];

    final resolved = switch (override) {
      ChannelExplicitPrice(:final price) => price,
      ChannelFixedAdjustment(:final adjustment) => baseline + adjustment,
      UseChannelDefault() ||
      null =>
        baseline + policy.adjustmentFor(channel, categoryId, baseline.currency),
    };

    _requireNonNegative(resolved, context: 'ChannelPriceResolver.product');
    return resolved;
  }

  /// The channel-adjusted unit price for one Bowl Builder bowl, given the
  /// already-summed [ingredientTotal] (`bowlBuilderTotalPriceProvider`'s
  /// value) — applied **once per bowl**, never per ingredient. Bowl Builder
  /// has no `MenuProduct`/category of its own (see
  /// `BowlBuilderIngredient`'s doc comment on why it's a separate model),
  /// so there is no product-level override or category lookup here — only
  /// [policy]'s channel-wide default applies, the same default every
  /// non-drink product falls back to.
  ///
  /// The caller multiplies the returned unit price by the bowl's own order
  /// quantity exactly as it already does today (`CartItem.totalRowPrice`/
  /// `OrderLine.create`'s `(unitPrice + modifierTotal) * quantity`) — this
  /// method never multiplies by quantity itself, so 2 bowls apply this
  /// adjustment twice automatically, with no extra logic.
  ///
  /// Throws [NegativeAmountViolation] under the same rule as
  /// [resolveProductUnitPrice].
  static Money resolveBowlUnitPrice({
    required Money ingredientTotal,
    required OrderChannel channel,
    required ChannelPricingPolicy policy,
  }) {
    final resolved = ingredientTotal +
        policy.defaultAdjustmentFor(channel, ingredientTotal.currency);
    _requireNonNegative(resolved, context: 'ChannelPriceResolver.bowl');
    return resolved;
  }

  static void _requireNonNegative(Money amount, {required String context}) {
    if (amount.isNegative) {
      throw NegativeAmountViolation(
        context: context,
        minorUnits: amount.minorUnits,
        currencyCode: amount.currency.isoCode,
      );
    }
  }
}
