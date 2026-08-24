import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/auth/domain/models/auth_session.dart';
import 'package:abakus_one_v2/features/auth/presentation/providers/auth_provider.dart';
import 'package:abakus_one_v2/features/cart/data/submit_dine_in_order_gateway.dart';
import 'package:abakus_one_v2/features/cart/presentation/providers/cart_provider.dart';
import 'package:abakus_one_v2/features/cart/presentation/providers/dine_in_order_dependencies_provider.dart';
import 'package:abakus_one_v2/features/cart/presentation/screens/dine_in_checkout_screen.dart';
import 'package:abakus_one_v2/features/cart/presentation/screens/order_success_screen.dart';
import 'package:abakus_one_v2/features/loyalty/data/loyalty_gateway.dart';
import 'package:abakus_one_v2/features/loyalty/domain/models/loyalty_account_snapshot.dart';
import 'package:abakus_one_v2/features/loyalty/domain/models/loyalty_history_entry.dart';
import 'package:abakus_one_v2/features/loyalty/domain/models/loyalty_reward.dart';
import 'package:abakus_one_v2/features/loyalty/presentation/providers/loyalty_providers.dart';
import 'package:abakus_one_v2/features/orders/data/canonical_order_repository.dart';
import 'package:abakus_one_v2/features/orders/domain/identity/order_identity.dart';
import 'package:abakus_one_v2/features/orders/domain/mappers/cart_to_order_mapper.dart';
import 'package:abakus_one_v2/features/orders/domain/models/catalog_reward_snapshot.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_actor.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_benefit_type.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_channel.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_status.dart';
import 'package:abakus_one_v2/features/orders/presentation/providers/order_identity_provider.dart';
import 'package:abakus_one_v2/features/orders/presentation/providers/orders_provider.dart';
import 'package:abakus_one_v2/features/qr/domain/models/active_table_context.dart';
import 'package:abakus_one_v2/features/qr/domain/models/guest_session.dart';
import 'package:abakus_one_v2/features/qr/domain/models/table_session.dart';
import 'package:abakus_one_v2/features/qr/data/table_guest_session_firestore_client.dart';
import 'package:abakus_one_v2/features/qr/presentation/providers/active_table_context_provider.dart';
import 'package:abakus_one_v2/features/qr/presentation/providers/table_guest_session_dependencies_provider.dart';

/// Boncuk Loyalty Program P7-D.1 (2026-08-24) — `DineInCheckoutScreen` now
/// submits through `SubmitDineInOrderGateway` (the real implementation
/// talks to the `submitDineInOrder` Cloud Function, unavailable under
/// `flutter test`), never a direct Firestore write. Mirrors
/// `delivery_checkout_screen_test.dart`'s own fake-gateway pattern —
/// organization/branch/restaurant/table/identity resolution is now a
/// SERVER concern (`submitDineInOrder.ts`'s own test suite), so this file
/// only proves the SCREEN's own wiring: what it sends, how it reacts to
/// success/failure, and its guest-vs-customer reward-UI gating.
class _FakeSubmitDineInOrderGateway implements SubmitDineInOrderGateway {
  _FakeSubmitDineInOrderGateway({
    required this.repository,
    required this.identityProvider,
    required this.cartItemsSnapshot,
    required this.resolveCustomerId,
  });

  final CanonicalOrderRepository repository;
  final OrderIdentityProvider identityProvider;
  final List Function() cartItemsSnapshot;
  final String? Function() resolveCustomerId;

  final Map<String, dynamic> _orderIdByKey = {};
  int callCount = 0;
  String? lastTableSessionId;
  String? lastSelectedRewardId;
  List<Map<String, dynamic>>? lastRequestItems;

  String catalogRewardTitleToReturn = 'Test Ödülü';
  int catalogRewardBoncukCostToReturn = 100;
  int catalogRewardCoveredValueMinorUnitsToReturn = 12000;

  SubmitDineInOrderException? errorToThrow;
  SubmitDineInOrderException? throwOnNextSubmit;
  Completer<void>? holdUntil;

