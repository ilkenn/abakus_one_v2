import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/auth/domain/models/auth_session.dart';
import 'package:abakus_one_v2/features/auth/presentation/providers/auth_provider.dart';
import 'package:abakus_one_v2/features/campaigns/data/campaign_gateway.dart';
import 'package:abakus_one_v2/features/campaigns/domain/models/campaign.dart';
import 'package:abakus_one_v2/features/campaigns/presentation/providers/campaigns_provider.dart';
import 'package:abakus_one_v2/core/services/connectivity/network_connectivity_monitor.dart';
import 'package:abakus_one_v2/features/cart/data/dine_in_offline_order_queue_repository.dart';
import 'package:abakus_one_v2/features/cart/data/submit_dine_in_order_gateway.dart';
import 'package:abakus_one_v2/features/cart/domain/models/cart_item.dart';
import 'package:abakus_one_v2/features/cart/domain/models/pending_dine_in_submission.dart';
import 'package:abakus_one_v2/features/cart/presentation/providers/cart_provider.dart';
import 'package:abakus_one_v2/features/cart/presentation/providers/dine_in_order_dependencies_provider.dart';
import 'package:abakus_one_v2/features/cart/presentation/providers/table_session_cart_dependencies_provider.dart';
import 'package:abakus_one_v2/features/cart/presentation/screens/dine_in_checkout_screen.dart';
import 'package:abakus_one_v2/features/cart/presentation/screens/order_success_screen.dart';
import '../../test_support/fake_table_session_cart_firestore_client.dart';
import 'package:abakus_one_v2/features/loyalty/data/loyalty_gateway.dart';
import 'package:abakus_one_v2/features/loyalty/domain/models/loyalty_account_snapshot.dart';
import 'package:abakus_one_v2/features/loyalty/domain/models/loyalty_history_entry.dart';
import 'package:abakus_one_v2/features/loyalty/domain/models/loyalty_reward.dart';
import 'package:abakus_one_v2/features/loyalty/presentation/providers/loyalty_providers.dart';
import 'package:abakus_one_v2/features/orders/data/canonical_order_repository.dart';
import 'package:abakus_one_v2/features/orders/domain/identity/order_identity.dart';
import 'package:abakus_one_v2/features/orders/domain/mappers/cart_to_order_mapper.dart';
import 'package:abakus_one_v2/features/orders/domain/models/campaign_snapshot.dart';
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
import 'package:abakus_one_v2/features/qr/data/technical_identity_provider.dart';
import 'package:abakus_one_v2/features/qr/presentation/providers/active_table_context_provider.dart';
import 'package:abakus_one_v2/features/qr/presentation/providers/table_guest_session_dependencies_provider.dart';

/// Self-Order QR Faz 3 — `cartProvider` now resolves a deterministic
/// `addedBySubAccountId` via this provider whenever a table context is
/// active, so every test that exercises `DineInCheckoutScreen` with one
/// needs a fixed, non-Firebase-backed uid. Mirrors
/// `table_guest_entry_screen_test.dart`'s own private fake exactly.
class _FakeTechnicalIdentityProvider implements TechnicalIdentityProvider {
  const _FakeTechnicalIdentityProvider(this.uid);
  final String uid;

  @override
  String? get currentUid => uid;

  @override
  Future<String> ensureSignedIn() async => uid;
}

/// Self-Order QR Faz 6 — a fixed, never-emitting "always online" signal so
/// the screen's own connectivity check always proceeds to the real
/// submission path in tests, never the offline-queue path, unless a test
/// explicitly asks for the offline branch via [status].
class _FakeNetworkConnectivityMonitor implements NetworkConnectivityMonitor {
  _FakeNetworkConnectivityMonitor({
    this.status = NetworkConnectivityStatus.online,
    Stream<NetworkConnectivityStatus>? statusChanges,
  }) : _statusChanges = statusChanges ?? const Stream.empty();

  NetworkConnectivityStatus status;
  final Stream<NetworkConnectivityStatus> _statusChanges;

  @override
  Future<NetworkConnectivityStatus> currentStatus() async => status;

  @override
  Stream<NetworkConnectivityStatus> get onStatusChanged => _statusChanges;
}

