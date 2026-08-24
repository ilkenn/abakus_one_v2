import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abakus_one_v2/features/auth/domain/models/auth_session.dart';
import 'package:abakus_one_v2/features/auth/presentation/providers/auth_provider.dart';
import 'package:abakus_one_v2/features/loyalty/data/loyalty_gateway.dart';
import 'package:abakus_one_v2/features/loyalty/domain/models/loyalty_account_snapshot.dart';
import 'package:abakus_one_v2/features/loyalty/domain/models/loyalty_history_entry.dart';
import 'package:abakus_one_v2/features/loyalty/domain/models/loyalty_reward.dart';
import 'package:abakus_one_v2/features/loyalty/presentation/providers/loyalty_providers.dart';
import 'package:abakus_one_v2/features/loyalty/presentation/screens/reward_detail_screen.dart';
import 'package:abakus_one_v2/features/loyalty/presentation/screens/rewards_screen.dart';

/// Boncuk Loyalty Program P7-D (2026-08-24) — "Boncuklarım → Ödüller".
/// Proves the real customer Reward Catalog screen: real-gateway sourcing (no
/// mock catalog reachable), affordability, and navigation into
/// [RewardDetailScreen] — mirrors the checkout screens' own
/// `_FakeLoyaltyGateway` test-double convention.
class _FakeLoyaltyGateway implements LoyaltyGateway {
  _FakeLoyaltyGateway({
    LoyaltyAccountSnapshot? snapshot,
    this.rewards = const [],
    this.rewardCatalogError,
  }) : snapshot = snapshot ?? LoyaltyAccountSnapshot.zero;

  LoyaltyAccountSnapshot snapshot;
  List<LoyaltyReward> rewards;
  LoyaltyGatewayException? rewardCatalogError;
  int rewardCatalogCalls = 0;

  @override
  Future<LoyaltyAccountSnapshot> getSnapshot() async => snapshot;

  @override
  Future<LoyaltyHistoryPage> getHistory({int? pageSize, String? cursor}) async {
    return LoyaltyHistoryPage.empty;
  }

  @override
  Future<List<LoyaltyReward>> getRewardCatalog() async {
    rewardCatalogCalls += 1;
    if (rewardCatalogError != null) throw rewardCatalogError!;
    return rewards;
  }
}

LoyaltyReward _reward({
  String rewardId = 'reward-1',
  String title = 'İçecek Ödülü',
  String description = 'Bir içecek seç, ücretsiz alsın.',
  List<String> eligibleProductIds = const ['prod-cola'],
  List<String> eligibleChannels = const [
    'dineIn',
    'takeaway',
    'delivery',
    'reservationPreorder',
  ],
  int boncukCost = 70,
  int sortOrder = 0,
}) {
  return LoyaltyReward(
    rewardId: rewardId,
    title: title,
    description: description,
    rewardType: 'explicitProductSet',
    eligibleProductIds: eligibleProductIds,
    eligibleChannels: eligibleChannels,
    boncukCost: boncukCost,
    sortOrder: sortOrder,
    version: 1,
  );
}

LoyaltyAccountSnapshot _snapshotWithBalance(int spendableBalance) {
  return LoyaltyAccountSnapshot(
    spendableBalance: spendableBalance,
    boncukDebt: 0,
    earningRemainderMinorUnits: 0,
    minorUnitsUntilNextBoncuk: 5000,
    lifetimeEarned: spendableBalance,
    lifetimeRedeemed: 0,
    earningSpendMinorUnits: 5000,
    earningBoncukAmount: 5,
    redemptionValueMinorUnitsPerBoncuk: 100,
    maxRedemptionBasisPoints: 5000,
  );
}

AuthSession _realCustomerSession() {
  return AuthSession(
    uid: 'real-customer-uid',
    phoneNumber: '+905551234567',
    createdAt: DateTime(2026, 8, 1),
    expiresAt: DateTime(2027, 8, 1),
  );
}