  @override
  Future<SubmitDineInOrderResult> submit({
    required String submissionKey,
    required String tableSessionId,
    required List<DineInOrderItem> items,
    String customerNote = '',
    String? selectedRewardId,
  }) async {
    callCount += 1;
    lastTableSessionId = tableSessionId;
    lastSelectedRewardId = selectedRewardId;
    lastRequestItems = [for (final item in items) item.toJson()];

    final pendingHold = holdUntil;
    if (pendingHold != null) await pendingHold.future;

    final pendingThrow = throwOnNextSubmit;
    if (pendingThrow != null) {
      throwOnNextSubmit = null;
      throw pendingThrow;
    }
    final error = errorToThrow;
    if (error != null) throw error;

    final existingOrderId = _orderIdByKey[submissionKey];
    if (existingOrderId != null) {
      final existing = await repository.findById(existingOrderId);
      return SubmitDineInOrderResult(
        orderId: existingOrderId.value,
        orderNumber: existing!.orderNumber.value,
        duplicate: true,
      );
    }

    final orderId = await identityProvider.nextOrderId();
    final orderNumber = await identityProvider.nextOrderNumber();
    _orderIdByKey[submissionKey] = orderId;

    final now = DateTime.now();
    final customerId = resolveCustomerId();

    var order = CartToOrderMapper.map(
      orderId: orderId,
      orderNumber: orderNumber,
      cartItems: cartItemsSnapshot().cast(),
      channel: OrderChannel.dineInQr,
      branchId: 'branch-1',
      restaurantId: 'restaurant-1',
      customerId: customerId,
      tableId: 'dev-table-12',
      tableSessionId: tableSessionId,
      guestAuthUid: customerId ?? 'guest-technical-uid-1',
      now: now,
      customerNote: customerNote,
    );
    order = order.transitionTo(
      OrderStatus.pendingConfirmation,
      actor: OrderActor.customer,
      at: now,
      auditEntryId: '${orderId.value}-transition-1',
    );
    if (selectedRewardId != null) {
      order = order.copyWith(
        selectedBenefitType: OrderBenefitType.catalogReward,
        catalogReward: CatalogRewardSnapshot(
          rewardId: selectedRewardId,
          rewardVersion: 1,
          title: catalogRewardTitleToReturn,
          boncukCost: catalogRewardBoncukCostToReturn,
          redeemedProductId: cartItemsSnapshot().first.id as String,
          redeemedQuantity: 1,
          coveredValueMinorUnits: catalogRewardCoveredValueMinorUnitsToReturn,
          rewardCatalogVersionId: '${selectedRewardId}_1',
        ),
      );
    }
    await repository.submitOrder(order);

    return SubmitDineInOrderResult(
      orderId: orderId.value,
      orderNumber: orderNumber.value,
      duplicate: false,
    );
  }
}

class _FakeTableGuestSessionFirestoreClient
    implements TableGuestSessionFirestoreClient {
  final Map<String, TableGuestSessionSnapshot> _sessions = {};

  void seed(String sessionId, TableGuestSessionSnapshot snapshot) {
    _sessions[sessionId] = snapshot;
  }

  @override
  Future<TableGuestSessionSnapshot?> findById(String sessionId) async {
    return _sessions[sessionId];
  }
}

class _FakeLoyaltyGateway implements LoyaltyGateway {
  _FakeLoyaltyGateway(
      {LoyaltyAccountSnapshot? snapshot, this.rewards = const []})
      : snapshot = snapshot ?? LoyaltyAccountSnapshot.zero;

  LoyaltyAccountSnapshot snapshot;
  List<LoyaltyReward> rewards;

  @override
  Future<LoyaltyAccountSnapshot> getSnapshot() async => snapshot;

  @override
  Future<LoyaltyHistoryPage> getHistory({int? pageSize, String? cursor}) async {
    return LoyaltyHistoryPage.empty;
  }

  @override
  Future<List<LoyaltyReward>> getRewardCatalog() async => rewards;
}

LoyaltyReward _catalogReward({
  String rewardId = 'reward-1',
  List<String> eligibleProductIds = const ['p1'],
  int boncukCost = 100,
}) {
  return LoyaltyReward(
    rewardId: rewardId,
    title: 'Test Ödülü',
    description: 'Bir test ödülü.',
    rewardType: 'explicitProductSet',
    eligibleProductIds: eligibleProductIds,
    eligibleChannels: const [
      'dineIn',
      'takeaway',
      'delivery',
      'reservationPreorder'
    ],
    boncukCost: boncukCost,
    sortOrder: 0,
    version: 1,
  );
}

