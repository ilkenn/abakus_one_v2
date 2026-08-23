import 'package:abakus_one_v2/features/orders/domain/models/boncuk_redemption_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

BoncukRedemptionSnapshot _build({int boncukUsed = 120}) {
  return BoncukRedemptionSnapshot(
    boncukUsed: boncukUsed,
    valueMinorUnits: 12000,
    remainingPayableMinorUnits: 38000,
    redemptionValueMinorUnitsPerBoncuk: 100,
    maxRedemptionBasisPoints: 5000,
    loyaltyPolicyVersion: 1,
  );
}

void main() {
  group('BoncukRedemptionSnapshot', () {
    test('two snapshots built from the same values are value-equal', () {
      expect(_build(), _build());
      expect(_build().hashCode, _build().hashCode);
    });

    test('differing in one field breaks equality', () {
      expect(_build(boncukUsed: 120), isNot(_build(boncukUsed: 121)));
    });
  });
}
