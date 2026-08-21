import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/loyalty/domain/models/loyalty_account_snapshot.dart';

/// Boncuk Configurable Loyalty Economics (2026-08-24), corrected same-day —
/// the client-side mirror of `functions/src/loyaltyPolicy.ts`'s
/// per-organization, exact-ratio policy. Neither the per-Boncuk rate nor
/// the earning-progress denominator are Flutter `static const` values, nor
/// are they derived client-side from a (possibly non-integer-reducible)
/// ratio — every field, including [LoyaltyAccountSnapshot.minorUnitsUntilNextBoncuk],
/// is a real, server-resolved instance field.
void main() {
  const defaultEconomics = (
    earningSpendMinorUnits: 5000,
    earningBoncukAmount: 5,
    redemptionValueMinorUnitsPerBoncuk: 100,
    maxRedemptionBasisPoints: 5000,
  );

  test(
      'zero snapshot has every balance field at 0 and carries the locked default economics',
      () {
    const zero = LoyaltyAccountSnapshot.zero;
    expect(zero.spendableBalance, 0);
    expect(zero.boncukDebt, 0);
    expect(zero.earningRemainderMinorUnits, 0);
    expect(zero.minorUnitsUntilNextBoncuk, 1000);
    expect(zero.lifetimeEarned, 0);
    expect(zero.lifetimeRedeemed, 0);
    expect(
        zero.earningSpendMinorUnits, defaultEconomics.earningSpendMinorUnits);
    expect(zero.earningBoncukAmount, defaultEconomics.earningBoncukAmount);
    expect(
      zero.redemptionValueMinorUnitsPerBoncuk,
      defaultEconomics.redemptionValueMinorUnitsPerBoncuk,
    );
    expect(zero.maxRedemptionBasisPoints,
        defaultEconomics.maxRedemptionBasisPoints);
  });

  test(
      'a non-integer-reducible policy (5000 -> 3) is carried verbatim — no client-side derivation ever attempted',
      () {
    const snapshot = LoyaltyAccountSnapshot(
      spendableBalance: 2,
      boncukDebt: 0,
      earningRemainderMinorUnits: 33,
      minorUnitsUntilNextBoncuk: 1634,
      lifetimeEarned: 2,
      lifetimeRedeemed: 0,
      earningSpendMinorUnits: 5000,
      earningBoncukAmount: 3,
      redemptionValueMinorUnitsPerBoncuk: 50,
      maxRedemptionBasisPoints: 2500,
    );
    expect(snapshot.earningSpendMinorUnits, 5000);
    expect(snapshot.earningBoncukAmount, 3);
    expect(snapshot.earningRemainderMinorUnits, 33);
    expect(snapshot.minorUnitsUntilNextBoncuk, 1634);
  });

  test(
      'minorUnitsUntilNextBoncuk is always the server-provided value, never re-derived — differs for two snapshots with identical remainders but different (server-resolved) block sizes',
      () {
    const evenlyDivisible = LoyaltyAccountSnapshot(
      spendableBalance: 0,
      boncukDebt: 0,
      earningRemainderMinorUnits: 400,
      minorUnitsUntilNextBoncuk: 600,
      lifetimeEarned: 0,
      lifetimeRedeemed: 0,
      earningSpendMinorUnits: 5000,
      earningBoncukAmount: 5,
      redemptionValueMinorUnitsPerBoncuk: 100,
      maxRedemptionBasisPoints: 5000,
    );
    const nonReducible = LoyaltyAccountSnapshot(
      spendableBalance: 0,
      boncukDebt: 0,
      earningRemainderMinorUnits: 400,
      minorUnitsUntilNextBoncuk: 1267,
      lifetimeEarned: 0,
      lifetimeRedeemed: 0,
      earningSpendMinorUnits: 5000,
      earningBoncukAmount: 3,
      redemptionValueMinorUnitsPerBoncuk: 50,
      maxRedemptionBasisPoints: 2500,
    );
    expect(evenlyDivisible.earningRemainderMinorUnits,
        nonReducible.earningRemainderMinorUnits);
    expect(
      evenlyDivisible.minorUnitsUntilNextBoncuk,
      isNot(nonReducible.minorUnitsUntilNextBoncuk),
    );
  });

  group('MANDATORY dynamic-policy fixtures', () {
    test(
        'Fixture A: 50 TL -> 5 Boncuk, 1 Boncuk = 1 TL, max 50% carries the exact fixture values',
        () {
      const fixtureA = LoyaltyAccountSnapshot(
        spendableBalance: 12,
        boncukDebt: 0,
        earningRemainderMinorUnits: 2500,
        minorUnitsUntilNextBoncuk: 2500,
        lifetimeEarned: 12,
        lifetimeRedeemed: 0,
        earningSpendMinorUnits: 5000,
        earningBoncukAmount: 5,
        redemptionValueMinorUnitsPerBoncuk: 100,
        maxRedemptionBasisPoints: 5000,
      );
      expect(fixtureA.earningSpendMinorUnits, 5000);
      expect(fixtureA.earningBoncukAmount, 5);
      expect(fixtureA.redemptionValueMinorUnitsPerBoncuk, 100);
      expect(fixtureA.maxRedemptionBasisPoints, 5000);
    });

    test(
        'Fixture B: 50 TL -> 3 Boncuk, 1 Boncuk = 0.50 TL, max 25% carries the exact fixture values',
        () {
      const fixtureB = LoyaltyAccountSnapshot(
        spendableBalance: 7,
        boncukDebt: 0,
        earningRemainderMinorUnits: 1000,
        minorUnitsUntilNextBoncuk: 667,
        lifetimeEarned: 7,
        lifetimeRedeemed: 0,
        earningSpendMinorUnits: 5000,
        earningBoncukAmount: 3,
        redemptionValueMinorUnitsPerBoncuk: 50,
        maxRedemptionBasisPoints: 2500,
      );
      expect(fixtureB.earningSpendMinorUnits, 5000);
      expect(fixtureB.earningBoncukAmount, 3);
      expect(fixtureB.redemptionValueMinorUnitsPerBoncuk, 50);
      expect(fixtureB.maxRedemptionBasisPoints, 2500);
      // The redemption value is deliberately sub-1-TL — proves the model
      // carries the raw minor-units value, not a pre-rounded display string.
      expect(fixtureB.redemptionValueMinorUnitsPerBoncuk < 100, isTrue);
    });
  });
}
