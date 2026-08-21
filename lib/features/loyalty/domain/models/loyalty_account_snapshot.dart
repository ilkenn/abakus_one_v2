/// P3A (2026-08-23) — the customer's real, server-authoritative Boncuk
/// account snapshot, mirroring `getCustomerLoyaltySnapshot.ts`'s exact
/// response contract field-for-field. Deliberately excludes internal
/// accounting provenance (`orderEligibleNetSpendMinorUnits`) the backend
/// itself never returns to a client — see that file's own doc comment.
///
/// **Configurable Loyalty Economics (2026-08-24)**: `earningSpendMinorUnits`/
/// `earningBoncukAmount`/`redemptionValueMinorUnitsPerBoncuk`/
/// `maxRedemptionBasisPoints` are now real, server-resolved INSTANCE fields
/// — the organization's current active `loyaltyPolicies` document, sanitized
/// and returned alongside the balance by the same `getCustomerLoyaltySnapshot`
/// call. They are deliberately no longer Flutter-side `static const`
/// values: Boncuk economics are configurable per organization server-side
/// (`functions/src/loyaltyPolicy.ts`), so a permanent Dart constant would
/// silently go stale exactly the way the previous rate change already
/// exposed. The customer app never computes or chooses these values — it
/// only ever renders whatever the server most recently returned.
///
/// **Same-day correction (2026-08-24) — exact-ratio economics, no derived
/// per-Boncuk rate.** The backend's divisibility constraint on
/// `earningSpendMinorUnits`/`earningBoncukAmount` was removed (a ratio like
/// `5000 minor units → 3 Boncuk` is now genuinely supported, exact,
/// non-integer-reducible economics — see `functions/src/loyaltyPolicy.ts`).
/// A Dart-side `earningRateMinorUnitsPerBoncuk = earningSpendMinorUnits ~/
/// earningBoncukAmount` getter would silently floor-truncate for such a
/// ratio and render the wrong "block size." `minorUnitsUntilNextBoncuk` is
/// therefore now a real, required field populated directly from the
/// server's own exact-ratio computation
/// (`getCustomerLoyaltySnapshot.ts`'s `computeEarningProgress`), never
/// derived client-side.
class LoyaltyAccountSnapshot {
  const LoyaltyAccountSnapshot({
    required this.spendableBalance,
    required this.boncukDebt,
    required this.earningRemainderMinorUnits,
    required this.minorUnitsUntilNextBoncuk,
    required this.lifetimeEarned,
    required this.lifetimeRedeemed,
    required this.earningSpendMinorUnits,
    required this.earningBoncukAmount,
    required this.redemptionValueMinorUnitsPerBoncuk,
    required this.maxRedemptionBasisPoints,
  });

  /// Whole Boncuk the customer can spend right now. Never negative —
  /// BR-LOYALTY-014 guarantees this server-side.
  final int spendableBalance;

  /// Whole Boncuk currently owed back from a prior refund clawback that
  /// exceeded spendable balance at the time — BR-LOYALTY-014. Future
  /// earning pays this down before any of it becomes spendable. Never
  /// negative.
  final int boncukDebt;

  /// Kuruş (minor units) of eligible net spend already accumulated toward
  /// the next whole Boncuk, under the CURRENT block. `earningRemainderMinorUnits
  /// + minorUnitsUntilNextBoncuk` is that block's actual size — constant for
  /// an evenly-reducible ratio, but may vary slightly block-to-block for a
  /// non-integer-reducible ratio (e.g. 5000 → 3); this is mathematically
  /// exact, not an approximation.
  final int earningRemainderMinorUnits;

  /// Kuruş still needed to earn the next whole Boncuk — server-computed
  /// exact-ratio value, never derived from a per-Boncuk rate client-side.
  final int minorUnitsUntilNextBoncuk;

  /// Historical gross Boncuk ever earned — monotonic, never decremented by
  /// a refund/reversal or by debt repayment (BR-LOYALTY-B P2B-B).
  final int lifetimeEarned;

  /// Historical Boncuk ever spent via redemption — monotonic.
  final int lifetimeRedeemed;

  /// The organization's current policy: `earningSpendMinorUnits` eligible
  /// net spend earns `earningBoncukAmount` Boncuk (BR-LOYALTY-001) —
  /// server-authoritative, per-organization, configurable
  /// (`loyaltyPolicies/{organizationId}`). Currently 5000/5 (50 TL = 5
  /// Boncuk) by default, but never assumed to be that specific pair (or
  /// evenly divisible) by any UI code — always read from these fields.
  final int earningSpendMinorUnits;
  final int earningBoncukAmount;

  /// `1 Boncuk = (redemptionValueMinorUnitsPerBoncuk / 100) TL` for
  /// ordinary cash-like redemption (BR-LOYALTY-005) — server-authoritative,
  /// per-organization, configurable. Informational display only this phase
  /// (no checkout redemption flow exists yet).
  final int redemptionValueMinorUnitsPerBoncuk;

  /// Maximum share of an eligible order a customer may pay with Boncuk, in
  /// basis points (`5000` = 50%) — server-authoritative, per-organization,
  /// configurable. Informational display only this phase.
  final int maxRedemptionBasisPoints;

  /// The zero/no-account-yet state — never shown to a guest (the guest
  /// prompt screen never renders any of these fields), and never shown to
  /// a real customer as if it were their true balance; it is only ever the
  /// real, honest starting point before their first eligible order. The
  /// policy fields here are display-safe fallbacks only (the locked
  /// defaults) — a real authenticated read always overwrites them with the
  /// server's actual current policy before this ever reaches the UI.
  static const zero = LoyaltyAccountSnapshot(
    spendableBalance: 0,
    boncukDebt: 0,
    earningRemainderMinorUnits: 0,
    minorUnitsUntilNextBoncuk: 1000,
    lifetimeEarned: 0,
    lifetimeRedeemed: 0,
    earningSpendMinorUnits: 5000,
    earningBoncukAmount: 5,
    redemptionValueMinorUnitsPerBoncuk: 100,
    maxRedemptionBasisPoints: 5000,
  );
}
