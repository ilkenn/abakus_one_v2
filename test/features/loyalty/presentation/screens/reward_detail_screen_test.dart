import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:abakus_one_v2/core/router/app_routes.dart';
import 'package:abakus_one_v2/features/auth/domain/models/auth_session.dart';
import 'package:abakus_one_v2/features/auth/presentation/providers/auth_provider.dart';
import 'package:abakus_one_v2/features/loyalty/data/loyalty_gateway.dart';
import 'package:abakus_one_v2/features/loyalty/domain/models/loyalty_account_snapshot.dart';
import 'package:abakus_one_v2/features/loyalty/domain/models/loyalty_history_entry.dart';
import 'package:abakus_one_v2/features/loyalty/domain/models/loyalty_reward.dart';
import 'package:abakus_one_v2/features/loyalty/presentation/providers/loyalty_providers.dart';
import 'package:abakus_one_v2/features/loyalty/presentation/screens/reward_detail_screen.dart';
import 'package:abakus_one_v2/features/menu/domain/models/menu_product.dart';
import 'package:abakus_one_v2/features/menu/presentation/providers/menu_catalog_provider.dart';
import 'package:abakus_one_v2/features/navigation/presentation/providers/navigation_provider.dart';
import 'package:abakus_one_v2/features/takeaway/presentation/screens/takeaway_branch_selection_screen.dart';

/// Boncuk Loyalty Program P7-D (2026-08-24) — proves [RewardDetailScreen]'s
/// eligible-products cross-reference, "where usable" channel display
/// (never showing an unsupported/unroutable channel as usable), the
/// affordability-gated CTA, and that the CTA only ever routes into an
/// existing checkout entry point — never a standalone claim/voucher.
class _FakeLoyaltyGateway implements LoyaltyGateway {
  _FakeLoyaltyGateway({LoyaltyAccountSnapshot? snapshot})
      : snapshot = snapshot ?? LoyaltyAccountSnapshot.zero;

  LoyaltyAccountSnapshot snapshot;

  @override
  Future<LoyaltyAccountSnapshot> getSnapshot() async => snapshot;

  @override
  Future<LoyaltyHistoryPage> getHistory({int? pageSize, String? cursor}) async {
    return LoyaltyHistoryPage.empty;
  }

  @override
  Future<List<LoyaltyReward>> getRewardCatalog() async => const [];
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
}) {
  return LoyaltyReward(
    rewardId: rewardId,
    title: title,
    description: description,
    rewardType: 'explicitProductSet',
    eligibleProductIds: eligibleProductIds,
    eligibleChannels: eligibleChannels,
    boncukCost: boncukCost,
    sortOrder: 0,
    version: 1,
  );
}

const _cola = MenuProduct(
  id: 'prod-cola',
  categoryId: 'cat-icecekler',
  name: 'Cola',
  description: '',
  basePrice: 30.0,
  imageKey: 'cola',
);

AuthSession _realCustomerSession() {
  return AuthSession(
    uid: 'real-customer-uid',
    phoneNumber: '+905551234567',
    createdAt: DateTime(2026, 8, 1),
    expiresAt: DateTime(2027, 8, 1),
  );
}

