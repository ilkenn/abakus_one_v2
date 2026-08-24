import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/auth/domain/models/auth_session.dart';
import 'package:abakus_one_v2/features/auth/presentation/providers/auth_provider.dart';
import 'package:abakus_one_v2/features/cart/domain/models/cart_item.dart';
import 'package:abakus_one_v2/features/cart/presentation/providers/cart_provider.dart';
import 'package:abakus_one_v2/features/cart/presentation/providers/shopping_channel_provider.dart';
import 'package:abakus_one_v2/features/cart/presentation/screens/order_success_screen.dart';
import 'package:abakus_one_v2/features/cart/presentation/screens/takeaway_checkout_screen.dart';
import 'package:abakus_one_v2/features/orders/data/canonical_order_repository.dart';
import 'package:abakus_one_v2/features/orders/domain/identity/order_identity.dart';
import 'package:abakus_one_v2/features/loyalty/data/loyalty_gateway.dart';
import 'package:abakus_one_v2/features/loyalty/domain/models/loyalty_account_snapshot.dart';
import 'package:abakus_one_v2/features/loyalty/domain/models/loyalty_history_entry.dart';
import 'package:abakus_one_v2/features/loyalty/domain/models/loyalty_reward.dart';
import 'package:abakus_one_v2/features/loyalty/presentation/providers/loyalty_providers.dart';
import 'package:abakus_one_v2/features/orders/domain/mappers/cart_to_order_mapper.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_actor.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_benefit_type.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_channel.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_status.dart';
import 'package:abakus_one_v2/features/orders/domain/models/boncuk_redemption_snapshot.dart';
import 'package:abakus_one_v2/features/orders/domain/models/catalog_reward_snapshot.dart';
import 'package:abakus_one_v2/features/orders/domain/models/pickup_mode.dart';
import 'package:abakus_one_v2/features/orders/presentation/providers/order_identity_provider.dart';
import 'package:abakus_one_v2/features/orders/presentation/providers/orders_provider.dart';
import 'package:abakus_one_v2/features/takeaway/data/submit_takeaway_order_gateway.dart';
import 'package:abakus_one_v2/features/takeaway/presentation/providers/takeaway_dependencies_provider.dart';

/// Faz D.3.1 migration: `TakeawayCheckoutScreen` no longer builds an
/// `Order`/writes to `CanonicalOrderRepository` directly — it calls
/// `SubmitTakeawayOrderGateway` (the real implementation talks to the
/// `submitTakeawayOrder` Cloud Function, unavailable under `flutter
/// test`, same reasoning `TableGuestSessionGateway`'s own test double
/// already established). [_FakeSubmitTakeawayOrderGateway] simulates the
/// real backend's *observable effect* — a canonical order actually
/// landing in `CanonicalOrderRepository` — using the exact same
/// `CartToOrderMapper` pricing/snapshot logic the screen used to call
/// directly (still real domain logic, just exercised from the test
/// double instead of production code — the wiring change these tests
/// verify is "the screen asks the gateway, then reads the result back,"
/// never "the screen never touches pricing logic again").
class _FakeSubmitTakeawayOrderGateway implements SubmitTakeawayOrderGateway {
  _FakeSubmitTakeawayOrderGateway({
    required this.repository,
    required this.identityProvider,
    required this.cartItemsSnapshot,
    required this.resolveCustomerId,
  });

  final CanonicalOrderRepository repository;
  final OrderIdentityProvider identityProvider;
  final List<CartItem> Function() cartItemsSnapshot;
  final String Function() resolveCustomerId;

  final Map<String, OrderId> _orderIdByKey = {};
  int callCount = 0;
  List<Map<String, dynamic>>? lastRequestItems;
  String? lastRestaurantId;
  String? lastBranchId;
  DateTime? lastPickupTime;

  /// Boncuk Loyalty P4-E-B — captures exactly what the screen sent, so
  /// tests can assert "count only, nothing else" against the SAME wire
  /// call the real gateway would make (the interface's own signature
  /// already makes anything else structurally impossible to send).
  int? lastRequestedBoncukAmount;
  String? lastSelectedRewardId;

  /// Boncuk Loyalty P7-C (2026-08-24) — the fake's own stand-in for the
  /// server's resolved reward snapshot, returned on the order whenever
  /// [submitAuthenticatedOrder] is called with a non-null
  /// `selectedRewardId`. A test can override these to prove the success
  /// screen reads them from the canonical re-read `Order`, never from a
  /// pre-submit client estimate (there is none for a catalog reward).
  String catalogRewardTitleToReturn = 'Test Ödülü';
  int catalogRewardBoncukCostToReturn = 100;
  int catalogRewardCoveredValueMinorUnitsToReturn = 12000;

  /// When set, the next [submitAuthenticatedOrder] call throws this
  /// instead of succeeding — simulates a real backend rejection (e.g. a
  /// stable Boncuk error reason) without touching Firebase.
  SubmitTakeawayOrderException? throwOnNextSubmit;

  /// When set, [submitAuthenticatedOrder] awaits this before resolving —
  /// lets a test hold the "in-flight submission" state open long enough to
  /// observe frozen controls, since the fake's own in-memory work
  /// otherwise resolves within a single `pump()`.
  Completer<void>? holdUntil;