Future<void> _pumpRewards(
  WidgetTester tester, {
  required _FakeLoyaltyGateway loyaltyGateway,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith(() => SeededAuthNotifier(AuthState(
              isAuthenticated: true,
              isGuest: false,
              session: _realCustomerSession(),
            ))),
        loyaltyGatewayProvider.overrideWithValue(loyaltyGateway),
      ],
      child: const MaterialApp(home: RewardsScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('loading state renders while the real reward catalog loads',
      (tester) async {
    final gateway = _FakeLoyaltyGateway(rewards: [_reward()]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith(() => SeededAuthNotifier(AuthState(
                isAuthenticated: true,
                isGuest: false,
                session: _realCustomerSession(),
              ))),
          loyaltyGatewayProvider.overrideWithValue(gateway),
        ],
        child: const MaterialApp(home: RewardsScreen()),
      ),
    );
    // No pumpAndSettle yet — the future is still in flight.
    expect(find.textContaining('yükleniyor'), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets(
      'an empty real catalog shows the explicit empty state, never a mock reward',
      (tester) async {
    await _pumpRewards(tester, loyaltyGateway: _FakeLoyaltyGateway());

    expect(find.text('Şu anda kullanılabilir bir ödül yok.'), findsOneWidget);
    expect(find.textContaining('Boncuk'), findsNothing);
  });

  testWidgets('a catalog load failure shows a retry affordance',
      (tester) async {
    final gateway = _FakeLoyaltyGateway(
      rewardCatalogError:
          const LoyaltyGatewayException('internal', 'Ödüller yüklenemedi.'),
    );
    await _pumpRewards(tester, loyaltyGateway: gateway);

    expect(find.text('Ödüller şu anda yüklenemedi.'), findsOneWidget);
    expect(find.text('Tekrar Dene'), findsOneWidget);
  });

  testWidgets(
      'every reward from the real gateway is listed, sorted by sortOrder — '
      'title, description, and Boncuk cost are all shown, sourced from the '
      'server DTO, never a hardcoded/mock value', (tester) async {
    final gateway = _FakeLoyaltyGateway(
      snapshot: _snapshotWithBalance(500),
      rewards: [
        _reward(
            rewardId: 'r2',
            title: 'İkinci Ödül',
            boncukCost: 200,
            sortOrder: 2),
        _reward(
            rewardId: 'r1',
            title: 'Birinci Ödül',
            boncukCost: 70,
            sortOrder: 1),
      ],
    );
    await _pumpRewards(tester, loyaltyGateway: gateway);

    expect(find.byKey(const Key('rewardCard-r1')), findsOneWidget);
    expect(find.byKey(const Key('rewardCard-r2')), findsOneWidget);
    expect(find.text('Birinci Ödül'), findsOneWidget);
    expect(find.text('İkinci Ödül'), findsOneWidget);
    expect(find.text('70 Boncuk'), findsOneWidget);
    expect(find.text('200 Boncuk'), findsOneWidget);

    // Sort order: r1 (sortOrder 1) must appear above r2 (sortOrder 2).
    final r1Position =
        tester.getTopLeft(find.byKey(const Key('rewardCard-r1')));
    final r2Position =
        tester.getTopLeft(find.byKey(const Key('rewardCard-r2')));
    expect(r1Position.dy, lessThan(r2Position.dy));
  });

  testWidgets(
      'affordability: a reward the customer can afford shows no "needs more" '
      'copy; one they cannot afford shows exactly how many more Boncuk are needed',
      (tester) async {
    final gateway = _FakeLoyaltyGateway(
      snapshot: _snapshotWithBalance(100),
      rewards: [
        _reward(rewardId: 'affordable', boncukCost: 70),
        _reward(rewardId: 'unaffordable', boncukCost: 420),
      ],
    );
    await _pumpRewards(tester, loyaltyGateway: gateway);

    expect(find.text('320 Boncuk daha gerekli'), findsOneWidget);
    expect(find.textContaining('70 Boncuk daha gerekli'), findsNothing);
  });

  testWidgets(
      'tapping a reward card navigates into RewardDetailScreen carrying the '
      'exact same server-sourced reward object', (tester) async {
    final gateway = _FakeLoyaltyGateway(
      rewards: [_reward(rewardId: 'reward-x', title: 'Falafel Salad')],
    );
    await _pumpRewards(tester, loyaltyGateway: gateway);

    await tester.tap(find.byKey(const Key('rewardCard-reward-x')));
    await tester.pumpAndSettle();

    expect(find.byType(RewardDetailScreen), findsOneWidget);
    final detailScreen =
        tester.widget<RewardDetailScreen>(find.byType(RewardDetailScreen));
    expect(detailScreen.reward.rewardId, 'reward-x');
    expect(detailScreen.reward.title, 'Falafel Salad');
  });
}
