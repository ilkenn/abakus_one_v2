/// The kind of reward a [VisitRewardRule] grants — Sprint 5D's Visit
/// Rewards Engine. Closed enum, extended additively as new reward types
/// are approved ("future reward types supported" — the same convention
/// every other taxonomy in this codebase follows).
enum RewardType {
  loyaltyPoints,
  coupon,
  freeProduct,
  freeDrink,
  dessert,
  upgrade,
  campaign,
}