/// Self-Order QR Faz 6 — an in-memory stand-in for
/// `SharedPreferencesDineInOfflineOrderQueueRepository`, avoiding any real
/// `shared_preferences` plugin-channel traffic under `flutter test`.
class _FakeDineInOfflineOrderQueueRepository
    implements DineInOfflineOrderQueueRepository {
  final List<PendingDineInSubmission> _entries = [];

  @override
  Future<void> enqueue(PendingDineInSubmission submission) async {
    if (_entries.any((e) => e.submissionKey == submission.submissionKey)) {
      return;
    }
    _entries.add(submission);
  }

  @override
  Future<List<PendingDineInSubmission>> findAll() async =>
      List.unmodifiable(_entries);

  @override
  Future<void> remove(String submissionKey) async {
    _entries.removeWhere((e) => e.submissionKey == submissionKey);
  }
}

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
    this.cartFirestoreClient,
  });

  final CanonicalOrderRepository repository;
  final OrderIdentityProvider identityProvider;
  final List Function() cartItemsSnapshot;
  final String? Function() resolveCustomerId;

  /// Self-Order QR Faz 4 — when set, [submit] simulates
  /// `submitDineInOrder`'s own atomic, server-side deletion of
  /// `submittedCartLineIds` so tests can verify the shared cart actually
  /// empties after a successful submission, exactly like production.
  final FakeTableSessionCartFirestoreClient? cartFirestoreClient;

  final Map<String, dynamic> _orderIdByKey = {};
  int callCount = 0;
  String? lastTableSessionId;
  String? lastSelectedRewardId;
  String? lastSelectedCampaignId;
  List<Map<String, dynamic>>? lastRequestItems;
  String? lastGuestDisplayName;
  List<String>? lastSubmittedCartLineIds;

  String catalogRewardTitleToReturn = 'Test Ödülü';
  int catalogRewardBoncukCostToReturn = 100;
  int catalogRewardCoveredValueMinorUnitsToReturn = 12000;

  String campaignTitleToReturn = 'Test Kampanya';
  int campaignDiscountMinorUnitsToReturn = 2000;

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
    String? selectedCampaignId,
    String? guestDisplayName,
    List<String> submittedCartLineIds = const [],
  }) async {
    callCount += 1;
    lastTableSessionId = tableSessionId;
    lastSelectedRewardId = selectedRewardId;
    lastSelectedCampaignId = selectedCampaignId;
    lastGuestDisplayName = guestDisplayName;
    lastRequestItems = [for (final item in items) item.toJson()];
    lastSubmittedCartLineIds = submittedCartLineIds;

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
    // Server-Authoritative Campaign Engine P8-C.3 (2026-08-25) — mirrors
    // the catalog-reward branch above exactly, a server-confirmed campaign
    // snapshot the real `submitDineInOrder.ts` would have written.
    if (selectedCampaignId != null) {
      order = order.copyWith(
        selectedBenefitType: OrderBenefitType.campaign,
        campaign: CampaignSnapshot(
          campaignId: selectedCampaignId,
          campaignVersion: 1,
          title: campaignTitleToReturn,
          campaignType: 'percentageDiscount',
          appliedRule: const CampaignRule(
            mechanic: 'percentage',
            scopeKind: 'order',
            percentBasisPoints: 1000,
          ),
          appliedValue: 1000,
          discountMinorUnits: campaignDiscountMinorUnitsToReturn,
          orderChannel: 'dineIn',
        ),
      );
    }
    await repository.submitOrder(order);

    // Self-Order QR Faz 4 — simulates `submitDineInOrder`'s own atomic
    // deletion of exactly the consumed shared-cart lines.
    final client = cartFirestoreClient;
    if (client != null) {
      for (final lineId in submittedCartLineIds) {
        client.removeLineById(tableSessionId, lineId);
      }
    }

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

  @override
  Stream<TableGuestSessionSnapshot?> watchById(String sessionId) {
    return Stream.value(_sessions[sessionId]);
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

/// Server-Authoritative Campaign Engine P8-C.3 (2026-08-25) — mirrors
/// `delivery_checkout_screen_test.dart`'s/`reservation_flow_screen_test.dart`'s
/// own `_FakeCampaignGateway` exactly.
class _FakeCampaignGateway implements CampaignGateway {
  _FakeCampaignGateway({this.campaigns = const [], this.error});

  List<Campaign> campaigns;
  CampaignGatewayException? error;
  int calls = 0;

  @override
  Future<List<Campaign>> getActiveCampaigns() async {
    calls += 1;
    if (error != null) throw error!;
    return campaigns;
  }
}

/// A well-formed, dineIn-eligible [Campaign] for checkout tests — mirrors
/// `delivery_checkout_screen_test.dart`'s own `_testCampaign` exactly,
/// default channel adapted to this screen's own.
Campaign _testCampaign({
  String campaignId = 'camp-1',
  String title = 'Test Kampanya',
  String description = 'Bir test kampanyası.',
  List<String> eligibleChannels = const ['dineIn'],
  int? minimumBasketMinorUnits,
  List<String>? eligibleProductIds,
  int sortOrder = 0,
}) {
  return Campaign(
    campaignId: campaignId,
    title: title,
    description: description,
    campaignType: 'percentageDiscount',
    rule: const CampaignRule(
      mechanic: 'percentage',
      scopeKind: 'order',
      percentBasisPoints: 1000,
    ),
    eligibleChannels: eligibleChannels,
    eligibleProductIds: eligibleProductIds,
    eligibleCategoryIds: null,
    minimumBasketMinorUnits: minimumBasketMinorUnits,
    schedule: const CampaignSchedule(mode: 'oneTime'),
    sortOrder: sortOrder,
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
        FakeTableSessionCartFirestoreClient cartClient,
        // ignore: library_private_types_in_public_api
        _FakeDineInOfflineOrderQueueRepository queueRepository,
      })> pumpWithSeededCart(
    WidgetTester tester, {
    ActiveTableContext? tableContext,
    TableGuestSessionSnapshot? sessionSnapshot,
    AuthSession? signedInCustomer,
    // ignore: library_private_types_in_public_api
    _FakeLoyaltyGateway? loyaltyGateway,
    // ignore: library_private_types_in_public_api
    _FakeCampaignGateway? campaignGateway,
    // Self-Order QR Faz 4 — a tablemate's own lines, already present in
    // the shared cart before this device adds its own "Falafel Bowl"
    // below; lets a test set up a genuinely multi-guest cart.
    List<CartItem> otherGuestLines = const [],
    // Self-Order QR Faz 6 — defaults to "online" so every pre-existing
    // test still exercises the real submission path; a dedicated offline
    // test overrides this to exercise the queueing path instead.
    NetworkConnectivityStatus connectivityStatus =
        NetworkConnectivityStatus.online,
    // Self-Order QR Faz 6 — lets a reconnect test drive the screen's own
    // `initState` subscription directly, mirroring a real `connectivity_
    // plus` status change.
    Stream<NetworkConnectivityStatus>? connectivityStatusChanges,
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

    final fakeCartClient = FakeTableSessionCartFirestoreClient();
    final fakeQueueRepository = _FakeDineInOfflineOrderQueueRepository();
    late final ProviderContainer container;
    final gateway = _FakeSubmitDineInOrderGateway(
      repository: InMemoryCanonicalOrderRepository(),
      identityProvider: InMemoryOrderIdentityProvider(),
      cartItemsSnapshot: () => container.read(cartProvider),
      resolveCustomerId: () => signedInCustomer?.uid,
      cartFirestoreClient: fakeCartClient,
    );

    container = ProviderContainer(
      overrides: [
        tableGuestSessionFirestoreClientProvider
            .overrideWithValue(fakeSessionClient),
        // Self-Order QR Faz 3 — `cartProvider` writes through to this
        // instead of the real Firestore SDK (unavailable under
        // `flutter test`) whenever `activeTableContextProvider` is set
        // below.
        tableSessionCartFirestoreClientProvider
            .overrideWithValue(fakeCartClient),
        technicalIdentityProviderProvider.overrideWithValue(
            const _FakeTechnicalIdentityProvider('fake-firebase-uid')),
        canonicalOrderRepositoryProvider.overrideWithValue(gateway.repository),
        orderIdentityProvider.overrideWithValue(gateway.identityProvider),
        submitDineInOrderGatewayProvider.overrideWithValue(gateway),
        loyaltyGatewayProvider
            .overrideWithValue(loyaltyGateway ?? _FakeLoyaltyGateway()),
        campaignGatewayProvider
            .overrideWithValue(campaignGateway ?? _FakeCampaignGateway()),
        // Self-Order QR Faz 6 — never touch the real `connectivity_plus`
        // platform channel or `shared_preferences` plugin under
        // `flutter test`.
        networkConnectivityMonitorProvider.overrideWithValue(
          _FakeNetworkConnectivityMonitor(
            status: connectivityStatus,
            statusChanges: connectivityStatusChanges,
          ),
        ),
        dineInOfflineOrderQueueRepositoryProvider.overrideWith(
          (ref) async => fakeQueueRepository,
        ),
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
      if (otherGuestLines.isNotEmpty) {
        fakeCartClient.seed(tableContext.session.id, otherGuestLines);
      }
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
    return (
      container: container,
      gateway: gateway,
      cartClient: fakeCartClient,
      queueRepository: fakeQueueRepository,
    );
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
          'excludedIngredients': <String>[],
        },
      ]);

      final orders = pumped.container.read(ordersProvider).value!;
      expect(orders, hasLength(1));

      final updatedContext = pumped.container.read(activeTableContextProvider);
      expect(updatedContext!.session.activeOrderIds, hasLength(1));

      expect(pumped.container.read(cartProvider), isEmpty);
    },
  );

  group('Self-Order QR Faz 4 — hibrit gonderim (coklu misafir sepeti)', () {
    const otherGuestLine = CartItem(
      id: 'p2',
      name: 'Tavuk Şiş',
      desc: '',
      price: 50.0,
      quantity: 1,
      customizationsKey: 'p2',
      addedBySubAccountId: 'subaccount-tgs-1-other-guest-uid',
    );

    testWidgets('tek misafirlik sepette hibrit secim karti hic gorunmez',
        (tester) async {
      await pumpWithSeededCart(
        tester,
        tableContext: _context(),
        sessionSnapshot: TableGuestSessionSnapshot(
          status: 'active',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
      );

      expect(
          find.text('Bu siparişte kimin ürünleri gönderilsin?'), findsNothing);
    });

    testWidgets(
        'coklu misafir sepetinde hibrit secim karti gorunur, varsayilan '
        '"Sadece Kendi Ürünlerimi Gönder"dir', (tester) async {
      await pumpWithSeededCart(
        tester,
        tableContext: _context(),
        sessionSnapshot: TableGuestSessionSnapshot(
          status: 'active',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
        otherGuestLines: const [otherGuestLine],
      );

      expect(find.text('Bu siparişte kimin ürünleri gönderilsin?'),
          findsOneWidget);
      expect(find.text('Seçilen tutar: 200 TL'), findsOneWidget);
    });

    testWidgets(
        'varsayilan modda (Sadece Kendi) gonderilen items sadece kendi '
        'urunumu icerir, submittedCartLineIds de sadece benim satirimi '
        'kapsar', (tester) async {
      final pumped = await pumpWithSeededCart(
        tester,
        tableContext: _context(),
        sessionSnapshot: TableGuestSessionSnapshot(
          status: 'active',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
        otherGuestLines: const [otherGuestLine],
      );

      // The submit button's own price label always reflects the whole
      // shared cart (250 TL) — informational, matching "here's everything
      // at the table" — only the "Seçilen tutar" line above reflects the
      // scoped (own-only) amount.
      await tester.tap(
        find.widgetWithText(ElevatedButton, 'Siparişi Ver · 250 TL'),
      );
      await tester.pumpAndSettle();

      expect(pumped.gateway.lastRequestItems, [
        {
          'kind': 'product',
          'productId': 'p1',
          'quantity': 2,
          'selectedModifiers': <Map<String, String>>[],
          'note': '',
          'excludedIngredients': <String>[],
        },
      ]);
      expect(pumped.gateway.lastSubmittedCartLineIds, hasLength(1));
      // Tablemate's line stays untouched — the ownership-locked Security
      // Rule couldn't delete it anyway, but the point is this mode never
      // even tries.
      expect(
        pumped.cartClient.linesFor('tgs-1').map((item) => item.id),
        contains('p2'),
      );
    });

    testWidgets(
        '"Tüm Masayı Gönder" secilince gonderilen items herkesin '
        'urunlerini icerir ve her ikisinin satiri da silinir', (tester) async {
      final pumped = await pumpWithSeededCart(
        tester,
        tableContext: _context(),
        sessionSnapshot: TableGuestSessionSnapshot(
          status: 'active',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
        otherGuestLines: const [otherGuestLine],
      );

      await tester.tap(find.text('Tüm Masayı Gönder'));
      await tester.pumpAndSettle();
      expect(find.text('Seçilen tutar: 250 TL'), findsOneWidget);

      await tester.tap(
        find.widgetWithText(ElevatedButton, 'Siparişi Ver · 250 TL'),
      );
      await tester.pumpAndSettle();

      expect(pumped.gateway.lastRequestItems, hasLength(2));
      expect(pumped.gateway.lastSubmittedCartLineIds, hasLength(2));
      expect(pumped.container.read(cartProvider), isEmpty);
    });
  });

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
    'AP-3: guestDisplayName-required reddi bir isim dialogu acar; isim '
    'girilip onaylaninca gateway guestDisplayName ile tekrar cagrilir',
    (tester) async {
      final pumped = await pumpWithSeededCart(
        tester,
        tableContext: _context(),
        sessionSnapshot: TableGuestSessionSnapshot(
          status: 'active',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
      );

      pumped.gateway.throwOnNextSubmit = const SubmitDineInOrderException(
        'failed-precondition',
        'guestDisplayName is required before the first order at this table.',
        boncukErrorReason: 'dineIn/guest-display-name-required',
      );

      await tester.tap(
        find.widgetWithText(ElevatedButton, 'Siparişi Ver · 200 TL'),
      );
      await tester.pumpAndSettle();

      expect(pumped.gateway.callCount, 1);
      expect(find.byType(OrderSuccessScreen), findsNothing);
      expect(find.text('Adını Öğrenebilir miyiz?'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('guestDisplayNameField')),
        'Ayşe',
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Devam Et'));
      await tester.pumpAndSettle();

      expect(pumped.gateway.callCount, 2);
      expect(pumped.gateway.lastGuestDisplayName, 'Ayşe');
      expect(find.byType(OrderSuccessScreen), findsOneWidget);
    },
  );

  testWidgets(
    'AP-3: isim dialogu vazgecilirse tekrar gonderim yapilmaz, sunucu '
    'mesaji gosterilir',
    (tester) async {
      final pumped = await pumpWithSeededCart(
        tester,
        tableContext: _context(),
        sessionSnapshot: TableGuestSessionSnapshot(
          status: 'active',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
      );

      pumped.gateway.throwOnNextSubmit = const SubmitDineInOrderException(
        'failed-precondition',
        'guestDisplayName is required before the first order at this table.',
        boncukErrorReason: 'dineIn/guest-display-name-required',
      );

      await tester.tap(
        find.widgetWithText(ElevatedButton, 'Siparişi Ver · 200 TL'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Adını Öğrenebilir miyiz?'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Vazgeç'));
      await tester.pumpAndSettle();

      expect(pumped.gateway.callCount, 1);
      expect(find.byType(OrderSuccessScreen), findsNothing);
      expect(find.text('Adını Öğrenebilir miyiz?'), findsNothing);
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

  // =========================================================================
  // Server-Authoritative Campaign Engine P8-C.3 (2026-08-25) — the dine-in
  // campaign checkout wiring: [CampaignSelectionCard], mutual exclusivity
  // with a catalog reward. **LOCKED guest policy**: an anonymous table
  // guest never sees a campaign control at all, mirroring the identical,
  // already-established catalog-reward guest exclusion in this same file —
  // this file's job is the WIRING only; the server-confirmed success
  // summary itself is proven via `order_success_screen_test.dart`.
  // =========================================================================

  testWidgets(
    'P8-C.3 A: anonim misafir: kampanya karti hic gosterilmez (devre disi bile degil)',
    (tester) async {
      await pumpWithSeededCart(
        tester,
        tableContext: _context(),
        sessionSnapshot: TableGuestSessionSnapshot(
          status: 'active',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
        campaignGateway: _FakeCampaignGateway(
          campaigns: [_testCampaign(campaignId: 'c1')],
        ),
      );

      expect(find.byKey(const Key('campaignSelectionCard')), findsNothing);
      expect(find.textContaining('Kampanya'), findsNothing);
    },
  );

  testWidgets(
    'P8-C.3 B: gercek musteri: sadece dineIn-uygun kampanyalar gosterilir (client-side best-effort filtre); secim gateway\'e selectedCampaignId ile gonderilir, odul karti gizlenir',
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
        campaignGateway: _FakeCampaignGateway(campaigns: [
          _testCampaign(campaignId: 'eligible'),
          _testCampaign(
            campaignId: 'delivery-only',
            eligibleChannels: const ['delivery'],
          ),
        ]),
      );

      expect(find.byKey(const Key('catalogRewardCard')), findsOneWidget);
      expect(find.byKey(const Key('campaignTile-eligible')), findsOneWidget);
      expect(find.byKey(const Key('campaignTile-delivery-only')), findsNothing);

      await tester.tap(find.byKey(const Key('campaignTile-eligible')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('catalogRewardCard')), findsNothing);

      await tester.tap(
        find.widgetWithText(ElevatedButton, 'Siparişi Ver · 200 TL'),
      );
      await tester.pumpAndSettle();

      expect(pumped.gateway.lastSelectedCampaignId, 'eligible');
      expect(pumped.gateway.lastSelectedRewardId, isNull);
      expect(find.byType(OrderSuccessScreen), findsOneWidget);
      expect(
          find.byKey(const Key('orderSuccessCampaignSummary')), findsOneWidget);
    },
  );

  testWidgets(
    'P8-C.3 C: bir odul secmek aktif kampanya secimini kaldirir (karsilikli disarida birakma)',
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
        campaignGateway: _FakeCampaignGateway(
          campaigns: [_testCampaign(campaignId: 'c1')],
        ),
      );

      await tester.tap(find.byKey(const Key('campaignTile-c1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('catalogRewardCard')), findsNothing);

      // Deselect the campaign to bring the reward card back, then select
      // the reward — proving the reverse direction of the exclusivity too.
      await tester.tap(find.byKey(const Key('campaignTile-c1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('catalogRewardCard')), findsOneWidget);

      await tester.tap(find.byKey(const Key('catalogRewardTile-reward-1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('campaignSelectionCard')), findsNothing,
          reason: 'otherBenefitActive hides the campaign card entirely '
              'while a catalog reward is selected');

      await tester.tap(
        find.widgetWithText(ElevatedButton, 'Siparişi Ver · 200 TL'),
      );
      await tester.pumpAndSettle();
      expect(pumped.gateway.lastSelectedCampaignId, isNull);
      expect(pumped.gateway.lastSelectedRewardId, 'reward-1');
    },
  );

  testWidgets(
    'P8-C.3 D: kampanya-spesifik sunucu reddi secimi sifirlar, gateway hatasiz tekrar cagrilabilir',
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
        campaignGateway: _FakeCampaignGateway(
          campaigns: [_testCampaign(campaignId: 'c1')],
        ),
      );
      await tester.tap(find.byKey(const Key('campaignTile-c1')));
      await tester.pumpAndSettle();

      pumped.gateway.throwOnNextSubmit = const SubmitDineInOrderException(
        'failed-precondition',
        'The selected campaign has reached its usage limit.',
        boncukErrorReason: 'campaign/usage-limit-reached',
      );

      await tester.tap(
        find.widgetWithText(ElevatedButton, 'Siparişi Ver · 200 TL'),
      );
      await tester.pumpAndSettle();

      expect(pumped.gateway.callCount, 1);
      expect(find.byType(OrderSuccessScreen), findsNothing);
      expect(
        find.textContaining('Bu kampanyanın kullanım hakkı doldu',
            skipOffstage: false),
        findsOneWidget,
      );
      expect(find.byKey(const Key('campaignTile-c1')), findsOneWidget);

      pumped.gateway.throwOnNextSubmit = null;
      await tester.tap(
        find.widgetWithText(ElevatedButton, 'Siparişi Ver · 200 TL'),
      );
      await tester.pumpAndSettle();
      expect(pumped.gateway.callCount, 2);
      expect(pumped.gateway.lastSelectedCampaignId, isNull);
      expect(find.byType(OrderSuccessScreen), findsOneWidget);
    },
  );

  testWidgets(
    'P8-C.3 E: kampanya yukleme hatasi normal siparisi hic engellemez — kampanya karti sadece gosterilmez',
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
        campaignGateway: _FakeCampaignGateway(
          error: const CampaignGatewayException(
              'internal', 'Kampanyalar yüklenemedi.'),
        ),
      );

      expect(
          find.byKey(const Key('campaignSelectionCardError')), findsOneWidget);

      await tester.tap(
        find.widgetWithText(ElevatedButton, 'Siparişi Ver · 200 TL'),
      );
      await tester.pumpAndSettle();

      expect(pumped.gateway.lastSelectedCampaignId, isNull);
      expect(find.byType(OrderSuccessScreen), findsOneWidget);
    },
  );

  group('Self-Order QR Faz 6 — offline siparis kuyruklanmasi', () {
    testWidgets(
      'cihaz offline ise gateway hic cagrilmaz, siparis yerel kuyruga eklenir ve kullaniciya bildirilir',
      (tester) async {
        final pumped = await pumpWithSeededCart(
          tester,
          tableContext: _context(),
          sessionSnapshot: TableGuestSessionSnapshot(
            status: 'active',
            expiresAt: DateTime.now().add(const Duration(hours: 1)),
          ),
          connectivityStatus: NetworkConnectivityStatus.offline,
        );

        await tester.tap(
          find.widgetWithText(ElevatedButton, 'Siparişi Ver · 200 TL'),
        );
        await tester.pumpAndSettle();

        expect(pumped.gateway.callCount, 0,
            reason: 'offline iken gercek gateway hic cagrilmamali');
        expect(find.byType(OrderSuccessScreen), findsNothing);
        expect(
          find.textContaining('Bağlantı yok'),
          findsOneWidget,
        );

        final queued = await pumped.queueRepository.findAll();
        expect(queued, hasLength(1));
        expect(queued.single.tableSessionId, 'tgs-1');
        // The cart is a server-driven mirror once a submission actually
        // reaches the server (Faz 4) — an offline-queued submission never
        // reached the server, so the local cart is deliberately left
        // untouched until the real flush succeeds.
        expect(pumped.container.read(cartProvider), isNotEmpty);
      },
    );

    testWidgets(
      'yeniden baglanti sinyali gelince kuyruktaki siparis otomatik gonderilir',
      (tester) async {
        final connectivityController =
            StreamController<NetworkConnectivityStatus>.broadcast();
        addTearDown(connectivityController.close);
        final pumped = await pumpWithSeededCart(
          tester,
          tableContext: _context(),
          sessionSnapshot: TableGuestSessionSnapshot(
            status: 'active',
            expiresAt: DateTime.now().add(const Duration(hours: 1)),
          ),
          connectivityStatus: NetworkConnectivityStatus.offline,
          connectivityStatusChanges: connectivityController.stream,
        );

        await tester.tap(
          find.widgetWithText(ElevatedButton, 'Siparişi Ver · 200 TL'),
        );
        await tester.pumpAndSettle();
        expect(await pumped.queueRepository.findAll(), hasLength(1));
        expect(pumped.gateway.callCount, 0);

        connectivityController.add(NetworkConnectivityStatus.online);
        await tester.pumpAndSettle();

        expect(pumped.gateway.callCount, 1,
            reason: 'reconnect must auto-flush the queued submission');
        expect(await pumped.queueRepository.findAll(), isEmpty);
      },
    );
  });
}
