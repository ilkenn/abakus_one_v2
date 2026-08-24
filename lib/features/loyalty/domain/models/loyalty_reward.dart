/// A single, currently-redeemable Reward Catalog entry — Boncuk Loyalty
/// Program P7-B/P7-C (2026-08-24), mirroring
/// `functions/src/getCustomerLoyaltyRewardCatalog.ts`'s own sanitized
/// customer DTO field-for-field. Server-authoritative and read-only: the
/// Boncuk cost, title, description, and eligible products are never
/// client-editable, never client-computed, and never sent back to the
/// server verbatim at redemption time — checkout only ever sends
/// [rewardId]; the server re-resolves everything else itself
/// (`submitTakeawayOrder.ts`, P7-C).
class LoyaltyReward {
  const LoyaltyReward({
    required this.rewardId,
    required this.title,
    required this.description,
    required this.rewardType,
    required this.eligibleProductIds,
    required this.boncukCost,
    required this.sortOrder,
    required this.version,
  });

  final String rewardId;
  final String title;
  final String description;

  /// Always `'explicitProductSet'` this phase — see
  /// `functions/src/loyaltyRewardCatalog.ts`'s own doc comment for why
  /// category-based eligibility is deliberately not supported yet.
  final String rewardType;

  /// The canonical `menuProducts` ids this reward can cover — a cart must
  /// contain at least one of these for the reward to be selectable.
  final List<String> eligibleProductIds;

  final int boncukCost;
  final int sortOrder;

  /// The exact reward-catalog version this listing reflects — display/
  /// audit provenance only; never sent back to the server (the server
  /// always re-resolves the CURRENT live version at redemption time).
  final int version;

  bool isEligibleForCart(Iterable<String> cartProductIds) {
    return cartProductIds.any(eligibleProductIds.contains);
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is LoyaltyReward &&
            other.rewardId == rewardId &&
            other.title == title &&
            other.description == description &&
            other.rewardType == rewardType &&
            _listEquals(other.eligibleProductIds, eligibleProductIds) &&
            other.boncukCost == boncukCost &&
            other.sortOrder == sortOrder &&
            other.version == version);
  }

  @override
  int get hashCode => Object.hash(
        rewardId,
        title,
        description,
        rewardType,
        Object.hashAll(eligibleProductIds),
        boncukCost,
        sortOrder,
        version,
      );
}

bool _listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
