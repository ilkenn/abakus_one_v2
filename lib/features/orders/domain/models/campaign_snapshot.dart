import '../../../campaigns/domain/models/campaign.dart';

/// An immutable, server-computed snapshot of a Campaign redemption applied
/// to a takeaway order at submission time — Server-Authoritative Campaign
/// Engine P8-C (2026-08-25), mirroring
/// `functions/src/campaignEngine.ts`'s own `CampaignOrderSnapshot`
/// field-for-field.
///
/// **A genuine price discount, not a settlement layered on top of an
/// unchanged total** — the same relationship `CatalogRewardSnapshot` has
/// with `Order.pricing`: the discounted line(s)' own price is genuinely
/// reduced before `Order.pricing.discount`/`grandTotal` are computed. This
/// snapshot is a read-only AUDIT record of what was applied and why the
/// total is what it is, never a second, independently-applied discount —
/// and it is why Boncuk earning is computed from the POST-campaign
/// `grandTotal`, with no separate campaign-specific subtraction.
///
/// Meaningful only when `Order.selectedBenefitType ==
/// OrderBenefitType.campaign`; `null` for every other order, including
/// every pre-P8-C order (a purely additive field). Never constructed from
/// local/client state — the only real source of an instance is
/// `OrderFirestoreMapper.fromFirestore` parsing a genuine server-written
/// order document. A historical order reconstructs its campaign entirely
/// from this frozen snapshot — it never re-reads the live `campaigns/
/// {campaignId}` document, so a later live edit (even a version bump) never
/// rewrites what an already-placed order shows.
class CampaignSnapshot {
  const CampaignSnapshot({
    required this.campaignId,
    required this.campaignVersion,
    required this.title,
    required this.campaignType,
    required this.appliedRule,
    required this.appliedValue,
    required this.discountMinorUnits,
    required this.orderChannel,
  });

  /// The campaign's stable identifier — server-resolved, never client-chosen
  /// beyond selecting which campaign to request.
  final String campaignId;

  /// The exact immutable campaign version this redemption used — audit
  /// provenance, never re-resolved from the LIVE (possibly since-edited)
  /// campaign definition.
  final int campaignVersion;

  /// The campaign's title at the time it was applied — copied verbatim, so
  /// a later rename never rewrites history.
  final String title;

  /// `"percentageDiscount" | "fixedAmountDiscount" | "freeProduct" |
  /// "buyXGetY" | "productDiscount" | "categoryDiscount"` — deliberately an
  /// opaque string, never a Dart enum, mirroring [Campaign.campaignType]'s
  /// own "never hardcode the vocabulary client-side" rule.
  final String campaignType;

  /// The exact rule that was actually applied — frozen at redemption time,
  /// never re-resolved from the live campaign.
  final CampaignRule appliedRule;

  /// The mechanic-specific resolved value the discount was computed
  /// from — a percentage's basis points, a fixed amount's minor units, or a
  /// free-unit/free-product count, depending on `appliedRule.mechanic`.
  final int appliedValue;

  /// The exact total discount this campaign applied, in minor units
  /// (kuruş) — always equal to `Order.pricing.discount.minorUnits` for a
  /// campaign-benefit order (there is never a second, hidden discount).
  final int discountMinorUnits;

  /// `"takeaway"` today — the commercial channel this campaign was
  /// evaluated and applied against, server-derived, never client-supplied.
  final String orderChannel;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is CampaignSnapshot &&
            other.campaignId == campaignId &&
            other.campaignVersion == campaignVersion &&
            other.title == title &&
            other.campaignType == campaignType &&
            other.appliedValue == appliedValue &&
            other.discountMinorUnits == discountMinorUnits &&
            other.orderChannel == orderChannel);
  }

  @override
  int get hashCode => Object.hash(
        campaignId,
        campaignVersion,
        title,
        campaignType,
        appliedValue,
        discountMinorUnits,
        orderChannel,
      );
}
