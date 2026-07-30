import '../../../../shared/models/money.dart';

/// The small, per-[RewardType] configuration payload a [VisitRewardRule]
/// carries — a flat, all-nullable shape (mirrors
/// `DispatchScoringInput`'s own flat-config style) rather than a sealed
/// hierarchy, since every field here is optional display/redemption
/// detail, not a branching business rule. Which field is meaningful
/// depends on the rule's own `RewardType`:
/// [RewardType.loyaltyPoints] → [pointsAmount],
/// [RewardType.coupon] → [couponDiscount] (a real [Money] value, never a
/// raw `double` — `CLAUDE.md` §4), [RewardType.freeProduct]/
/// [RewardType.freeDrink]/[RewardType.dessert]/[RewardType.upgrade] →
/// [productId]/[description], [RewardType.campaign] → [campaignId]
/// (references the existing `CampaignModel.id`, never a duplicate record).
class VisitRewardConfig {
  const VisitRewardConfig({
    this.pointsAmount,
    this.couponDiscount,
    this.productId,
    this.description,
    this.campaignId,
  });

  final int? pointsAmount;
  final Money? couponDiscount;
  final String? productId;
  final String? description;
  final String? campaignId;
}
