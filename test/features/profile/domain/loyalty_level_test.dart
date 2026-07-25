import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/profile/domain/models/loyalty_level.dart';

void main() {
  test('dusuk bakiye Bronz seviyeye karsilik gelir', () {
    expect(LoyaltyLevelInfo.forBalance(0), LoyaltyLevel.bronze);
    expect(LoyaltyLevelInfo.forBalance(320), LoyaltyLevel.bronze);
    expect(LoyaltyLevelInfo.forBalance(999), LoyaltyLevel.bronze);
  });

  test('esik degerinde ve uzerinde bir sonraki seviyeye gecilir', () {
    expect(LoyaltyLevelInfo.forBalance(1000), LoyaltyLevel.silver);
    expect(LoyaltyLevelInfo.forBalance(2999), LoyaltyLevel.silver);
    expect(LoyaltyLevelInfo.forBalance(3000), LoyaltyLevel.gold);
    expect(LoyaltyLevelInfo.forBalance(10000), LoyaltyLevel.gold);
  });

  test('next() dogru sirayla ilerler, en ustte null doner', () {
    expect(LoyaltyLevelInfo.next(LoyaltyLevel.bronze), LoyaltyLevel.silver);
    expect(LoyaltyLevelInfo.next(LoyaltyLevel.silver), LoyaltyLevel.gold);
    expect(LoyaltyLevelInfo.next(LoyaltyLevel.gold), isNull);
  });

  test('thresholdFor() her seviye icin dogru esigi doner', () {
    expect(LoyaltyLevelInfo.thresholdFor(LoyaltyLevel.bronze), 0);
    expect(LoyaltyLevelInfo.thresholdFor(LoyaltyLevel.silver), 1000);
    expect(LoyaltyLevelInfo.thresholdFor(LoyaltyLevel.gold), 3000);
  });

  test('labelFor() Turkce etiketleri dogru doner', () {
    expect(LoyaltyLevelInfo.labelFor(LoyaltyLevel.bronze), 'Bronz Seviye');
    expect(LoyaltyLevelInfo.labelFor(LoyaltyLevel.silver), 'Gümüş Seviye');
    expect(LoyaltyLevelInfo.labelFor(LoyaltyLevel.gold), 'Altın Seviye');
  });
}
