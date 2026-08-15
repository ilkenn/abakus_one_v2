import '../../../../shared/models/currency.dart';
import '../../../../shared/models/money.dart';
import '../../../orders/domain/models/order_channel.dart';
import 'channel_pricing_policy.dart';

/// The LOCKED Paket Servis (delivery) pricing rule — Faz P.1
/// (`docs/business_rules.md`): every product defaults to +140 TL on
/// [OrderChannel.delivery]; İçecekler (`cat_icecekler`) is the one
/// category override, at +20 TL. Build Your Own Bowl gets the same +140
/// TL exactly once per bowl unit, never per ingredient — a direct
/// consequence of reusing `ChannelPriceResolver.resolveBowlUnitPrice`'s
/// existing once-per-bowl design unmodified, not a special case coded
/// here.
///
/// **Deliberately kept separate from, and never wired into,
/// `InMemoryChannelPricingPolicyRepository`/
/// `channelPricingPolicySnapshotProvider`** — see that repository's own
/// doc comment for why: [OrderChannel.delivery] is this app's existing
/// *default* shopping channel, and at least one live screen
/// (`bowl_builder_screen.dart`) resolves a channel price with no
/// takeaway-only gate, so seeding the shared/live repository would have
/// silently changed a real customer-facing price today — exactly what
/// Faz P.1 forbids. This constant exists purely as: (a) proof, via tests
/// against the same [ChannelPriceResolver] every other channel uses, that
/// the pricing *engine* already correctly implements this rule with zero
/// code changes; and (b) the value a future phase (P.4, once real
/// delivery checkout is approved) wires into the live provider chain.
abstract final class DeliveryChannelPricingPolicy {
  DeliveryChannelPricingPolicy._();

  static final ChannelPricingPolicy value = ChannelPricingPolicy(
    channelDefaultAdjustments: {
      OrderChannel.delivery: Money.fromWhole(140, Currency.tryLira),
    },
    categoryOverrides: {
      OrderChannel.delivery: {
        'cat_icecekler': Money.fromWhole(20, Currency.tryLira),
      },
    },
  );
}
