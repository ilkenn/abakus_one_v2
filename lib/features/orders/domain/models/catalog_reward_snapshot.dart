/// An immutable, server-computed snapshot of a Reward Catalog redemption
/// applied to a takeaway order at submission time — Boncuk Loyalty
/// Program P7-C (2026-08-24), mirroring
/// `functions/src/submitTakeawayOrder.ts`'s own `catalogReward`
/// order-document field-for-field.
///
/// **Unlike [BoncukRedemptionSnapshot], this is not a settlement layered
/// on top of an unchanged total** — the rewarded product line's own price
/// is genuinely reduced (`Order.lines[i].lineDiscount`), and
/// `Order.pricing.grossSubtotal`/`grandTotal` already reflect that
/// reduction. This snapshot is a read-only AUDIT record of what was
/// redeemed and why the total is what it is, never a second,
/// independently-applied discount.
///
/// Meaningful only when `Order.selectedBenefitType ==
/// OrderBenefitType.catalogReward`; `null` for every other order,
/// including every pre-P7-C order (a purely additive field). Never
/// constructed from local/client state — the only real source of an
/// instance is [OrderFirestoreMapper.fromFirestore] parsing a genuine
/// server-written order document.
class CatalogRewardSnapshot {
  const CatalogRewardSnapshot({
    required this.rewardId,
    required this.rewardVersion,
    required this.title,
    required this.boncukCost,
    required this.redeemedProductId,
    required this.redeemedQuantity,
    required this.coveredValueMinorUnits,
    required this.rewardCatalogVersionId,
  });

  /// The reward's stable identifier — server-resolved, never client-chosen
  /// beyond selecting which reward to request.
  final String rewardId;

  /// The exact immutable `loyaltyRewardCatalogVersions` version this
  /// redemption used — audit provenance, never re-resolved from the LIVE
  /// (possibly since-edited) reward definition.
  final int rewardVersion;

  /// The reward's title at the time it was redeemed — copied verbatim from
  /// that version, so a later rename never rewrites history.
  final String title;

  /// Whole Boncuk actually debited for this reward — server-confirmed.
  final int boncukCost;

  /// The canonical `menuProducts` id of the ONE cart line the reward was
  /// applied to.
  final String redeemedProductId;

  /// Always exactly `1` this phase — only one product unit is ever
  /// redeemed per catalog reward, regardless of that line's own cart
  /// quantity.
  final int redeemedQuantity;

  /// The TL (kuruş) value of the one covered unit — the exact amount by
  /// which the rewarded line's own price was reduced (base price +
  /// per-unit modifiers, already channel-adjusted).
  final int coveredValueMinorUnits;

  /// `loyaltyRewardCatalogVersions/{rewardId}_{rewardVersion}`'s own
  /// document id — audit/traceability provenance only.
  final String rewardCatalogVersionId;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is CatalogRewardSnapshot &&
            other.rewardId == rewardId &&
            other.rewardVersion == rewardVersion &&
            other.title == title &&
            other.boncukCost == boncukCost &&
            other.redeemedProductId == redeemedProductId &&
            other.redeemedQuantity == redeemedQuantity &&
            other.coveredValueMinorUnits == coveredValueMinorUnits &&
            other.rewardCatalogVersionId == rewardCatalogVersionId);
  }

  @override
  int get hashCode => Object.hash(
        rewardId,
        rewardVersion,
        title,
        boncukCost,
        redeemedProductId,
        redeemedQuantity,
        coveredValueMinorUnits,
        rewardCatalogVersionId,
      );
}