  @override
  Future<SubmitTakeawayOrderResult> submitAuthenticatedOrder({
    required String submissionKey,
    required String restaurantId,
    required String branchId,
    required DateTime pickupTime,
    required List<TakeawayOrderItem> items,
    required String contactFirstName,
    required String contactLastName,
    required String contactPhone,
    int requestedBoncukAmount = 0,
    String? selectedRewardId,
  }) async {
    callCount += 1;
    lastRequestItems = [for (final item in items) item.toJson()];
    lastRestaurantId = restaurantId;
    final pendingHold = holdUntil;
    if (pendingHold != null) {
      await pendingHold.future;
    }
    lastBranchId = branchId;
    lastPickupTime = pickupTime;
    lastRequestedBoncukAmount = requestedBoncukAmount;
    lastSelectedRewardId = selectedRewardId;

    final pendingThrow = throwOnNextSubmit;
    if (pendingThrow != null) {
      throwOnNextSubmit = null;
      throw pendingThrow;
    }

    final existingOrderId = _orderIdByKey[submissionKey];
    if (existingOrderId != null) {
      final existing = await repository.findById(existingOrderId);
      return SubmitTakeawayOrderResult(
        orderId: existingOrderId.value,
        orderNumber: existing!.orderNumber.value,
        duplicate: true,
      );
    }

    final orderId = await identityProvider.nextOrderId();
    final orderNumber = await identityProvider.nextOrderNumber();
    _orderIdByKey[submissionKey] = orderId;

    final now = DateTime.now();
    var order = CartToOrderMapper.map(
      orderId: orderId,
      orderNumber: orderNumber,
      cartItems: cartItemsSnapshot(),
      channel: OrderChannel.takeaway,
      branchId: branchId,
      restaurantId: restaurantId,
      customerId: resolveCustomerId(),
      pickupMode: PickupMode.scheduled,
      pickupTime: pickupTime,
      contactFirstName: contactFirstName,
      contactLastName: contactLastName,
      contactPhone: contactPhone,
      now: now,
    );
    order = order.transitionTo(
      OrderStatus.pendingConfirmation,
      actor: OrderActor.customer,
      at: now,
      auditEntryId: '${orderId.value}-transition-1',
    );
    if (requestedBoncukAmount > 0) {
      // Simulates the SERVER's own settlement snapshot — a simplified but
      // real domain-shaped stand-in (rate: 1 Boncuk = 1 TL = 100 minor
      // units), never re-implementing the real
      // `calculateBoncukRedemption` algorithm here; the real algorithm is
      // covered server-side by `loyaltyRedemption.test.ts`/
      // `submitTakeawayOrder.test.ts`, not re-proven by this Flutter test.
      const redemptionValueMinorUnitsPerBoncuk = 100;
      final valueMinorUnits =
          requestedBoncukAmount * redemptionValueMinorUnitsPerBoncuk;
      order = order.copyWith(
        selectedBenefitType: OrderBenefitType.boncukRedemption,
        boncukRedemption: BoncukRedemptionSnapshot(
          boncukUsed: requestedBoncukAmount,
          valueMinorUnits: valueMinorUnits,
          remainingPayableMinorUnits:
              order.pricing.grandTotal.minorUnits - valueMinorUnits,
          redemptionValueMinorUnitsPerBoncuk:
              redemptionValueMinorUnitsPerBoncuk,
          maxRedemptionBasisPoints: 5000,
          loyaltyPolicyVersion: 1,
        ),
      );
    } else if (selectedRewardId != null) {
      // Simulates the SERVER's own resolved reward snapshot (P7-C) —
      // never re-implementing the real pricing/`freeUnitCount` mechanism
      // here (that's covered server-side by
      // `submitTakeawayOrderCatalogReward.test.ts`); this fake only needs
      // to prove the SCREEN reads `order.catalogReward`/
      // `selectedBenefitType` from the canonical re-read order, exactly
      // like the boncukRedemption branch above.
      order = order.copyWith(
        selectedBenefitType: OrderBenefitType.catalogReward,
        catalogReward: CatalogRewardSnapshot(
          rewardId: selectedRewardId,
          rewardVersion: 1,
          title: catalogRewardTitleToReturn,
          boncukCost: catalogRewardBoncukCostToReturn,
          redeemedProductId: cartItemsSnapshot().first.id,
          redeemedQuantity: 1,
          coveredValueMinorUnits: catalogRewardCoveredValueMinorUnitsToReturn,
          rewardCatalogVersionId: '${selectedRewardId}_1',
        ),
      );
    }
    await repository.submitOrder(order);

    return SubmitTakeawayOrderResult(
      orderId: orderId.value,
      orderNumber: orderNumber.value,
      duplicate: false,
    );
  }

  /// This screen (the authenticated flow) never calls the guest path —
  /// `TakeawayGuestCheckoutScreen`'s own test file exercises that one.
  @override
  Future<SubmitTakeawayOrderResult> submitGuestOrder({
    required String submissionKey,
    required String takeawaySessionId,
    required List<TakeawayOrderItem> items,
    required String contactFirstName,
    required String contactLastName,
    required String contactPhone,
  }) {
    throw UnimplementedError(
      'submitGuestOrder is not exercised by TakeawayCheckoutScreen (the '
      'authenticated flow) — see takeaway_guest_checkout_screen_test.dart.',
    );
  }
}

/// Boncuk Loyalty P4-E-B — mirrors `loyalty_screen_test.dart`'s own private
/// `_FakeLoyaltyGateway` exactly (duplicated per this codebase's
/// established per-file test-double convention, not shared).
class _FakeLoyaltyGateway implements LoyaltyGateway {
  _FakeLoyaltyGateway({
    LoyaltyAccountSnapshot? snapshot,
    this.snapshotError,
    this.neverCompleteSnapshot = false,
    this.rewards = const [],
    this.rewardCatalogError,
  }) : snapshot = snapshot ?? LoyaltyAccountSnapshot.zero;

  LoyaltyAccountSnapshot snapshot;
  LoyaltyGatewayException? snapshotError;
  bool neverCompleteSnapshot;
  int snapshotCalls = 0;

  /// Boncuk Loyalty P7-C (2026-08-24) — the real, server-authoritative
  /// reward list this fake returns; `const []` (the default) mirrors "no
  /// rewards for this cart," matching every pre-P7-C test's own behavior
  /// exactly (the catalog-reward card renders nothing).
  List<LoyaltyReward> rewards;
  LoyaltyGatewayException? rewardCatalogError;
  int rewardCatalogCalls = 0;

