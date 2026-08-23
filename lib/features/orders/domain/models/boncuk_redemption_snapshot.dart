/// An immutable, server-computed snapshot of a Boncuk redemption applied to
/// a takeaway order at submission time — Boncuk Loyalty Program P4-E-B
/// (2026-08-22), mirroring `functions/src/submitTakeawayOrder.ts`'s own
/// `boncukRedemption` order-document field-for-field. **Settlement, never a
/// discount** (`BR-LOYALTY-019`): `Order.pricing.discount`/`grandTotal` are
/// completely untouched by this snapshot — it records how part of that
/// SAME, unchanged total was paid, not a price reduction.
///
/// Meaningful only when `Order.selectedBenefitType ==
/// OrderBenefitType.boncukRedemption`; `null` for every other order,
/// including every pre-P4-E-B order (a purely additive field — backward
/// compatible with every order document written before it existed).
///
/// Never constructed from local/client state — the only real source of an
/// instance is [OrderFirestoreMapper.fromFirestore] parsing a genuine
/// server-written order document. The pre-submit checkout UI's own
/// non-authoritative Boncuk estimate is a completely separate,
/// presentation-only computation that never produces this type — see
/// `TakeawayCheckoutScreen`'s own local selection state.
class BoncukRedemptionSnapshot {
  const BoncukRedemptionSnapshot({
    required this.boncukUsed,
    required this.valueMinorUnits,
    required this.remainingPayableMinorUnits,
    required this.redemptionValueMinorUnitsPerBoncuk,
    required this.maxRedemptionBasisPoints,
    required this.loyaltyPolicyVersion,
  });

  /// Whole Boncuk actually debited for this order — server-confirmed, the
  /// authoritative count (never re-derived from any pre-submit estimate).
  final int boncukUsed;

  /// [boncukUsed]'s monetary value in kuruş, at the redemption rate active
  /// when this order was created — [redemptionValueMinorUnitsPerBoncuk]
  /// below is that same rate, snapshotted for audit/display, never
  /// re-resolved from a live policy later.
  final int valueMinorUnits;

  /// `Order.pricing.grandTotal.minorUnits - valueMinorUnits` — the actual
  /// remaining amount payable by cash/card, server-computed at submission
  /// time.
  final int remainingPayableMinorUnits;

  /// The organization's redemption rate at submission time (kuruş per
  /// Boncuk) — display/audit provenance only, never re-applied to compute
  /// anything client-side after the fact.
  final int redemptionValueMinorUnitsPerBoncuk;

  /// The maximum share of the order (basis points) Boncuk was allowed to
  /// cover, at submission time — display/audit provenance only.
  final int maxRedemptionBasisPoints;

  /// The `loyaltyPolicies/{organizationId}.version` active when this
  /// redemption was applied — audit provenance only, mirrors
  /// `functions/src/loyaltyLedger.ts`'s own `loyaltyPolicyVersion`
  /// provenance field.
  final int loyaltyPolicyVersion;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is BoncukRedemptionSnapshot &&
            other.boncukUsed == boncukUsed &&
            other.valueMinorUnits == valueMinorUnits &&
            other.remainingPayableMinorUnits == remainingPayableMinorUnits &&
            other.redemptionValueMinorUnitsPerBoncuk ==
                redemptionValueMinorUnitsPerBoncuk &&
            other.maxRedemptionBasisPoints == maxRedemptionBasisPoints &&
            other.loyaltyPolicyVersion == loyaltyPolicyVersion);
  }

  @override
  int get hashCode => Object.hash(
        boncukUsed,
        valueMinorUnits,
        remainingPayableMinorUnits,
        redemptionValueMinorUnitsPerBoncuk,
        maxRedemptionBasisPoints,
        loyaltyPolicyVersion,
      );
}
