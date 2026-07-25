import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/profile/domain/models/loyalty_level.dart';
import 'package:abakus_one_v2/features/profile/presentation/providers/loyalty_provider.dart';

void main() {
  test('baslangic durumu Bronz seviyede, gunluk cark hakki acik', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final state = container.read(loyaltyProvider);

    expect(state.currentBalance, 320);
    expect(state.level, LoyaltyLevel.bronze);
    expect(state.nextLevel, LoyaltyLevel.silver);
    expect(state.pointsToNextLevel, 1000 - 320);
    expect(state.dailySpinAvailable, isTrue);
    expect(state.lastSpinReward, isNull);
    expect(state.rewards, isNotEmpty);
    expect(state.tasks, isNotEmpty);
    expect(state.campaigns, isNotEmpty);
  });

  test('spinWheel bakiyeyi kSpinWheelSegments icindeki bir degerle artirir',
      () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final before = container.read(loyaltyProvider).currentBalance;
    final reward = container.read(loyaltyProvider.notifier).spinWheel();
    final after = container.read(loyaltyProvider);

    expect(reward, isNotNull);
    expect(kSpinWheelSegments, contains(reward));
    expect(after.currentBalance, before + reward!);
    expect(after.lastSpinReward, reward);
    expect(after.history.first.title, 'Şans Çarkı Ödülü');
    expect(after.history.first.points, reward);
    expect(after.history.first.isEarned, isTrue);
  });

  test('gunluk cark hakki tukendikten sonra ikinci cevirme engellenir', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(loyaltyProvider.notifier);

    final firstSpin = notifier.spinWheel();
    expect(firstSpin, isNotNull);
    expect(container.read(loyaltyProvider).dailySpinAvailable, isFalse);

    final balanceAfterFirstSpin =
        container.read(loyaltyProvider).currentBalance;
    final secondSpin = notifier.spinWheel();

    expect(secondSpin, isNull);
    expect(
      container.read(loyaltyProvider).currentBalance,
      balanceAfterFirstSpin,
    );
  });

  test('redeemReward yeterli bakiyede dusurur ve gecmise ekler', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(loyaltyProvider.notifier);

    notifier.redeemReward('İçecek Ödülü', 50);
    final state = container.read(loyaltyProvider);

    expect(state.currentBalance, 320 - 50);
    expect(state.history.first.title, 'İçecek Ödülü Kullanımı');
    expect(state.history.first.isEarned, isFalse);
  });

  test('redeemReward yetersiz bakiyede hicbir sey degistirmez', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(loyaltyProvider.notifier);

    final before = container.read(loyaltyProvider);
    notifier.redeemReward('Bowl Ödülü', 10000);
    final after = container.read(loyaltyProvider);

    expect(after.currentBalance, before.currentBalance);
    expect(after.history.length, before.history.length);
  });

  test(
      'en ust seviyedeyken (Altin) pointsToNextLevel 0 ve nextLevel null doner',
      () {
    const state = LoyaltyState(currentBalance: 3500, history: []);

    expect(state.level, LoyaltyLevel.gold);
    expect(state.nextLevel, isNull);
    expect(state.pointsToNextLevel, 0);
  });

  test('Gumus seviyedeyken pointsToNextLevel Altin esigine gore hesaplanir',
      () {
    const state = LoyaltyState(currentBalance: 1500, history: []);

    expect(state.level, LoyaltyLevel.silver);
    expect(state.nextLevel, LoyaltyLevel.gold);
    expect(state.pointsToNextLevel, 3000 - 1500);
  });
}
