import 'package:abakus_one_v2/features/cart/presentation/screens/takeaway_checkout_screen.dart';
import 'package:abakus_one_v2/features/loyalty/domain/models/loyalty_account_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

/// Boncuk Loyalty Program P4-E-B (2026-08-22) — pure-function coverage for
/// `computeClientEstimatedMaxBoncuk`, the NON-AUTHORITATIVE presentation
/// estimate `TakeawayCheckoutScreen` uses to bound its stepper/MAX action.
/// Mirrors `functions/src/loyaltyRedemption.ts`'s own locked
/// `calculateBoncukRedemption` cap formula (P4-B §3) exactly — these worked
/// examples are chosen to match that file's own, so a divergence between
/// the client estimate and the real server algorithm would show up here
/// first.
void main() {
  LoyaltyAccountSnapshot snapshot({
    int spendableBalance = 100,
    int boncukDebt = 0,
    int redemptionValueMinorUnitsPerBoncuk = 100,
    int maxRedemptionBasisPoints = 5000,
  }) {
    return LoyaltyAccountSnapshot(
      spendableBalance: spendableBalance,
      boncukDebt: boncukDebt,
      earningRemainderMinorUnits: 0,
      minorUnitsUntilNextBoncuk: 5000,
      lifetimeEarned: spendableBalance,
      lifetimeRedeemed: 0,
      earningSpendMinorUnits: 5000,
      earningBoncukAmount: 5,
      redemptionValueMinorUnitsPerBoncuk: redemptionValueMinorUnitsPerBoncuk,
      maxRedemptionBasisPoints: maxRedemptionBasisPoints,
    );
  }

  test('order-cap-bound: cart 240 TL, rate 100, cap 50% -> max 120', () {
    // maxRedemptionValueMinorUnits = 24000 * 5000 / 10000 = 12000.
    // maxUsableBoncukByOrderCap = 12000 / 100 = 120. min(100, 120) is
    // balance-bound here (100) — use a larger balance to isolate the cap.
    expect(
      computeClientEstimatedMaxBoncuk(
        snapshot(spendableBalance: 500),
        240.0,
      ),
      120,
    );
  });

  test('balance-bound: a small balance caps below what the order allows', () {
    expect(
      computeClientEstimatedMaxBoncuk(
        snapshot(spendableBalance: 10),
        240.0,
      ),
      10,
    );
  });

  test('a non-default rate/cap changes the result — never a hardcoded pair',
      () {
    final withDefaultPolicy = computeClientEstimatedMaxBoncuk(
      snapshot(spendableBalance: 500),
      240.0,
    );
    final withTighterPolicy = computeClientEstimatedMaxBoncuk(
      snapshot(
        spendableBalance: 500,
        redemptionValueMinorUnitsPerBoncuk: 300,
        maxRedemptionBasisPoints: 1000,
      ),
      240.0,
    );
    expect(withTighterPolicy, lessThan(withDefaultPolicy));
    // maxRedemptionValueMinorUnits = 24000 * 1000 / 10000 = 2400.
    // maxUsableBoncukByOrderCap = 2400 / 300 = 8.
    expect(withTighterPolicy, 8);
  });

  test('zero spendable balance -> 0, regardless of cart size', () {
    expect(
      computeClientEstimatedMaxBoncuk(snapshot(spendableBalance: 0), 500.0),
      0,
    );
  });

  test('boncukDebt > 0 -> 0, even if spendableBalance were somehow nonzero',
      () {
    // The canonical invariant guarantees spendableBalance == 0 whenever
    // boncukDebt > 0 in a real snapshot — this proves the function itself
    // never trusts spendableBalance alone, defensively checking debt too.
    expect(
      computeClientEstimatedMaxBoncuk(
        snapshot(spendableBalance: 50, boncukDebt: 3),
        240.0,
      ),
      0,
    );
  });

  test('a zero cart total -> 0 usable Boncuk (nothing to redeem against)', () {
    expect(
      computeClientEstimatedMaxBoncuk(snapshot(spendableBalance: 500), 0.0),
      0,
    );
  });

  test('integer-only result — never a fractional Boncuk count', () {
    // 100 minor-unit-per-Boncuk rate against an odd cart total that would
    // produce a fractional quotient if this used floating point division.
    final result = computeClientEstimatedMaxBoncuk(
      snapshot(spendableBalance: 500, maxRedemptionBasisPoints: 3333),
      99.99,
    );
    expect(result, isA<int>());
  });
}