Future<ProviderContainer> _pumpDetail(
  WidgetTester tester, {
  required LoyaltyReward reward,
  LoyaltyAccountSnapshot? snapshot,
  List<MenuProduct> catalog = const [_cola],
}) async {
  final router = GoRouter(
    initialLocation: '/detail',
    routes: [
      // A stand-in root screen ahead of the pushed detail screen — mirrors
      // how RewardsScreen actually reaches RewardDetailScreen
      // (`Navigator.push`, never as the navigator's own first route), so
      // `_routeToChannel`'s `popUntil((route) => route.isFirst)` has a real
      // route to pop back TO instead of being a no-op.
      GoRoute(
        path: '/detail',
        builder: (context, state) => Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                key: const Key('openRewardDetail'),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => RewardDetailScreen(reward: reward),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.reservationPrefix,
        builder: (context, state) =>
            const Scaffold(body: Text('Reservation Flow Screen Stub')),
      ),
    ],
  );
  late final ProviderContainer container;
  container = ProviderContainer(
    overrides: [
      authProvider.overrideWith(() => SeededAuthNotifier(AuthState(
            isAuthenticated: true,
            isGuest: false,
            session: _realCustomerSession(),
          ))),
      loyaltyGatewayProvider.overrideWithValue(
        _FakeLoyaltyGateway(snapshot: snapshot),
      ),
      menuProductsProvider.overrideWithValue(catalog),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('openRewardDetail')));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets(
      'shows the exact server-sourced title, description and Boncuk cost',
      (tester) async {
    await _pumpDetail(
      tester,
      reward: _reward(
          title: 'Falafel Salad',
          description: 'Taze falafel salatası.',
          boncukCost: 400),
    );

    expect(find.text('Falafel Salad'), findsOneWidget);
    expect(find.text('Taze falafel salatası.'), findsOneWidget);
    expect(find.byKey(const Key('rewardDetailCostCard')), findsOneWidget);
    expect(find.text('400 Boncuk'), findsOneWidget);
  });

  testWidgets(
      'eligible products are cross-referenced by id against the real menu '
      'catalog and shown by name', (tester) async {
    await _pumpDetail(
      tester,
      reward: _reward(eligibleProductIds: const ['prod-cola']),
      catalog: const [_cola],
    );

    expect(find.text('Uygun Ürünler'), findsOneWidget);
    expect(find.text('Cola'), findsOneWidget);
  });

  testWidgets(
      'a reward whose eligibleProductIds do not match any real catalog '
      'product shows no "Uygun Ürünler" section at all — never a fabricated '
      'name', (tester) async {
    await _pumpDetail(
      tester,
      reward: _reward(eligibleProductIds: const ['prod-does-not-exist']),
      catalog: const [_cola],
    );

    expect(find.text('Uygun Ürünler'), findsNothing);
  });

  testWidgets(
      'channel badges: an app-routable channel (delivery/takeaway/'
      'reservationPreorder) is shown as usable; dineIn is shown but never '
      'as usable, since no server-authoritative dine-in order pipeline '
      'exists yet', (tester) async {
    await _pumpDetail(
      tester,
      reward: _reward(eligibleChannels: const [
        'dineIn',
        'takeaway',
        'delivery',
        'reservationPreorder',
      ]),
    );

    expect(find.text('Masa'), findsOneWidget);
    expect(find.text('Gel Al'), findsOneWidget);
    expect(find.text('Paket Servis'), findsOneWidget);
    expect(find.text('Rezervasyon'), findsOneWidget);
  });

  testWidgets(
      'a reward configured for dineIn only shows no usable channel at all '
      'and the CTA explains it is unusable through the app', (tester) async {
    await _pumpDetail(
      tester,
      reward: _reward(eligibleChannels: const ['dineIn']),
      snapshot: _snapshotWithBalance(500),
    );

    expect(
      find.text('Bu ödül şu anda uygulama üzerinden kullanılamıyor.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('rewardDetailUseCta')), findsNothing);
  });

  testWidgets(
      'insufficient balance disables the CTA with a clear "Yeterli Boncuk '
      'Yok" explanation, never a silently-disabled button', (tester) async {
    await _pumpDetail(
      tester,
      reward: _reward(
        eligibleChannels: const ['delivery'],
        boncukCost: 400,
      ),
      snapshot: _snapshotWithBalance(50),
    );

    expect(find.text('Bu ödülü kullanmak için 350 Boncuk daha kazanmalısın.'),
        findsOneWidget);
    expect(find.text('Yeterli Boncuk Yok'), findsOneWidget);
    final cta = tester
        .widget<ElevatedButton>(find.byKey(const Key('rewardDetailUseCta')));
    expect(cta.onPressed, isNull);
  });

  testWidgets(
      'a single usable channel: the CTA routes directly into that '
      'channel\'s existing checkout entry point — never a standalone claim',
      (tester) async {
    final container = await _pumpDetail(
      tester,
      reward: _reward(eligibleChannels: const ['delivery']),
      snapshot: _snapshotWithBalance(500),
    );

    expect(find.text('Paket Servis ile Kullan'), findsOneWidget);
    await tester.tap(find.byKey(const Key('rewardDetailUseCta')));
    await tester.pumpAndSettle();

    // Delivery routes via the bottom-nav menu tab (existing checkout entry
    // point), never a standalone claim/voucher screen — the detail screen
    // itself is popped off the stack in the process.
    expect(container.read(navigationProvider), AppTab.menu);
    expect(find.text('Ödül Detayı'), findsNothing);
  });

  testWidgets(
      'a single usable channel (takeaway): the CTA pushes the real '
      'TakeawayBranchSelectionScreen, not a standalone claim screen',
      (tester) async {
    await _pumpDetail(
      tester,
      reward: _reward(eligibleChannels: const ['takeaway']),
      snapshot: _snapshotWithBalance(500),
    );

    expect(find.text('Gel Al ile Kullan'), findsOneWidget);
    await tester.tap(find.byKey(const Key('rewardDetailUseCta')));
    await tester.pumpAndSettle();

    expect(find.byType(TakeawayBranchSelectionScreen), findsOneWidget);
  });

  testWidgets(
      'multiple usable channels show a channel-picker CTA; picking one '
      'routes to that channel', (tester) async {
    await _pumpDetail(
      tester,
      reward: _reward(eligibleChannels: const ['takeaway', 'delivery']),
      snapshot: _snapshotWithBalance(500),
    );

    expect(find.text('Bu Ödülü Kullan'), findsOneWidget);
    await tester.tap(find.byKey(const Key('rewardDetailUseCta')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('rewardDetailChannelOption-takeaway')),
        findsOneWidget);
    expect(find.byKey(const Key('rewardDetailChannelOption-delivery')),
        findsOneWidget);

    await tester
        .tap(find.byKey(const Key('rewardDetailChannelOption-takeaway')));
    await tester.pumpAndSettle();

    expect(find.byType(TakeawayBranchSelectionScreen), findsOneWidget);
  });
}
