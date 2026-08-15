import '../../../shared/models/currency.dart';
import '../../../shared/models/money.dart';
import '../../orders/domain/models/order_channel.dart';
import '../domain/pricing/channel_pricing_policy.dart';

/// Admin-editable storage for the channel/category price-adjustment rules
/// `ChannelPriceResolver` reads — the future "yönetim panelinden kategori
/// ve ürün bazında fiyat farkı değiştirme" screen's data layer. No UI reads
/// or writes this yet (out of this sprint's scope); only the in-memory
/// seed below does, standing in for that screen's future defaults.
///
/// Mirrors `ChannelOperationPolicyRepository`'s shape: a repository over a
/// small, admin-configurable ruleset, not a single hardcoded constant — see
/// that type's own doc comment for the same reasoning. Deliberately
/// generic over every `OrderChannel`, not just `takeaway`: a future
/// delivery/marketplace channel price rule is a `setChannelDefaultAdjustment`/
/// `setCategoryOverride` call against this same interface, not a new type.
abstract interface class ChannelPricingPolicyRepository {
  /// The full current policy — read once by a caller (e.g.
  /// `ChannelPriceResolver`) rather than queried field-by-field, so one
  /// resolution pass is consistent even if this repository is mutated
  /// concurrently.
  Future<ChannelPricingPolicy> current();

  Future<void> setChannelDefaultAdjustment(
    OrderChannel channel,
    Money adjustment,
  );

  Future<void> setCategoryOverride(
    OrderChannel channel,
    String categoryId,
    Money adjustment,
  );

  Future<void> clearCategoryOverride(OrderChannel channel, String categoryId);
}

/// Today's only implementation — in-memory, seeded with the approved Gel Al
/// rule (`docs/business_rules.md` BR-PRICE-004, superseding BR-PRICE-001/
/// DL-002 for the takeaway channel specifically): every product defaults to
/// +20 TL on [OrderChannel.takeaway]; İçecekler (`cat_icecekler`) is the one
/// category override, at +0 TL. No other channel has a configured default —
/// dine-in/delivery/reservation resolve to a zero adjustment (unchanged
/// pricing) until a policy is explicitly set for them.
///
/// **Deliberately not seeded with the LOCKED Faz P.1 delivery pricing rule
/// (+140 TL / +20 TL beverage) despite that rule being approved** — this
/// repository backs `channelPricingPolicySnapshotProvider`, which
/// `bowl_builder_screen.dart` reads unconditionally for whatever channel
/// `shoppingChannelProvider` is currently set to, with **no**
/// takeaway-only gate (unlike `resolveDisplayPrice`, which does gate on
/// [OrderChannel.takeaway]). [OrderChannel.delivery] is this app's
/// existing *default* shopping channel
/// (`ShoppingChannelContext.delivery()`'s own doc comment) — so adding a
/// delivery entry here would have live-changed Bowl Builder's
/// customer-facing price today, violating Faz P.1's explicit "do not
/// start real delivery checkout" constraint. The approved delivery
/// pricing values live instead as an isolated, unwired constant —
/// `DeliveryChannelPricingPolicy.value`
/// (`../domain/pricing/delivery_channel_pricing_policy.dart`) — proven
/// correct by tests against the same `ChannelPriceResolver`, ready for a
/// future phase to wire into checkout once real delivery ordering exists.
class InMemoryChannelPricingPolicyRepository
    implements ChannelPricingPolicyRepository {
  InMemoryChannelPricingPolicyRepository()
      : _channelDefaults = {
          OrderChannel.takeaway: Money.fromWhole(20, Currency.tryLira),
        },
        _categoryOverrides = {
          OrderChannel.takeaway: {
            'cat_icecekler': Money.zero(Currency.tryLira),
          },
        };

  final Map<OrderChannel, Money> _channelDefaults;
  final Map<OrderChannel, Map<String, Money>> _categoryOverrides;

  @override
  Future<ChannelPricingPolicy> current() async {
    return ChannelPricingPolicy(
      channelDefaultAdjustments: Map.unmodifiable(_channelDefaults),
      categoryOverrides: {
        for (final entry in _categoryOverrides.entries)
          entry.key: Map.unmodifiable(entry.value),
      },
    );
  }

  @override
  Future<void> setChannelDefaultAdjustment(
    OrderChannel channel,
    Money adjustment,
  ) async {
    _channelDefaults[channel] = adjustment;
  }

  @override
  Future<void> setCategoryOverride(
    OrderChannel channel,
    String categoryId,
    Money adjustment,
  ) async {
    _categoryOverrides.putIfAbsent(channel, () => {})[categoryId] = adjustment;
  }

  @override
  Future<void> clearCategoryOverride(
    OrderChannel channel,
    String categoryId,
  ) async {
    _categoryOverrides[channel]?.remove(categoryId);
  }
}
