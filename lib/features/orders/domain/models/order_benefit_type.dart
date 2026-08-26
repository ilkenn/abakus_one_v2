/// The customer-safe, closed representation of which single benefit (if
/// any) an order settled part of its total with — Boncuk Loyalty Program
/// P4-E-B (2026-08-22), mirroring `functions/src/submitTakeawayOrder.ts`'s
/// own `selectedBenefitType` server contract field-for-field. **Only
/// `none`/`boncukRedemption`/`catalogReward` are real; nothing else is
/// ever produced by any writer today** — coupon/campaign benefit types
/// have no backend authority yet (`docs/business_rules.md`
/// `BR-LOYALTY-022`'s own disclosed scope). A future benefit type must stay
/// parse-safe (see [orderBenefitTypeFromWire]) without this enum ever
/// pretending to support one before its own backend exists.
///
/// **Boncuk Loyalty P7-C (2026-08-24) — `catalogReward` added.** Real for
/// the takeaway channel only this phase (`submitTakeawayOrder.ts`); every
/// other channel still only ever produces `none`/`boncukRedemption`.
///
/// **Server-Authoritative Campaign Engine P8-C (2026-08-25) — `campaign`
/// added.** Real for the takeaway channel only this phase
/// (`submitTakeawayOrder.ts`); every other channel still only ever produces
/// `none`/`boncukRedemption`/`catalogReward`. Unlike `boncukRedemption`, a
/// campaign is a genuine price discount (see [CampaignSnapshot]'s own doc
/// comment) — the same "already-applied reduction, not a settlement"
/// relationship `catalogReward` already has with [Order.pricing].
enum OrderBenefitType { none, boncukRedemption, catalogReward, campaign }

/// Parses `Order.selectedBenefitType`'s wire value.
///
/// Deliberately **not** the strict `EnumType.values.byName(...)`
/// fail-fast-on-unknown discipline this mapper otherwise uses for closed
/// state-machine fields (`status`/`channel`) — a genuinely unknown or
/// future value here degrades to [OrderBenefitType.none] rather than
/// throwing, so an old client build reading an order written by a NEWER
/// backend release (a future benefit type this build doesn't understand
/// yet) never crashes reading order history; it simply shows no benefit,
/// never fabricated or wrong information. Absent/`null` (every
/// pre-P4-E-B order) also resolves to [OrderBenefitType.none].
OrderBenefitType orderBenefitTypeFromWire(String? raw) {
  switch (raw) {
    case 'boncukRedemption':
      return OrderBenefitType.boncukRedemption;
    case 'catalogReward':
      return OrderBenefitType.catalogReward;
    case 'campaign':
      return OrderBenefitType.campaign;
    default:
      return OrderBenefitType.none;
  }
}

/// The inverse of [orderBenefitTypeFromWire] — used only where this
/// codebase ever needs to round-trip a value back to Firestore's own wire
/// shape (none today; reserved for symmetry/testability).
String orderBenefitTypeToWire(OrderBenefitType value) {
  switch (value) {
    case OrderBenefitType.boncukRedemption:
      return 'boncukRedemption';
    case OrderBenefitType.catalogReward:
      return 'catalogReward';
    case OrderBenefitType.campaign:
      return 'campaign';
    case OrderBenefitType.none:
      return 'none';
  }
}