ActiveTableContext _context({
  String sessionId = 'tgs-1',
  String branchId = 'branch-1',
  String restaurantId = 'restaurant-1',
  String? reservationContextId,
}) {
  final now = DateTime(2026, 8, 9);
  return ActiveTableContext(
    restaurantId: restaurantId,
    branchId: branchId,
    branchName: 'Abaküs Ortaköy',
    tableId: 'dev-table-12',
    tableName: 'Masa 12',
    reservationContextId: reservationContextId,
    session: TableSession(
      id: sessionId,
      restaurantId: restaurantId,
      branchId: branchId,
      tableId: 'dev-table-12',
      status: TableSessionStatus.active,
      openedAt: now,
      guestSessionIds: const [],
      activeOrderIds: const [],
    ),
    guestSession: GuestSession(
      id: 'gsession-1',
      tableSessionId: sessionId,
      branchId: 'branch-1',
      tableId: 'dev-table-12',
      detectedLanguageCode: 'tr',
      selectedLanguageCode: 'tr',
      createdAt: now,
      lastSeenAt: now,
      status: GuestSessionStatus.active,
    ),
  );
}

void main() {
  Future<
      ({
        ProviderContainer container,
        _FakeSubmitDineInOrderGateway gateway,
      })> pumpWithSeededCart(
    WidgetTester tester, {
    ActiveTableContext? tableContext,
    TableGuestSessionSnapshot? sessionSnapshot,
    AuthSession? signedInCustomer,
    // ignore: library_private_types_in_public_api
    _FakeLoyaltyGateway? loyaltyGateway,
  }) async {
    // The CatalogRewardCard adds substantial height for a real-customer
    // scenario — the default test surface is too short for the ListView's
    // Sliver machinery to materialize everything below it (e.g. the error
    // banner), even with `skipOffstage: false` (that only affects finder
    // traversal, not whether a Sliver chose to build the item at all).
    // Mirrors `delivery_checkout_screen_test.dart`'s own `pumpCheckout`.
    tester.view.physicalSize = const Size(480, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final fakeSessionClient = _FakeTableGuestSessionFirestoreClient();
    if (tableContext != null && sessionSnapshot != null) {
      fakeSessionClient.seed(tableContext.session.id, sessionSnapshot);
    }

    late final ProviderContainer container;
    final gateway = _FakeSubmitDineInOrderGateway(
      repository: InMemoryCanonicalOrderRepository(),
      identityProvider: InMemoryOrderIdentityProvider(),
      cartItemsSnapshot: () => container.read(cartProvider),
      resolveCustomerId: () => signedInCustomer?.uid,
    );

    container = ProviderContainer(
      overrides: [
        tableGuestSessionFirestoreClientProvider
            .overrideWithValue(fakeSessionClient),
        canonicalOrderRepositoryProvider.overrideWithValue(gateway.repository),
        orderIdentityProvider.overrideWithValue(gateway.identityProvider),
        submitDineInOrderGatewayProvider.overrideWithValue(gateway),
        loyaltyGatewayProvider
            .overrideWithValue(loyaltyGateway ?? _FakeLoyaltyGateway()),
        if (signedInCustomer != null)
          authProvider.overrideWith(
            () => SeededAuthNotifier(
              AuthState(
                isAuthenticated: true,
                isGuest: false,
                session: signedInCustomer,
              ),
            ),
          ),
      ],
    );
    addTearDown(container.dispose);

    if (tableContext != null) {
      container.read(activeTableContextProvider.notifier).set(tableContext);
    }
    container.read(cartProvider.notifier).addToCart(
          id: 'p1',
          name: 'Falafel Bowl',
          desc: '',
          price: 100.0,
          quantity: 2,
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: DineInCheckoutScreen()),
      ),
    );
    await tester.pumpAndSettle();
    return (container: container, gateway: gateway);
  }

  testWidgets(
    'teslimat adresi veya gel-al ifadesi istemez, masa baglamini gosterir',
    (tester) async {
      await pumpWithSeededCart(
        tester,
        tableContext: _context(),
        sessionSnapshot: TableGuestSessionSnapshot(
          status: 'active',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
      );

      expect(find.text('Abaküs Ortaköy · Masa 12'), findsOneWidget);
      expect(find.textContaining('Teslimat Adresi'), findsNothing);
      expect(find.textContaining('Adres Ekle'), findsNothing);
      expect(find.textContaining('Gel Al'), findsNothing);
      expect(find.widgetWithText(ElevatedButton, 'Siparişi Ver · 200 TL'),
          findsOneWidget);
    },
  );

  testWidgets(
    'guest (customer oturumu yok): gateway tableSessionId ile cagrilir, siparis olusur, sepet temizlenir',
    (tester) async {
      final pumped = await pumpWithSeededCart(
        tester,
        tableContext: _context(),
        sessionSnapshot: TableGuestSessionSnapshot(
          status: 'active',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
      );

      await tester.tap(
        find.widgetWithText(ElevatedButton, 'Siparişi Ver · 200 TL'),
      );
      await tester.pumpAndSettle();

      expect(find.byType(OrderSuccessScreen), findsOneWidget);
      expect(find.text('Abaküs Ortaköy · Masa 12'), findsOneWidget);
      expect(find.text('Siparişin Alındı!'), findsOneWidget);

      expect(pumped.gateway.callCount, 1);
      expect(pumped.gateway.lastTableSessionId, 'tgs-1');
      expect(pumped.gateway.lastRequestItems, [
        {
          'kind': 'product',
          'productId': 'p1',
          'quantity': 2,
          'selectedModifiers': <Map<String, String>>[],
          'note': '',
        },
      ]);

      final orders = pumped.container.read(ordersProvider).value!;
      expect(orders, hasLength(1));

      final updatedContext = pumped.container.read(activeTableContextProvider);
      expect(updatedContext!.session.activeOrderIds, hasLength(1));

      expect(pumped.container.read(cartProvider), isEmpty);
    },
  );

  testWidgets(
      'hizli cift dokunma sadece bir gateway cagrisi yapar (yinelenen '
      'gonderim engellenir)', (tester) async {
    final pumped = await pumpWithSeededCart(
      tester,
      tableContext: _context(),
      sessionSnapshot: TableGuestSessionSnapshot(
        status: 'active',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      ),
    );

    final button = find.widgetWithText(ElevatedButton, 'Siparişi Ver · 200 TL');
    await tester.tap(button);
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(pumped.gateway.callCount, 1);
    final orders = pumped.container.read(ordersProvider).value!;
    expect(orders, hasLength(1));
  });

  testWidgets(
    'aktif masa baglami yoksa (kaybolmus baglam) siparis engellenir, gateway hic cagrilmaz',
    (tester) async {
      final pumped = await pumpWithSeededCart(tester);

      await tester.tap(
        find.widgetWithText(ElevatedButton, 'Siparişi Ver · 200 TL'),
      );
      await tester.pumpAndSettle();

      expect(find.byType(OrderSuccessScreen), findsNothing);
      expect(pumped.gateway.callCount, 0);
      expect(
        find.textContaining('Masa bilgisi bulunamadı', skipOffstage: false),
        findsOneWidget,
      );
      final orders = await pumped.container.read(ordersProvider.future);
      expect(orders, isEmpty);
      expect(pumped.container.read(cartProvider), isNotEmpty);
    },
  );

  testWidgets(
    'oturum baska bir yerde kapatilmissa (gecersiz/kaybolmus oturum) '
    'siparis engellenir, gateway hic cagrilmaz',
    (tester) async {
      final pumped = await pumpWithSeededCart(
        tester,
        tableContext: _context(),
        sessionSnapshot: TableGuestSessionSnapshot(
          status: 'revoked',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
      );

      await tester.tap(
        find.widgetWithText(ElevatedButton, 'Siparişi Ver · 200 TL'),
      );
      await tester.pumpAndSettle();

      expect(find.byType(OrderSuccessScreen), findsNothing);
      expect(pumped.gateway.callCount, 0);
      expect(
        find.textContaining(
          'Masa oturumun artık aktif değil',
          skipOffstage: false,
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'oturumun suresi dolmussa (expiresAt gecmis) siparis engellenir',
    (tester) async {
      final pumped = await pumpWithSeededCart(
        tester,
        tableContext: _context(),
        sessionSnapshot: TableGuestSessionSnapshot(
          status: 'active',
          expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
        ),
      );

      await tester.tap(
        find.widgetWithText(ElevatedButton, 'Siparişi Ver · 200 TL'),
      );
      await tester.pumpAndSettle();

      expect(find.byType(OrderSuccessScreen), findsNothing);
      expect(pumped.gateway.callCount, 0);
    },
  );

  // =========================================================================
  // Boncuk Loyalty Program P7-D.1 (2026-08-24) — catalog-reward selection,
  // real customer only; an anonymous table guest sees no reward control at
  // all, not even a disabled state.
  // =========================================================================

  testWidgets(
    'anonim misafir: odul karti hic gosterilmez (devre disi bile degil)',
    (tester) async {
      await pumpWithSeededCart(
        tester,
        tableContext: _context(),
        sessionSnapshot: TableGuestSessionSnapshot(
          status: 'active',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
        loyaltyGateway: _FakeLoyaltyGateway(
          snapshot: const LoyaltyAccountSnapshot(
            spendableBalance: 500,
            boncukDebt: 0,
            earningRemainderMinorUnits: 0,
            minorUnitsUntilNextBoncuk: 5000,
            lifetimeEarned: 500,
            lifetimeRedeemed: 0,
            earningSpendMinorUnits: 5000,
            earningBoncukAmount: 5,
            redemptionValueMinorUnitsPerBoncuk: 100,
            maxRedemptionBasisPoints: 5000,
          ),
          rewards: [_catalogReward()],
        ),
      );

      expect(find.byKey(const Key('catalogRewardCard')), findsNothing);
      expect(find.byKey(const Key('catalogRewardCardSkeleton')), findsNothing);
      expect(find.textContaining('Boncuk'), findsNothing);
    },
  );

  testWidgets(
    'gercek musteri: uygun bir odul secilebilir, gateway secilenRewardId ile cagrilir',
    (tester) async {
      final signedInCustomer = AuthSession(
        uid: 'real-customer-uid',
        phoneNumber: '+905551234567',
        createdAt: DateTime(2026, 8, 1),
        expiresAt: DateTime(2027, 8, 1),
      );
      final pumped = await pumpWithSeededCart(
        tester,
        tableContext: _context(),
        sessionSnapshot: TableGuestSessionSnapshot(
          status: 'active',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
        signedInCustomer: signedInCustomer,
        loyaltyGateway: _FakeLoyaltyGateway(
          rewards: [
            _catalogReward(rewardId: 'reward-1', eligibleProductIds: ['p1'])
          ],
        ),
      );

      expect(find.byKey(const Key('catalogRewardCard')), findsOneWidget);
      await tester.tap(find.byKey(const Key('catalogRewardTile-reward-1')));
      await tester.pumpAndSettle();

      await tester.tap(
        find.widgetWithText(ElevatedButton, 'Siparişi Ver · 200 TL'),
      );
      await tester.pumpAndSettle();

      expect(pumped.gateway.lastSelectedRewardId, 'reward-1');
      expect(find.byType(OrderSuccessScreen), findsOneWidget);
      expect(find.byKey(const Key('orderSuccessCatalogRewardSummary')),
          findsOneWidget);
    },
  );

  testWidgets(
    'catalogReward-spesifik sunucu reddi secimi sifirlar, gateway hatasiz tekrar cagrilabilir',
    (tester) async {
      final signedInCustomer = AuthSession(
        uid: 'real-customer-uid',
        phoneNumber: '+905551234567',
        createdAt: DateTime(2026, 8, 1),
        expiresAt: DateTime(2027, 8, 1),
      );
      final pumped = await pumpWithSeededCart(
        tester,
        tableContext: _context(),
        sessionSnapshot: TableGuestSessionSnapshot(
          status: 'active',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
        signedInCustomer: signedInCustomer,
        loyaltyGateway: _FakeLoyaltyGateway(
          rewards: [_catalogReward(rewardId: 'reward-1')],
        ),
      );
      await tester.tap(find.byKey(const Key('catalogRewardTile-reward-1')));
      await tester.pumpAndSettle();

      pumped.gateway.throwOnNextSubmit = const SubmitDineInOrderException(
        'invalid-argument',
        'Reward no longer valid.',
        boncukErrorReason: 'catalogReward/insufficient-balance',
      );

      await tester.tap(
        find.widgetWithText(ElevatedButton, 'Siparişi Ver · 200 TL'),
      );
      await tester.pumpAndSettle();

      expect(pumped.gateway.callCount, 1);
      expect(find.byType(OrderSuccessScreen), findsNothing);
      expect(
        find.textContaining('Bu ödül için yeterli Boncuk bakiyen yok',
            skipOffstage: false),
        findsOneWidget,
      );

      await tester.tap(
        find.widgetWithText(ElevatedButton, 'Siparişi Ver · 200 TL'),
      );
      await tester.pumpAndSettle();
      expect(pumped.gateway.callCount, 2);
      expect(pumped.gateway.lastSelectedRewardId, isNull);
      expect(find.byType(OrderSuccessScreen), findsOneWidget);
    },
  );
}