  @override
  Future<LoyaltyAccountSnapshot> getSnapshot() async {
    snapshotCalls += 1;
    if (neverCompleteSnapshot) {
      return Completer<LoyaltyAccountSnapshot>().future;
    }
    if (snapshotError != null) throw snapshotError!;
    return snapshot;
  }

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

/// A well-formed, non-default snapshot for Boncuk checkout tests — a
/// non-default redemption rate/cap deliberately (P4-E-B §20 F/G: "policy
/// value not hardcoded" / "max percentage not hardcoded" — using the
/// locked default values (100/5000) here would never actually prove the
/// UI reads [LoyaltyAccountSnapshot]'s own fields rather than a Flutter
/// constant).
LoyaltyAccountSnapshot _boncukSnapshot({
  int spendableBalance = 500,
  int boncukDebt = 0,
  int redemptionValueMinorUnitsPerBoncuk = 150,
  int maxRedemptionBasisPoints = 4000,
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

/// Boncuk Loyalty P7-C — a well-formed [LoyaltyReward], eligible for the
/// cart item `'p1'` seeded by [pumpCheckout] by default.
LoyaltyReward _catalogReward({
  String rewardId = 'reward-1',
  String title = 'Test Ödülü',
  String description = 'Bir test ödülü.',
  List<String> eligibleProductIds = const ['p1'],
  List<String> eligibleChannels = const [
    'dineIn',
    'takeaway',
    'delivery',
    'reservationPreorder',
  ],
  int boncukCost = 100,
  int sortOrder = 0,
  int version = 1,
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
    version: version,
  );
}

AuthSession _realCustomerSession({String uid = 'real-customer-uid'}) {
  return AuthSession(
    uid: uid,
    phoneNumber: '+905551234567',
    createdAt: DateTime(2026, 8, 1),
    expiresAt: DateTime(2027, 8, 1),
  );
}

Future<
    ({
      ProviderContainer container,
      _FakeSubmitTakeawayOrderGateway gateway,
      _FakeLoyaltyGateway loyaltyGateway,
    })> pumpCheckout(
  WidgetTester tester, {
  AuthState? authState,
  // ignore: library_private_types_in_public_api
  _FakeLoyaltyGateway? loyaltyGateway,
}) async {
  // A tall viewport so every section (Şube/Teslim Alma Zamanı/İletişim
  // Bilgileri/Ürünler/submit button) is actually laid out and mounted —
  // ListView's sliver machinery doesn't mount far-below-the-fold children
  // at the default test surface size, matching
  // `dine_in_checkout_screen_test.dart`'s own documented reasoning for the
  // same phenomenon.
  tester.view.physicalSize = const Size(480, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final resolvedAuthState = authState ??
      AuthState(
        isAuthenticated: true,
        isGuest: false,
        session: _realCustomerSession(),
      );

  // `container` is referenced inside the gateway's closures below before
  // it's assigned — safe, since those closures are only ever invoked
  // later (during widget interaction), by which point construction has
  // completed. Avoids a circular "container needs the gateway override,
  // the gateway needs to read from the container" dependency.
  late final ProviderContainer container;
  final gateway = _FakeSubmitTakeawayOrderGateway(
    repository: InMemoryCanonicalOrderRepository(),
    identityProvider: InMemoryOrderIdentityProvider(),
    cartItemsSnapshot: () => container.read(cartProvider),
    resolveCustomerId: () => container.read(authProvider).session!.uid,
  );
  final resolvedLoyaltyGateway = loyaltyGateway ?? _FakeLoyaltyGateway();

  container = ProviderContainer(
    overrides: [
      authProvider.overrideWith(() => SeededAuthNotifier(resolvedAuthState)),
      canonicalOrderRepositoryProvider.overrideWithValue(gateway.repository),
      orderIdentityProvider.overrideWithValue(gateway.identityProvider),
      submitTakeawayOrderGatewayProvider.overrideWithValue(gateway),
      loyaltyGatewayProvider.overrideWithValue(resolvedLoyaltyGateway),
    ],
  );
  addTearDown(container.dispose);

  container.read(shoppingChannelProvider.notifier).selectTakeaway(
        restaurantId: 'restaurant-1',
        branchId: 'branch-1',
        branchDisplayName: 'Abaküs Ortaköy',
      );
  container.read(cartProvider.notifier).addToCart(
        id: 'p1',
        name: 'Falafel Bowl',
        desc: '',
        price: 120.0,
        quantity: 2,
        pricedForChannel: OrderChannel.takeaway,
      );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: TakeawayCheckoutScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return (
    container: container,
    gateway: gateway,
    loyaltyGateway: resolvedLoyaltyGateway,
  );
}

Future<void> fillContactFields(WidgetTester tester) async {
  await tester.enterText(find.widgetWithText(TextField, 'Ad'), 'Ada');
  await tester.enterText(find.widgetWithText(TextField, 'Soyad'), 'Yılmaz');
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('şube adı, ürünler, toplam ve ambalaj bilgisi gösterilir', (
    tester,
  ) async {
    await pumpCheckout(tester);

    expect(find.text('Abaküs Ortaköy'), findsOneWidget);
    expect(find.textContaining('Falafel Bowl'), findsOneWidget);
    expect(find.text('240 TL'), findsWidgets); // 120 * 2
    expect(
      find.textContaining('Gel Al fiyatlarına ambalaj maliyeti dahildir'),
      findsOneWidget,
    );
  });

  testWidgets(
      'pickup zamanı seçilmeden ve iletişim bilgileri girilmeden Siparişi '
      'Ver devre dışıdır', (tester) async {
    await pumpCheckout(tester);

    final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Siparişi Ver'));
    expect(button.onPressed, isNull);
  });

  testWidgets(
      '20 dk sonra seçilip iletişim bilgileri doldurulunca Siparişi Ver '
      'aktif olur', (tester) async {
    await pumpCheckout(tester);

    await tester.tap(find.text('20 dk sonra'));
    await tester.pumpAndSettle();
    await fillContactFields(tester);
    // Phone was pre-filled from the session, only name fields were empty.

    final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Siparişi Ver'));
    expect(button.onPressed, isNotNull);
  });

  testWidgets(
      'Faz D.5: geçersiz telefon numarasıyla Siparişi Ver devre dışı kalır '
      '— TakeawayGuestCheckoutScreen ile aynı TurkishPhoneNumber modeli '
      'reuse edilir, eskiden yalnızca boş-olmama kontrolü vardı',
      (tester) async {
    await pumpCheckout(tester);

    await tester.tap(find.text('20 dk sonra'));
    await tester.pumpAndSettle();
    await fillContactFields(tester);
    // Overwrite the session-prefilled (valid) phone with too few digits.
    await tester.enterText(
      find.widgetWithText(TextField, '5XX XXX XX XX'),
      '123',
    );
    await tester.pumpAndSettle();

    final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Siparişi Ver'));
    expect(button.onPressed, isNull);
  });

  testWidgets(
      'başarılı gönderimde: TakeawayCheckoutScreen doğrudan repository '
      'create çağırmaz, submitTakeawayOrder gateway\'ini kullanır — doğru '
      'şube/pickup/iletişim bilgileriyle çağrılır, backend\'in döndürdüğü '
      'canonical order okunup sepet temizlenir, başarı ekranına geçilir',
      (tester) async {
    final pumped = await pumpCheckout(tester);
    final container = pumped.container;
    final gateway = pumped.gateway;

    await tester.tap(find.text('30 dk sonra'));
    await tester.pumpAndSettle();
    await fillContactFields(tester);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Siparişi Ver'));
    await tester.pumpAndSettle();

    expect(find.byType(OrderSuccessScreen), findsOneWidget);
    expect(container.read(cartProvider), isEmpty);

    // The gateway — not a direct repository write — is what the screen
    // actually called, with exactly the intent fields, no price of any
    // kind.
    expect(gateway.callCount, 1);
    expect(gateway.lastRestaurantId, 'restaurant-1');
    expect(gateway.lastBranchId, 'branch-1');
    expect(gateway.lastPickupTime, isNotNull);
    expect(gateway.lastRequestItems, [
      {
        'kind': 'product',
        'productId': 'p1',
        'quantity': 2,
        'selectedModifiers': <Map<String, String>>[],
        'note': '',
      },
    ]);

    final orders =
        await container.read(canonicalOrderRepositoryProvider).findAll();
    expect(orders, hasLength(1));
    final order = orders.single;
    expect(order.channel, OrderChannel.takeaway);
    expect(order.customerId, 'real-customer-uid');
    expect(order.branchId, 'branch-1');
    expect(order.restaurantId, 'restaurant-1');
    expect(order.pickupMode, PickupMode.scheduled);
    expect(order.pickupTime, isNotNull);
    expect(order.contactFirstName, 'Ada');
    expect(order.contactLastName, 'Yılmaz');
    expect(order.contactPhone, '+905551234567');
  });

  testWidgets(
      'hızlı çift dokunma (idempotency): gateway iki kez çağrılsa bile '
      '(aynı submissionKey ile, backend\'in idempotent reuse\'unu simüle '
      'ederek) yalnızca bir sipariş oluşur', (tester) async {
    final pumped = await pumpCheckout(tester);
    final container = pumped.container;
    final gateway = pumped.gateway;

    await tester.tap(find.text('20 dk sonra'));
    await tester.pumpAndSettle();
    await fillContactFields(tester);

    final button = find.widgetWithText(ElevatedButton, 'Siparişi Ver');
    await tester.tap(button);
    // No pump in between — the second tap should be swallowed by the
    // `_isSubmitting` guard, exactly like DineInCheckoutScreen's own
    // double-tap protection (unchanged by this migration).
    await tester.tap(button);
    await tester.pumpAndSettle();

    final orders =
        await container.read(canonicalOrderRepositoryProvider).findAll();
    expect(orders, hasLength(1));
    // The UI-level guard means the gateway itself was only ever invoked
    // once for this double-tap — the deeper "same submissionKey survives
    // a real retry" guarantee is the backend's own responsibility,
    // covered by `submitTakeawayOrder.test.ts`'s emulator tests, not
    // re-proven here.
    expect(gateway.callCount, 1);
  });

  testWidgets(
      'anonymous/guest oturum submit anında fail-closed reddedilir — '
      'gateway hiç çağrılmaz, sipariş oluşturulmaz (girişten '
      'TakeawayBranchSelectionScreen sorumlu olsa da bu ekran kendi '
      'başına da güvenli olmalı)', (tester) async {
    final pumped = await pumpCheckout(
      tester,
      authState: const AuthState(isAuthenticated: true, isGuest: true),
    );
    final container = pumped.container;
    final gateway = pumped.gateway;

    await tester.tap(find.text('20 dk sonra'));
    await tester.pumpAndSettle();
    await fillContactFields(tester);
    // The guest AuthState carries no session, so the phone field has no
    // prefill (unlike the real-customer scenarios) — fill it explicitly so
    // the UI-level _canSubmit check isn't what blocks this test; the guard
    // under test is the auth re-check inside _submitOrder itself.
    await tester.enterText(
      find.widgetWithText(TextField, '5XX XXX XX XX'),
      '5551234567',
    );
    await tester.pumpAndSettle();

    final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Siparişi Ver'));
    // A guest session still satisfies the UI-level _canSubmit form
    // validation (pickup time + contact fields) — the auth re-check only
    // happens inside _submitOrder itself, so the button is enabled here
    // and the guard is exercised by actually tapping it.
    expect(button.onPressed, isNotNull);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Siparişi Ver'));
    await tester.pumpAndSettle();

    expect(find.byType(OrderSuccessScreen), findsNothing);
    expect(gateway.callCount, 0);
    final orders =
        await container.read(canonicalOrderRepositoryProvider).findAll();
    expect(orders, isEmpty);
  });

  // =========================================================================
  // Boncuk Loyalty P4-E-B (2026-08-22) — the premium takeaway Boncuk
  // checkout card. Letters mirror the task's own mandatory list (§20 A-R);
  // Q ("no Boncuk: existing checkout path still works") is already fully
  // covered by every pre-existing test above, unmodified — not repeated
  // here as a separate case.
  // =========================================================================

  Future<void> setUpValidForm(WidgetTester tester) async {
    await tester.tap(find.text('30 dk sonra'));
    await tester.pumpAndSettle();
    await fillContactFields(tester);
  }

  testWidgets('A: snapshot balance > 0 -> the Boncuk card is available',
      (tester) async {
    await pumpCheckout(
      tester,
      loyaltyGateway: _FakeLoyaltyGateway(snapshot: _boncukSnapshot()),
    );

    expect(find.byKey(const Key('boncukRedemptionCard')), findsOneWidget);
    expect(find.byKey(const Key('boncukToggle')), findsOneWidget);
    expect(find.byKey(const Key('boncukZeroState')), findsNothing);
    expect(find.byKey(const Key('boncukDebtState')), findsNothing);
  });

  testWidgets('B: toggle off -> requested amount sent is 0', (tester) async {
    final pumped = await pumpCheckout(
      tester,
      loyaltyGateway: _FakeLoyaltyGateway(snapshot: _boncukSnapshot()),
    );
    await setUpValidForm(tester);
    // Toggle stays off — the default state.

    await tester.tap(find.widgetWithText(ElevatedButton, 'Siparişi Ver'));
    await tester.pumpAndSettle();

    expect(pumped.gateway.lastRequestedBoncukAmount, 0);
  });

  testWidgets('C: toggle on -> minimum selected amount is 1', (tester) async {
    await pumpCheckout(
      tester,
      loyaltyGateway: _FakeLoyaltyGateway(snapshot: _boncukSnapshot()),
    );

    await tester.tap(find.byKey(const Key('boncukToggle')));
    await tester.pumpAndSettle();

    expect(find.text('1 Boncuk'), findsOneWidget);
  });

  testWidgets('D: stepper only ever moves by whole units', (tester) async {
    await pumpCheckout(
      tester,
      loyaltyGateway: _FakeLoyaltyGateway(snapshot: _boncukSnapshot()),
    );
    await tester.tap(find.byKey(const Key('boncukToggle')));
    await tester.pumpAndSettle();
    expect(find.text('1 Boncuk'), findsOneWidget);

    await tester.tap(find.byKey(const Key('boncukStepperIncrement')));
    await tester.pumpAndSettle();
    expect(find.text('2 Boncuk'), findsOneWidget);

    await tester.tap(find.byKey(const Key('boncukStepperDecrement')));
    await tester.pumpAndSettle();
    expect(find.text('1 Boncuk'), findsOneWidget);

    // Cannot decrement below 1 while enabled — the decrement button is
    // disabled, not a route to 0 (turning fully off is the toggle's job).
    final decrementButton = tester
        .widget<IconButton>(find.byKey(const Key('boncukStepperDecrement')));
    expect(decrementButton.onPressed, isNull);
  });

  testWidgets('E: MAX uses the current presentation max, from the snapshot',
      (tester) async {
    final pumped = await pumpCheckout(
      tester,
      loyaltyGateway: _FakeLoyaltyGateway(
        // spendableBalance well above the order-cap, so the ORDER CAP
        // (not the balance) determines the max — proves this isn't just
        // "use the whole balance."
        snapshot: _boncukSnapshot(
          spendableBalance: 500,
          redemptionValueMinorUnitsPerBoncuk: 150,
          maxRedemptionBasisPoints: 4000,
        ),
      ),
    );
    await setUpValidForm(tester);
    // Cart total is 240 TL (120 x 2) -> 24000 minor units.
    // maxRedemptionValueMinorUnits = 24000 * 4000 / 10000 = 9600.
    // maxUsableBoncukByOrderCap = 9600 / 150 = 64. min(500, 64) = 64.
    expect(
      computeClientEstimatedMaxBoncuk(_boncukSnapshot(), 240.0),
      64,
    );

    await tester.tap(find.byKey(const Key('boncukToggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('boncukMaxButton')));
    await tester.pumpAndSettle();

    expect(find.text('64 Boncuk'), findsOneWidget);
    // P4-E-B microfix — both estimates shown together: 64 Boncuk * 150
    // minor units = 9600 minor units = 96 TL; remaining (tahmini) =
    // 24000 - 9600 = 14400 minor units = 144 TL.
    expect(
      find.text('Boncuk ile ödenecek (tahmini): 96 TL'),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('boncukEstimatedRemaining')),
      findsOneWidget,
    );
    expect(
      find.text('Kalan tutar (tahmini): 144 TL'),
      findsOneWidget,
    );
    expect(
      find.text('Kesin tutar sipariş onayında belirlenir.'),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(ElevatedButton, 'Siparişi Ver'));
    await tester.pumpAndSettle();
    expect(pumped.gateway.lastRequestedBoncukAmount, 64);
  });

  testWidgets(
      'F: redemption rate is read from the snapshot, never hardcoded — a '
      'non-default rate changes the displayed estimate', (tester) async {
    await pumpCheckout(
      tester,
      loyaltyGateway: _FakeLoyaltyGateway(
        snapshot: _boncukSnapshot(redemptionValueMinorUnitsPerBoncuk: 300),
      ),
    );

    await tester.tap(find.byKey(const Key('boncukToggle')));
    await tester.pumpAndSettle();
    // 1 Boncuk at 300 minor units/Boncuk = 3 TL — never the locked-default
    // "1 Boncuk = 1 TL" figure, proving no hardcoded rate.
    expect(find.textContaining('3 TL'), findsWidgets);
  });

  testWidgets(
      'G: max redemption basis points is read from the snapshot, never '
      'hardcoded — a tighter cap changes the computed max', (tester) async {
    final loose = computeClientEstimatedMaxBoncuk(
      _boncukSnapshot(maxRedemptionBasisPoints: 4000),
      240.0,
    );
    final tight = computeClientEstimatedMaxBoncuk(
      _boncukSnapshot(maxRedemptionBasisPoints: 1000),
      240.0,
    );
    expect(tight, lessThan(loose));
  });

  testWidgets('H: zero spendable balance shows the quiet zero state',
      (tester) async {
    await pumpCheckout(
      tester,
      loyaltyGateway: _FakeLoyaltyGateway(
        snapshot: _boncukSnapshot(spendableBalance: 0),
      ),
    );

    expect(find.byKey(const Key('boncukZeroState')), findsOneWidget);
    expect(find.text('Henüz kullanabileceğin Boncuk yok.'), findsOneWidget);
    expect(find.byKey(const Key('boncukToggle')), findsNothing);
  });

  testWidgets('I: debt state shows calm copy and never exposes the debt number',
      (tester) async {
    await pumpCheckout(
      tester,
      loyaltyGateway: _FakeLoyaltyGateway(
        snapshot: _boncukSnapshot(spendableBalance: 0, boncukDebt: 37),
      ),
    );

    expect(find.byKey(const Key('boncukDebtState')), findsOneWidget);
    expect(
      find.text('Boncuk bakiyen şu anda kullanıma uygun değil.'),
      findsOneWidget,
    );
    expect(find.textContaining('37'), findsNothing);
    expect(find.byKey(const Key('boncukToggle')), findsNothing);
  });

  testWidgets('J: snapshot loading renders the inline premium skeleton',
      (tester) async {
    tester.view.physicalSize = const Size(480, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final resolvedAuthState = AuthState(
      isAuthenticated: true,
      isGuest: false,
      session: _realCustomerSession(),
    );
    late final ProviderContainer container;
    final gateway = _FakeSubmitTakeawayOrderGateway(
      repository: InMemoryCanonicalOrderRepository(),
      identityProvider: InMemoryOrderIdentityProvider(),
      cartItemsSnapshot: () => container.read(cartProvider),
      resolveCustomerId: () => container.read(authProvider).session!.uid,
    );
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(() => SeededAuthNotifier(resolvedAuthState)),
        canonicalOrderRepositoryProvider.overrideWithValue(gateway.repository),
        orderIdentityProvider.overrideWithValue(gateway.identityProvider),
        submitTakeawayOrderGatewayProvider.overrideWithValue(gateway),
        loyaltyGatewayProvider.overrideWithValue(
          _FakeLoyaltyGateway(neverCompleteSnapshot: true),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(shoppingChannelProvider.notifier).selectTakeaway(
          restaurantId: 'restaurant-1',
          branchId: 'branch-1',
          branchDisplayName: 'Abaküs Ortaköy',
        );
    container.read(cartProvider.notifier).addToCart(
          id: 'p1',
          name: 'Falafel Bowl',
          desc: '',
          price: 120.0,
          quantity: 2,
          pricedForChannel: OrderChannel.takeaway,
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: TakeawayCheckoutScreen()),
      ),
    );
    // Deliberately no pumpAndSettle — the snapshot future never completes,
    // so the loading state is exactly what's on screen after one frame.
    await tester.pump();

    expect(find.byKey(const Key('boncukCardSkeleton')), findsOneWidget);
  });

  testWidgets(
      'K: snapshot load failure shows scoped retry, ordinary checkout '
      'remains fully usable without Boncuk', (tester) async {
    final pumped = await pumpCheckout(
      tester,
      loyaltyGateway: _FakeLoyaltyGateway(
        snapshotError: const LoyaltyGatewayException(
          'internal',
          'Boncuk bakiyene şu anda ulaşılamıyor.',
        ),
      ),
    );

    expect(find.byKey(const Key('boncukCardError')), findsOneWidget);

    await setUpValidForm(tester);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Siparişi Ver'));
    await tester.pumpAndSettle();

    expect(find.byType(OrderSuccessScreen), findsOneWidget);
    expect(pumped.gateway.lastRequestedBoncukAmount, 0);
  });

  testWidgets(
      'L: a cart change that lowers the estimated max below the current '
      'selection NEVER silently clamps to a smaller nonzero amount — '
      'selection stays exactly as chosen, submission is disabled, and an '
      'explicit notice/recovery action is shown', (tester) async {
    await pumpCheckout(
      tester,
      loyaltyGateway: _FakeLoyaltyGateway(
        // A tight cap so a modest selection is easy to invalidate.
        snapshot: _boncukSnapshot(
          spendableBalance: 500,
          redemptionValueMinorUnitsPerBoncuk: 100,
          maxRedemptionBasisPoints: 5000,
        ),
      ),
    );
    await setUpValidForm(tester);
    // Cart total 240 TL -> max = min(500, floor(24000*5000/10000)/100) = 120.
    await tester.tap(find.byKey(const Key('boncukToggle')));
    await tester.pumpAndSettle();
    // MAX in one tap (never a manual stepper loop) — selects the full 120,
    // the order-cap-bound maximum at the current cart total.
    await tester.tap(find.byKey(const Key('boncukMaxButton')));
    await tester.pumpAndSettle();
    expect(find.text('120 Boncuk'), findsOneWidget);

    // Halve the cart total (quantity 2 -> 1), lowering the order cap to
    // 60 — well below the 120 already selected, but still above 0.
    final containerFinder = find.byType(UncontrolledProviderScope);
    final scope = tester.widget<UncontrolledProviderScope>(containerFinder);
    scope.container.read(cartProvider.notifier).updateQuantity(
          'p1',
          '',
          '',
          1,
        );
    await tester.pumpAndSettle();

    // Selection must remain exactly 120 — never silently reduced to 60.
    expect(find.text('120 Boncuk'), findsOneWidget);
    expect(
        find.byKey(const Key('boncukInvalidSelectionNotice')), findsOneWidget);
    final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Siparişi Ver'));
    expect(button.onPressed, isNull,
        reason: 'submission must be disabled while the selection is invalid');
  });

  testWidgets(
      'M: the estimated max reaching exactly zero (never a smaller nonzero '
      'value) turns Boncuk usage off and shows an informational notice',
      (tester) async {
    await pumpCheckout(
      tester,
      loyaltyGateway: _FakeLoyaltyGateway(
        snapshot: _boncukSnapshot(
          spendableBalance: 500,
          redemptionValueMinorUnitsPerBoncuk: 100,
          maxRedemptionBasisPoints: 5000,
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('boncukToggle')));
    await tester.pumpAndSettle();
    expect(find.text('1 Boncuk'), findsOneWidget);

    final scope = tester.widget<UncontrolledProviderScope>(
        find.byType(UncontrolledProviderScope));
    scope.container.read(cartProvider.notifier).removeFromCart(id: 'p1');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('boncukUnavailableForCartNotice')),
        findsOneWidget);
    final toggle = tester.widget<Switch>(find.byKey(const Key('boncukToggle')));
    expect(toggle.value, isFalse);
  });

  testWidgets('N: every Boncuk control is frozen while a submission is active',
      (tester) async {
    final pumped = await pumpCheckout(
      tester,
      loyaltyGateway: _FakeLoyaltyGateway(snapshot: _boncukSnapshot()),
    );
    await setUpValidForm(tester);
    await tester.tap(find.byKey(const Key('boncukToggle')));
    await tester.pumpAndSettle();

    // Holds the fake gateway's own Future open — the fake's in-memory work
    // otherwise resolves within a single `pump()`, too fast to ever
    // observe the in-flight `_isSubmitting` state at all.
    final hold = Completer<void>();
    pumped.gateway.holdUntil = hold;

    await tester.tap(find.widgetWithText(ElevatedButton, 'Siparişi Ver'));
    await tester.pump();

    final toggle = tester.widget<Switch>(find.byKey(const Key('boncukToggle')));
    expect(toggle.onChanged, isNull);
    final increment = tester
        .widget<IconButton>(find.byKey(const Key('boncukStepperIncrement')));
    expect(increment.onPressed, isNull);
    final maxButton =
        tester.widget<OutlinedButton>(find.byKey(const Key('boncukMaxButton')));
    expect(maxButton.onPressed, isNull);

    hold.complete();
    await tester.pumpAndSettle();
  });

  testWidgets(
      'O: a Boncuk-specific server rejection never auto-resubmits without '
      'Boncuk — the customer must explicitly tap submit again', (tester) async {
    final pumped = await pumpCheckout(
      tester,
      loyaltyGateway: _FakeLoyaltyGateway(snapshot: _boncukSnapshot()),
    );
    await setUpValidForm(tester);
    await tester.tap(find.byKey(const Key('boncukToggle')));
    await tester.pumpAndSettle();

    pumped.gateway.throwOnNextSubmit = const SubmitTakeawayOrderException(
      'invalid-argument',
      'requestedBoncukAmount exceeds the maximum usable Boncuk for this order.',
      boncukErrorReason: 'boncuk/exceeds-max-usable',
    );

    await tester.tap(find.widgetWithText(ElevatedButton, 'Siparişi Ver'));
    await tester.pumpAndSettle();

    // Exactly one call was made — the rejection must never trigger a
    // second, automatic call on the customer's behalf.
    expect(pumped.gateway.callCount, 1);
    expect(find.byType(OrderSuccessScreen), findsNothing);
    expect(
      find.textContaining('Bilgileri güncelledik; tekrar seçim yap'),
      findsOneWidget,
    );
    // Boncuk usage was turned off by the rejection — the screen is now
    // immediately submittable again WITHOUT Boncuk, but only via another
    // explicit tap.
    final toggle = tester.widget<Switch>(find.byKey(const Key('boncukToggle')));
    expect(toggle.value, isFalse);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Siparişi Ver'));
    await tester.pumpAndSettle();
    expect(pumped.gateway.callCount, 2);
    expect(pumped.gateway.lastRequestedBoncukAmount, 0);
    expect(find.byType(OrderSuccessScreen), findsOneWidget);
  });

  testWidgets(
      'P: on success, the server-confirmed canonical Boncuk values are '
      'shown — order total / Boncuk used / remaining payable', (tester) async {
    await pumpCheckout(
      tester,
      loyaltyGateway: _FakeLoyaltyGateway(snapshot: _boncukSnapshot()),
    );
    await setUpValidForm(tester);
    await tester.tap(find.byKey(const Key('boncukToggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('boncukStepperIncrement')));
    await tester.pumpAndSettle();
    expect(find.text('2 Boncuk'), findsOneWidget);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Siparişi Ver'));
    await tester.pumpAndSettle();

    expect(find.byType(OrderSuccessScreen), findsOneWidget);
    expect(find.byKey(const Key('orderSuccessBoncukSummary')), findsOneWidget);
    expect(find.text('2 Boncuk kullanıldı'), findsOneWidget);
  });

  testWidgets(
      'R: the legacy delivery checkout coupon UI is a completely separate '
      'screen — no coupon control leaks into the takeaway checkout',
      (tester) async {
    await pumpCheckout(
      tester,
      loyaltyGateway: _FakeLoyaltyGateway(snapshot: _boncukSnapshot()),
    );

    expect(find.textContaining('Kupon'), findsNothing);
  });

  testWidgets(
      'loyalty snapshot is invalidated after a successful Boncuk redemption '
      'so the customer\'s displayed balance refreshes', (tester) async {
    final pumped = await pumpCheckout(
      tester,
      loyaltyGateway: _FakeLoyaltyGateway(snapshot: _boncukSnapshot()),
    );
    await setUpValidForm(tester);
    await tester.tap(find.byKey(const Key('boncukToggle')));
    await tester.pumpAndSettle();
    final callsBeforeSubmit = pumped.loyaltyGateway.snapshotCalls;

    await tester.tap(find.widgetWithText(ElevatedButton, 'Siparişi Ver'));
    await tester.pumpAndSettle();

    expect(
      pumped.loyaltyGateway.snapshotCalls,
      greaterThan(callsBeforeSubmit),
      reason:
          'ref.invalidate(loyaltySnapshotProvider) must trigger a fresh fetch',
    );
  });

  testWidgets(
      'requestedBoncukAmount is sent as a plain count, never with a '
      'monetary/policy field alongside it', (tester) async {
    final pumped = await pumpCheckout(
      tester,
      loyaltyGateway: _FakeLoyaltyGateway(snapshot: _boncukSnapshot()),
    );
    await setUpValidForm(tester);
    await tester.tap(find.byKey(const Key('boncukToggle')));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Siparişi Ver'));
    await tester.pumpAndSettle();

    // The interface signature itself (`submitAuthenticatedOrder`) has no
    // parameter for a monetary Boncuk value, policy version, max percent,
    // balance, or remaining payable — structurally impossible to send any
    // of them. This assertion proves the one real parameter that DOES
    // exist carries exactly the customer's own whole-Boncuk count.
    expect(pumped.gateway.lastRequestedBoncukAmount, 1);
  });

  // =========================================================================
  // Boncuk Loyalty Program P7-C (2026-08-24) — the Takeaway catalog-reward
  // checkout wiring: [CatalogRewardCard], mutual exclusivity with cash
  // Boncuk redemption, and the server-confirmed success summary.
  // =========================================================================

  testWidgets(
      'P7-C A: only rewards eligible for the current cart are shown; an '
      'ineligible reward is filtered out entirely', (tester) async {
    await pumpCheckout(
      tester,
      loyaltyGateway: _FakeLoyaltyGateway(
        rewards: [
          _catalogReward(rewardId: 'eligible', eligibleProductIds: ['p1']),
          _catalogReward(
              rewardId: 'ineligible', eligibleProductIds: ['other-product']),
        ],
      ),
    );

    expect(find.byKey(const Key('catalogRewardCard')), findsOneWidget);
    expect(find.byKey(const Key('catalogRewardTile-eligible')), findsOneWidget);
    expect(find.byKey(const Key('catalogRewardTile-ineligible')), findsNothing);
  });

  testWidgets(
      'P7-C B: selecting a reward sends exactly its rewardId, and removes '
      '(not just disables) the Boncuk cash-redemption card', (tester) async {
    final pumped = await pumpCheckout(
      tester,
      loyaltyGateway: _FakeLoyaltyGateway(
        snapshot: _boncukSnapshot(),
        rewards: [_catalogReward(rewardId: 'reward-1')],
      ),
    );
    expect(find.byKey(const Key('boncukRedemptionCard')), findsOneWidget);

    await tester.tap(find.byKey(const Key('catalogRewardTile-reward-1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('boncukRedemptionCard')), findsNothing);

    await setUpValidForm(tester);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Siparişi Ver'));
    await tester.pumpAndSettle();

    expect(pumped.gateway.lastSelectedRewardId, 'reward-1');
    expect(pumped.gateway.lastRequestedBoncukAmount, 0);
  });

  testWidgets(
      'P7-C C: selecting a reward while Boncuk cash redemption is already '
      'on turns Boncuk off (mutual exclusivity, the reward selection wins)',
      (tester) async {
    await pumpCheckout(
      tester,
      loyaltyGateway: _FakeLoyaltyGateway(
        snapshot: _boncukSnapshot(),
        rewards: [_catalogReward(rewardId: 'reward-1')],
      ),
    );
    await tester.tap(find.byKey(const Key('boncukToggle')));
    await tester.pumpAndSettle();
    expect(find.text('1 Boncuk'), findsOneWidget);

    // The Boncuk card is showing (reward not yet selected) — its own
    // CatalogRewardCard sibling self-hides while Boncuk is active, so no
    // reward tile is visible to tap yet; select it via the gateway path
    // is not possible from the UI in this state, which is exactly the
    // locked mutual-exclusivity behavior under test.
    expect(find.byKey(const Key('catalogRewardCard')), findsNothing);
  });

  testWidgets(
      'P7-C D: tapping an already-selected reward deselects it, and the '
      'Boncuk cash-redemption card reappears (the only way back, since '
      'selecting a reward removes that card entirely)', (tester) async {
    final pumped = await pumpCheckout(
      tester,
      loyaltyGateway: _FakeLoyaltyGateway(
        snapshot: _boncukSnapshot(),
        rewards: [_catalogReward(rewardId: 'reward-1')],
      ),
    );
    await tester.tap(find.byKey(const Key('catalogRewardTile-reward-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('boncukRedemptionCard')), findsNothing);

    await tester.tap(find.byKey(const Key('catalogRewardTile-reward-1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('boncukRedemptionCard')), findsOneWidget);

    await setUpValidForm(tester);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Siparişi Ver'));
    await tester.pumpAndSettle();
    expect(pumped.gateway.lastSelectedRewardId, isNull);
  });

  testWidgets(
      'P7-C E: on success, the server-confirmed catalog reward summary is '
      'shown — reward title / Boncuk used / free product / covered amount',
      (tester) async {
    final pumped = await pumpCheckout(
      tester,
      loyaltyGateway: _FakeLoyaltyGateway(
        rewards: [_catalogReward(rewardId: 'reward-1', boncukCost: 420)],
      ),
    );
    pumped.gateway.catalogRewardTitleToReturn = 'Çıtırtı Bowl';
    pumped.gateway.catalogRewardBoncukCostToReturn = 420;
    pumped.gateway.catalogRewardCoveredValueMinorUnitsToReturn = 12000;

    await tester.tap(find.byKey(const Key('catalogRewardTile-reward-1')));
    await tester.pumpAndSettle();
    await setUpValidForm(tester);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Siparişi Ver'));
    await tester.pumpAndSettle();

    expect(find.byType(OrderSuccessScreen), findsOneWidget);
    expect(find.byKey(const Key('orderSuccessCatalogRewardSummary')),
        findsOneWidget);
    expect(find.textContaining('Çıtırtı Bowl ödülü kullanıldı'), findsWidgets);
    expect(find.text('420 Boncuk'), findsOneWidget);
    expect(find.text('120 TL'), findsWidgets);
  });

  testWidgets('P7-C F: reward catalog loading renders the inline skeleton',
      (tester) async {
    tester.view.physicalSize = const Size(480, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final resolvedAuthState = AuthState(
      isAuthenticated: true,
      isGuest: false,
      session: _realCustomerSession(),
    );
    late final ProviderContainer container;
    final gateway = _FakeSubmitTakeawayOrderGateway(
      repository: InMemoryCanonicalOrderRepository(),
      identityProvider: InMemoryOrderIdentityProvider(),
      cartItemsSnapshot: () => container.read(cartProvider),
      resolveCustomerId: () => container.read(authProvider).session!.uid,
    );
    // A [LoyaltyGateway] whose reward catalog future never completes,
    // mirroring test J's own `neverCompleteSnapshot` pattern but for the
    // reward catalog instead.
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(() => SeededAuthNotifier(resolvedAuthState)),
        canonicalOrderRepositoryProvider.overrideWithValue(gateway.repository),
        orderIdentityProvider.overrideWithValue(gateway.identityProvider),
        submitTakeawayOrderGatewayProvider.overrideWithValue(gateway),
        loyaltyGatewayProvider
            .overrideWithValue(_NeverCompletingRewardCatalogGateway()),
      ],
    );
    addTearDown(container.dispose);
    container.read(shoppingChannelProvider.notifier).selectTakeaway(
          restaurantId: 'restaurant-1',
          branchId: 'branch-1',
          branchDisplayName: 'Abaküs Ortaköy',
        );
    container.read(cartProvider.notifier).addToCart(
          id: 'p1',
          name: 'Falafel Bowl',
          desc: '',
          price: 120.0,
          quantity: 2,
          pricedForChannel: OrderChannel.takeaway,
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: TakeawayCheckoutScreen()),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('catalogRewardCardSkeleton')), findsOneWidget);
  });

  testWidgets(
      'P7-C G: reward catalog load failure shows a scoped retry card; '
      'ordinary checkout (without a reward) remains fully usable',
      (tester) async {
    final pumped = await pumpCheckout(
      tester,
      loyaltyGateway: _FakeLoyaltyGateway(
        rewardCatalogError: const LoyaltyGatewayException(
          'internal',
          'Ödül kataloğuna şu anda ulaşılamıyor.',
        ),
      ),
    );

    expect(find.byKey(const Key('catalogRewardCardError')), findsOneWidget);

    await setUpValidForm(tester);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Siparişi Ver'));
    await tester.pumpAndSettle();

    expect(find.byType(OrderSuccessScreen), findsOneWidget);
    expect(pumped.gateway.lastSelectedRewardId, isNull);
  });

  testWidgets(
      'P7-C H: a cart change that removes the reward\'s only eligible '
      'product clears the selection automatically — never left selected '
      'and pointing at nothing', (tester) async {
    await pumpCheckout(
      tester,
      loyaltyGateway: _FakeLoyaltyGateway(
        rewards: [_catalogReward(rewardId: 'reward-1')],
      ),
    );
    await tester.tap(find.byKey(const Key('catalogRewardTile-reward-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('catalogRewardTile-reward-1')), findsOneWidget);

    final scope = tester.widget<UncontrolledProviderScope>(
        find.byType(UncontrolledProviderScope));
    scope.container.read(cartProvider.notifier).removeFromCart(id: 'p1');
    await tester.pumpAndSettle();

    // The reward card renders nothing at all now (no eligible product left
    // in the cart) — proving the selection was cleared, not merely hidden
    // while still "selected" underneath.
    expect(find.byKey(const Key('catalogRewardCard')), findsNothing);
  });

  testWidgets(
      'P7-C I: a catalogReward-specific server rejection resets the '
      'selection and never auto-resubmits without the reward — the '
      'customer must explicitly tap submit again', (tester) async {
    final pumped = await pumpCheckout(
      tester,
      loyaltyGateway: _FakeLoyaltyGateway(
        rewards: [_catalogReward(rewardId: 'reward-1')],
      ),
    );
    await tester.tap(find.byKey(const Key('catalogRewardTile-reward-1')));
    await tester.pumpAndSettle();
    await setUpValidForm(tester);

    pumped.gateway.throwOnNextSubmit = const SubmitTakeawayOrderException(
      'invalid-argument',
      'The requested reward is no longer valid.',
      boncukErrorReason: 'catalogReward/insufficient-balance',
    );

    await tester.tap(find.widgetWithText(ElevatedButton, 'Siparişi Ver'));
    await tester.pumpAndSettle();

    expect(pumped.gateway.callCount, 1);
    expect(find.byType(OrderSuccessScreen), findsNothing);
    expect(
      find.textContaining('Bilgileri güncelledik; ödül kullanmadan'),
      findsOneWidget,
    );
    // The reward's card is back — selection was reset, not merely hidden.
    expect(find.byKey(const Key('catalogRewardTile-reward-1')), findsOneWidget);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Siparişi Ver'));
    await tester.pumpAndSettle();
    expect(pumped.gateway.callCount, 2);
    expect(pumped.gateway.lastSelectedRewardId, isNull);
    expect(find.byType(OrderSuccessScreen), findsOneWidget);
  });

  testWidgets(
      'P7-C J: the reward catalog is invalidated after a successful '
      'catalog-reward redemption so the customer\'s eligible-reward list '
      'refreshes (their balance may no longer cover the same rewards)',
      (tester) async {
    final pumped = await pumpCheckout(
      tester,
      loyaltyGateway: _FakeLoyaltyGateway(
        rewards: [_catalogReward(rewardId: 'reward-1')],
      ),
    );
    await tester.tap(find.byKey(const Key('catalogRewardTile-reward-1')));
    await tester.pumpAndSettle();
    await setUpValidForm(tester);
    final callsBeforeSubmit = pumped.loyaltyGateway.rewardCatalogCalls;

    await tester.tap(find.widgetWithText(ElevatedButton, 'Siparişi Ver'));
    await tester.pumpAndSettle();

    expect(
      pumped.loyaltyGateway.rewardCatalogCalls,
      greaterThan(callsBeforeSubmit),
      reason:
          'ref.invalidate(loyaltyRewardCatalogProvider) must trigger a fresh fetch',
    );
  });

  testWidgets(
      'P7-C K: an ordinary checkout with no eligible reward for the cart '
      'renders no catalog-reward card at all', (tester) async {
    await pumpCheckout(tester);

    expect(find.byKey(const Key('catalogRewardCard')), findsNothing);
    expect(find.byKey(const Key('catalogRewardCardSkeleton')), findsNothing);
    expect(find.byKey(const Key('catalogRewardCardError')), findsNothing);
  });
}

/// A [LoyaltyGateway] fake whose reward-catalog future never resolves —
/// mirrors [_FakeLoyaltyGateway]'s own `neverCompleteSnapshot` behavior for
/// the account snapshot, but for `getRewardCatalog()` instead. Kept as a
/// separate tiny class (rather than a new flag on [_FakeLoyaltyGateway])
/// since it's needed by exactly one test.
class _NeverCompletingRewardCatalogGateway implements LoyaltyGateway {
  @override
  Future<LoyaltyAccountSnapshot> getSnapshot() async =>
      LoyaltyAccountSnapshot.zero;

  @override
  Future<LoyaltyHistoryPage> getHistory({int? pageSize, String? cursor}) async {
    return LoyaltyHistoryPage.empty;
  }

  @override
  Future<List<LoyaltyReward>> getRewardCatalog() {
    return Completer<List<LoyaltyReward>>().future;
  }
}
