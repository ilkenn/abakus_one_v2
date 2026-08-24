import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/core/fraud/domain/fraud_evidence.dart';
import 'package:abakus_one_v2/core/fraud/domain/mock_location_status.dart';
import 'package:abakus_one_v2/features/address_search/data/address_location_gateway.dart';
import 'package:abakus_one_v2/features/address_search/presentation/providers/address_search_provider.dart';
import 'package:abakus_one_v2/features/auth/domain/models/auth_session.dart';
import 'package:abakus_one_v2/features/auth/presentation/providers/auth_provider.dart';
import 'package:abakus_one_v2/features/cart/domain/models/cart_item.dart';
import 'package:abakus_one_v2/features/cart/presentation/providers/cart_provider.dart';
import 'package:abakus_one_v2/features/cart/presentation/screens/order_success_screen.dart';
import 'package:abakus_one_v2/features/cart/presentation/screens/takeaway_checkout_screen.dart'
    show computeClientEstimatedMaxBoncuk;
import 'package:abakus_one_v2/features/delivery/data/check_delivery_eligibility_gateway.dart';
import 'package:abakus_one_v2/features/delivery/data/submit_delivery_order_gateway.dart';
import 'package:abakus_one_v2/features/delivery/presentation/providers/delivery_dependencies_provider.dart';
import 'package:abakus_one_v2/features/delivery/presentation/screens/delivery_checkout_screen.dart';
import 'package:abakus_one_v2/features/loyalty/data/loyalty_gateway.dart';
import 'package:abakus_one_v2/features/loyalty/domain/models/loyalty_account_snapshot.dart';
import 'package:abakus_one_v2/features/loyalty/domain/models/loyalty_history_entry.dart';
import 'package:abakus_one_v2/features/loyalty/domain/models/loyalty_reward.dart';
import 'package:abakus_one_v2/features/loyalty/presentation/providers/loyalty_providers.dart';
import 'package:abakus_one_v2/features/orders/data/canonical_order_repository.dart';
import 'package:abakus_one_v2/features/orders/data/saved_address_repository.dart';
import 'package:abakus_one_v2/features/orders/domain/identity/order_identity.dart';
import 'package:abakus_one_v2/features/orders/domain/mappers/cart_to_order_mapper.dart';
import 'package:abakus_one_v2/features/orders/domain/models/boncuk_redemption_snapshot.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_actor.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_benefit_type.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_channel.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_status.dart';
import 'package:abakus_one_v2/features/orders/domain/models/saved_address.dart';
import 'package:abakus_one_v2/features/orders/presentation/providers/order_identity_provider.dart';
import 'package:abakus_one_v2/features/orders/presentation/providers/orders_provider.dart';
import 'package:abakus_one_v2/features/orders/presentation/providers/saved_address_providers.dart';
import 'package:abakus_one_v2/features/payment/domain/models/payment_method_seed_data.dart';
import 'package:abakus_one_v2/features/payment/domain/models/payment_method_snapshot.dart';

/// Paket Servis P.3 — `DeliveryCheckoutScreen` never talks to
/// `CanonicalOrderRepository` directly; it calls `SubmitDeliveryOrderGateway`
/// (the real implementation talks to the `submitDeliveryOrder` Cloud
/// Function, unavailable under `flutter test`) and reads the resulting
/// canonical order back — same "send intent, not price" discipline
/// `takeaway_checkout_screen_test.dart` already establishes for takeaway.
class _FakeSubmitDeliveryOrderGateway implements SubmitDeliveryOrderGateway {
  _FakeSubmitDeliveryOrderGateway({
    required this.repository,
    required this.identityProvider,
    required this.cartItemsSnapshot,
    required this.resolveCustomerId,
    required this.addressLookup,
  });

  final CanonicalOrderRepository repository;
  final OrderIdentityProvider identityProvider;
  final List<CartItem> Function() cartItemsSnapshot;
  final String Function() resolveCustomerId;
  final SavedAddress Function(String savedAddressId) addressLookup;

  final Map<String, dynamic> _orderIdByKey = {};
  int callCount = 0;
  String? lastSavedAddressId;
  String? lastPaymentMethodId;
  List<Map<String, dynamic>>? lastRequestItems;
  ClientLocationEvidence? lastDeviceLocation;
  String? lastDeviceLocationUnavailableReason;
  int? lastRequestedBoncukAmount;
  SubmitDeliveryOrderException? errorToThrow;

  /// Boncuk Loyalty P5-B — one-shot rejection (cleared after being thrown
  /// once), for tests that need the NEXT call to fail and a subsequent
  /// retry to succeed. `errorToThrow` above is left untouched (persists
  /// across calls) since an existing test relies on that.
  SubmitDeliveryOrderException? throwOnNextSubmit;

  /// Boncuk Loyalty P5-B — when set, [submit] awaits this before resolving,
  /// letting a test observe frozen in-flight controls (mirrors
  /// `takeaway_checkout_screen_test.dart`'s own `holdUntil`).
  Completer<void>? holdUntil;

  @override
  Future<SubmitDeliveryOrderResult> submit({
    required String submissionKey,
    required String savedAddressId,
    required String paymentMethodId,
    required List<DeliveryOrderItem> items,
    ClientLocationEvidence? deviceLocation,
    String? deviceLocationUnavailableReason,
    int requestedBoncukAmount = 0,
  }) async {
    callCount += 1;
    lastSavedAddressId = savedAddressId;
    lastPaymentMethodId = paymentMethodId;
    lastRequestItems = [for (final item in items) item.toJson()];
    lastDeviceLocation = deviceLocation;
    lastDeviceLocationUnavailableReason = deviceLocationUnavailableReason;
    lastRequestedBoncukAmount = requestedBoncukAmount;

    final pendingHold = holdUntil;
    if (pendingHold != null) {
      await pendingHold.future;
    }

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
      return SubmitDeliveryOrderResult(
        orderId: existingOrderId.value,
        orderNumber: existing!.orderNumber.value,
        duplicate: true,
      );
    }

    final orderId = await identityProvider.nextOrderId();
    final orderNumber = await identityProvider.nextOrderNumber();
    _orderIdByKey[submissionKey] = orderId;

    final now = DateTime.now();
    final address = addressLookup(savedAddressId);
    final paymentMethod =
        PaymentMethodSeedData.all.firstWhere((m) => m.id == paymentMethodId);

    var order = CartToOrderMapper.map(
      orderId: orderId,
      orderNumber: orderNumber,
      cartItems: cartItemsSnapshot(),
      channel: OrderChannel.delivery,
      branchId: 'branch-1',
      restaurantId: 'restaurant-1',
      customerId: resolveCustomerId(),
      now: now,
    );
    order = order.copyWith(
      deliveryAddressSnapshot: address.toDeliveryAddressSnapshot(),
      paymentMethodSnapshot: PaymentMethodSnapshot.capture(paymentMethod),
    );
    order = order.transitionTo(
      OrderStatus.pendingConfirmation,
      actor: OrderActor.customer,
      at: now,
      auditEntryId: '${orderId.value}-transition-1',
    );
    if (requestedBoncukAmount > 0) {
      // Boncuk Loyalty P5-B — simulates the SERVER's own settlement
      // snapshot, mirroring `takeaway_checkout_screen_test.dart`'s own
      // `_FakeSubmitTakeawayOrderGateway` exactly (same simplified but
      // real domain-shaped stand-in, rate: 1 Boncuk = 1 TL = 100 minor
      // units). The real `calculateBoncukRedemption` algorithm is covered
      // server-side, not re-proven by this Flutter test.
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
    }
    await repository.submitOrder(order);

    return SubmitDeliveryOrderResult(
      orderId: orderId.value,
      orderNumber: orderNumber.value,
      duplicate: false,
    );
  }
}

class _FakeCheckDeliveryEligibilityGateway
    implements CheckDeliveryEligibilityGateway {
  _FakeCheckDeliveryEligibilityGateway({this.result});

  DeliveryEligibilityResult? result;
  int callCount = 0;

  @override
  Future<DeliveryEligibilityResult> check({
    required String savedAddressId,
  }) async {
    callCount += 1;
    return result ??
        const DeliveryEligibilityResult(
          eligible: true,
          reason: null,
          minimumOrderMinorUnits: null,
        );
  }
}

class _FakeAddressLocationGateway implements AddressLocationGateway {
  _FakeAddressLocationGateway({this.captureResult});

  DeviceLocationCaptureResult? captureResult;
  int captureCallCount = 0;

  @override
  Future<({double latitude, double longitude})?> currentPosition() async =>
      null;

  @override
  Future<bool> isPermissionPermanentlyDenied() async => false;

  @override
  Future<DeviceLocationCaptureResult> captureLocationEvidence() async {
    captureCallCount += 1;
    return captureResult ??
        const DeviceLocationCaptureResult.unavailable(
          DeviceLocationUnavailableReason.permissionDenied,
        );
  }
}

class _FakeSavedAddressRepository implements SavedAddressRepository {
  _FakeSavedAddressRepository({this.seed = const []});

  List<SavedAddress> seed;

  @override
  Future<SavedAddress> save({
    String? addressId,
    required String providerPlaceId,
    required String label,
    bool isDefault = false,
    required String apartmentNo,
    String? floor,
    String? addressDescription,
    String? buildingNoOverride,
    ClientLocationEvidence? deviceLocation,
    String? deviceLocationUnavailableReason,
  }) async =>
      throw UnimplementedError();

  @override
  Future<List<SavedAddress>> listForCurrentUser() async => seed;

  @override
  Future<void> updateMetadata({
    required String addressId,
    String? label,
    bool? isDefault,
    String? apartmentNo,
    String? floor,
    String? addressDescription,
    String? buildingNoOverride,
  }) async {}

  @override
  Future<void> delete(String addressId) async {}
}

/// Boncuk Loyalty P5-B — mirrors `takeaway_checkout_screen_test.dart`'s own
/// private `_FakeLoyaltyGateway` exactly (duplicated per this codebase's
/// established per-file test-double convention, not shared).
class _FakeLoyaltyGateway implements LoyaltyGateway {
  _FakeLoyaltyGateway({
    LoyaltyAccountSnapshot? snapshot,
    this.snapshotError,
    this.neverCompleteSnapshot = false,
  }) : snapshot = snapshot ?? LoyaltyAccountSnapshot.zero;

  LoyaltyAccountSnapshot snapshot;
  LoyaltyGatewayException? snapshotError;
  bool neverCompleteSnapshot;
  int snapshotCalls = 0;

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
  Future<List<LoyaltyReward>> getRewardCatalog() async => const [];
}

/// A well-formed, non-default snapshot for Boncuk checkout tests — mirrors
/// `takeaway_checkout_screen_test.dart`'s own `_boncukSnapshot` exactly (a
/// non-default redemption rate/cap deliberately, so a test can prove the UI
/// reads [LoyaltyAccountSnapshot]'s own fields rather than a Flutter
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

AuthSession _realCustomerSession({String uid = 'real-customer-uid'}) {
  return AuthSession(
    uid: uid,
    phoneNumber: '+905551234567',
    createdAt: DateTime(2026, 8, 1),
    expiresAt: DateTime(2027, 8, 1),
  );
}

SavedAddress _verifiedAddress({
  String id = 'address-1',
  bool isDefault = true,
}) {
  return SavedAddress(
    id: id,
    customerId: 'real-customer-uid',
    label: 'Ev',
    provinceId: 'istanbul',
    provinceName: 'İstanbul',
    districtId: 'besiktas',
    districtName: 'Beşiktaş',
    neighborhoodId: 'levent',
    neighborhoodName: 'Levent',
    apartmentNo: '4',
    latitude: 41.05,
    longitude: 29.01,
    verificationStatus: AddressVerificationStatus.verified,
    verifiedAt: DateTime(2026, 8, 1),
    providerSource: 'google_places',
    isDefault: isDefault,
  );
}

Future<
    ({
      ProviderContainer container,
      _FakeSubmitDeliveryOrderGateway gateway,
      _FakeCheckDeliveryEligibilityGateway eligibilityGateway,
      _FakeAddressLocationGateway locationGateway,
      _FakeLoyaltyGateway loyaltyGateway,
    })> pumpCheckout(
  WidgetTester tester, {
  AuthState? authState,
  List<SavedAddress>? addresses,
  DeliveryEligibilityResult? eligibilityResult,
  DeviceLocationCaptureResult? locationCaptureResult,
  // ignore: library_private_types_in_public_api
  _FakeLoyaltyGateway? loyaltyGateway,
}) async {
  tester.view.physicalSize = const Size(480, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final resolvedAuthState = authState ??
      AuthState(
        isAuthenticated: true,
        isGuest: false,
        session: _realCustomerSession(),
      );
  final resolvedAddresses = addresses ?? [_verifiedAddress()];
  final addressRepository = _FakeSavedAddressRepository(
    seed: resolvedAddresses,
  );
  final locationGateway = _FakeAddressLocationGateway(
    captureResult: locationCaptureResult,
  );
  final eligibilityGateway = _FakeCheckDeliveryEligibilityGateway(
    result: eligibilityResult,
  );
  final resolvedLoyaltyGateway = loyaltyGateway ?? _FakeLoyaltyGateway();

  late final ProviderContainer container;
  final gateway = _FakeSubmitDeliveryOrderGateway(
    repository: InMemoryCanonicalOrderRepository(),
    identityProvider: InMemoryOrderIdentityProvider(),
    cartItemsSnapshot: () => container.read(cartProvider),
    resolveCustomerId: () => container.read(authProvider).session!.uid,
    addressLookup: (id) => resolvedAddresses.firstWhere((a) => a.id == id),
  );

  container = ProviderContainer(
    overrides: [
      authProvider.overrideWith(() => SeededAuthNotifier(resolvedAuthState)),
      canonicalOrderRepositoryProvider.overrideWithValue(gateway.repository),
      orderIdentityProvider.overrideWithValue(gateway.identityProvider),
      savedAddressRepositoryProvider.overrideWithValue(addressRepository),
      addressLocationGatewayProvider.overrideWithValue(locationGateway),
      submitDeliveryOrderGatewayProvider.overrideWithValue(gateway),
      checkDeliveryEligibilityGatewayProvider.overrideWithValue(
        eligibilityGateway,
      ),
      loyaltyGatewayProvider.overrideWithValue(resolvedLoyaltyGateway),
    ],
  );
  addTearDown(container.dispose);

  container.read(cartProvider.notifier).addToCart(
        id: 'p1',
        name: 'Falafel Bowl',
        desc: '',
        price: 120.0,
        quantity: 2,
        pricedForChannel: OrderChannel.delivery,
      );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: DeliveryCheckoutScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return (
    container: container,
    gateway: gateway,
    eligibilityGateway: eligibilityGateway,
    locationGateway: locationGateway,
    loyaltyGateway: resolvedLoyaltyGateway,
  );
}

void main() {
  testWidgets(
      'varsayılan doğrulanmış adres otomatik seçilir, ürünler ve tahmini '
      'toplam gösterilir', (tester) async {
    await pumpCheckout(tester);

    expect(find.text('Ev'), findsOneWidget);
    expect(find.textContaining('Falafel Bowl'), findsOneWidget);
    expect(
      find.textContaining('tutar tahminidir'),
      findsOneWidget,
    );
  });

  testWidgets(
      'ödeme yöntemi seçilmeden Siparişi Ver devre dışıdır, seçilince aktif '
      'olur', (tester) async {
    await pumpCheckout(tester);

    final buttonBefore = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Siparişi Ver'),
    );
    expect(buttonBefore.onPressed, isNull);

    await tester.tap(find.text('Nakit'));
    await tester.pumpAndSettle();

    final buttonAfter = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Siparişi Ver'),
    );
    expect(buttonAfter.onPressed, isNotNull);
  });

  testWidgets('doğrulanmış adres yoksa Siparişi Ver devre dışı kalır',
      (tester) async {
    await pumpCheckout(
      tester,
      addresses: [
        const SavedAddress(
          id: 'address-unverified',
          customerId: 'real-customer-uid',
          label: 'Doğrulanmamış',
          apartmentNo: '1',
        ),
      ],
    );

    await tester.tap(find.text('Nakit'));
    await tester.pumpAndSettle();

    final button = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Siparişi Ver'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets(
      'uygun olmayan teslimat bölgesi uyarısı gösterilir (advisory-only — '
      'submitDeliveryOrder her zaman bağımsızca yeniden doğrular)',
      (tester) async {
    await pumpCheckout(
      tester,
      eligibilityResult: const DeliveryEligibilityResult(
        eligible: false,
        reason: 'not_covered',
        minimumOrderMinorUnits: null,
      ),
    );

    expect(
      find.text('Bu adrese şu anda paket servis hizmeti veremiyoruz.'),
      findsOneWidget,
    );
  });

  testWidgets(
      'başarılı gönderimde: gateway doğru adres/ödeme/ürün bilgileriyle '
      'çağrılır, FRAUD-F.2 konum yakalama tetiklenir, backend\'in '
      'döndürdüğü canonical order okunup sepet temizlenir, başarı ekranına '
      'geçilir', (tester) async {
    final capturedLocation = ClientLocationEvidence(
      latitude: 41.06,
      longitude: 29.02,
      accuracyMeters: 10,
      clientCapturedAt: DateTime(2026, 8, 16),
      mockLocationStatus: MockLocationStatus.notDetected,
      permissionState: 'granted',
      precisionState: 'precise',
    );
    final pumped = await pumpCheckout(
      tester,
      locationCaptureResult: DeviceLocationCaptureResult.available(
        capturedLocation,
      ),
    );
    final container = pumped.container;
    final gateway = pumped.gateway;
    final locationGateway = pumped.locationGateway;

    await tester.tap(find.text('Nakit'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Siparişi Ver'));
    await tester.pumpAndSettle();

    expect(find.byType(OrderSuccessScreen), findsOneWidget);
    expect(container.read(cartProvider), isEmpty);

    expect(gateway.callCount, 1);
    expect(gateway.lastSavedAddressId, 'address-1');
    expect(gateway.lastPaymentMethodId, 'cash');
    expect(gateway.lastRequestItems, [
      {
        'kind': 'product',
        'productId': 'p1',
        'quantity': 2,
        'selectedModifiers': <Map<String, String>>[],
        'note': '',
      },
    ]);
    expect(gateway.lastDeviceLocation, capturedLocation);
    expect(locationGateway.captureCallCount, 1);

    final orders =
        await container.read(canonicalOrderRepositoryProvider).findAll();
    expect(orders, hasLength(1));
    final order = orders.single;
    expect(order.channel, OrderChannel.delivery);
    expect(order.customerId, 'real-customer-uid');
    expect(order.deliveryAddressSnapshot?.savedAddressId, 'address-1');
    expect(order.paymentMethodSnapshot?.paymentMethodId, 'cash');
  });

  testWidgets(
      'hızlı çift dokunma (idempotency): gateway iki kez çağrılsa bile tek '
      'sipariş oluşur, ve FRAUD-F.2 konum yakalama yalnızca bir kez '
      'tetiklenir (retry aynı adayı yeniden kullanır)', (tester) async {
    final pumped = await pumpCheckout(tester);
    final container = pumped.container;
    final gateway = pumped.gateway;
    final locationGateway = pumped.locationGateway;

    await tester.tap(find.text('Nakit'));
    await tester.pumpAndSettle();

    final button = find.widgetWithText(ElevatedButton, 'Siparişi Ver');
    await tester.tap(button);
    // No pump in between — the second tap should be swallowed by the
    // _isSubmitting guard, mirroring TakeawayCheckoutScreen's own
    // double-tap protection.
    await tester.tap(button);
    await tester.pumpAndSettle();

    final orders =
        await container.read(canonicalOrderRepositoryProvider).findAll();
    expect(orders, hasLength(1));
    expect(gateway.callCount, 1);
    expect(locationGateway.captureCallCount, 1);
  });

  testWidgets(
      'anonymous/guest oturum submit anında fail-closed reddedilir — '
      'gateway hiç çağrılmaz, sipariş oluşturulmaz', (tester) async {
    final pumped = await pumpCheckout(
      tester,
      authState: const AuthState(isAuthenticated: true, isGuest: true),
    );
    final container = pumped.container;
    final gateway = pumped.gateway;

    await tester.tap(find.text('Nakit'));
    await tester.pumpAndSettle();

    final button = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Siparişi Ver'),
    );
    // The UI-level checks (address + payment method selected) still allow
    // a tap — the auth re-check happens only inside _submitOrder itself.
    expect(button.onPressed, isNotNull);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Siparişi Ver'));
    await tester.pumpAndSettle();

    expect(find.byType(OrderSuccessScreen), findsNothing);
    expect(gateway.callCount, 0);
    final orders =
        await container.read(canonicalOrderRepositoryProvider).findAll();
    expect(orders, isEmpty);
  });

  testWidgets(
      'sunucu failed-precondition (minimum sipariş) hatası müşteriye Türkçe, '
      'ham backend metni içermeyen bir mesajla gösterilir', (tester) async {
    final pumped = await pumpCheckout(tester);
    pumped.gateway.errorToThrow = const SubmitDeliveryOrderException(
      'failed-precondition',
      'Minimum sipariş tutarı karşılanmıyor.',
    );

    await tester.tap(find.text('Nakit'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Siparişi Ver'));
    await tester.pumpAndSettle();

    expect(find.byType(OrderSuccessScreen), findsNothing);
    expect(
      find.text('Bu adres için minimum sipariş tutarına ulaşmadın.'),
      findsOneWidget,
    );
  });

  // =========================================================================
  // Boncuk Loyalty P5-B (2026-08-24) — delivery Boncuk checkout, reusing
  // `BoncukRedemptionCard` UNCHANGED. Letters mirror
  // `takeaway_checkout_screen_test.dart`'s own A-R list; the default
  // delivery cart in `pumpCheckout` (Falafel Bowl x2 @ 120 TL = 240 TL) is
  // the same total as the takeaway tests' own default cart, so the numeric
  // expectations below are deliberately identical.
  // =========================================================================

  Future<void> selectCashPayment(WidgetTester tester) async {
    await tester.tap(find.text('Nakit'));
    await tester.pumpAndSettle();
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
    await selectCashPayment(tester);
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

    final decrementButton = tester
        .widget<IconButton>(find.byKey(const Key('boncukStepperDecrement')));
    expect(decrementButton.onPressed, isNull);
  });

  testWidgets('E: MAX uses the current presentation max, from the snapshot',
      (tester) async {
    final pumped = await pumpCheckout(
      tester,
      loyaltyGateway: _FakeLoyaltyGateway(
        snapshot: _boncukSnapshot(
          spendableBalance: 500,
          redemptionValueMinorUnitsPerBoncuk: 150,
          maxRedemptionBasisPoints: 4000,
        ),
      ),
    );
    await selectCashPayment(tester);
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
    await pumpCheckout(
      tester,
      loyaltyGateway: _FakeLoyaltyGateway(neverCompleteSnapshot: true),
    );
    // pumpCheckout already calls pumpAndSettle once, which would hang if
    // the snapshot future genuinely never resolved and something kept
    // scheduling frames — it doesn't (the loading state itself is static),
    // so the skeleton is what's left on screen.
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

    await selectCashPayment(tester);
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
        snapshot: _boncukSnapshot(
          spendableBalance: 500,
          redemptionValueMinorUnitsPerBoncuk: 100,
          maxRedemptionBasisPoints: 5000,
        ),
      ),
    );
    await selectCashPayment(tester);
    // Cart total 240 TL -> max = min(500, floor(24000*5000/10000)/100) = 120.
    await tester.tap(find.byKey(const Key('boncukToggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('boncukMaxButton')));
    await tester.pumpAndSettle();
    expect(find.text('120 Boncuk'), findsOneWidget);

    final containerFinder = find.byType(UncontrolledProviderScope);
    final scope = tester.widget<UncontrolledProviderScope>(containerFinder);
    scope.container.read(cartProvider.notifier).updateQuantity(
          'p1',
          '',
          '',
          1,
        );
    await tester.pumpAndSettle();

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
    await selectCashPayment(tester);
    await tester.tap(find.byKey(const Key('boncukToggle')));
    await tester.pumpAndSettle();

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
    await selectCashPayment(tester);
    await tester.tap(find.byKey(const Key('boncukToggle')));
    await tester.pumpAndSettle();

    pumped.gateway.throwOnNextSubmit = const SubmitDeliveryOrderException(
      'invalid-argument',
      'requestedBoncukAmount exceeds the maximum usable Boncuk for this order.',
      boncukErrorReason: 'boncuk/exceeds-max-usable',
    );

    await tester.tap(find.widgetWithText(ElevatedButton, 'Siparişi Ver'));
    await tester.pumpAndSettle();

    expect(pumped.gateway.callCount, 1);
    expect(find.byType(OrderSuccessScreen), findsNothing);
    expect(
      find.textContaining('Bilgileri güncelledik; tekrar seçim yap'),
      findsOneWidget,
    );
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
    await selectCashPayment(tester);
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
      'R: the legacy delivery checkout coupon UI is a completely separate, '
      'dead/unreachable screen — no coupon control leaks into the live '
      'DeliveryCheckoutScreen', (tester) async {
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
    await selectCashPayment(tester);
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
    await selectCashPayment(tester);
    await tester.tap(find.byKey(const Key('boncukToggle')));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Siparişi Ver'));
    await tester.pumpAndSettle();

    expect(pumped.gateway.lastRequestedBoncukAmount, 1);
  });

  testWidgets(
      'all 7 delivery payment methods remain selectable with Boncuk enabled '
      '— payment method is never treated as a competing "benefit"',
      (tester) async {
    final pumped = await pumpCheckout(
      tester,
      loyaltyGateway: _FakeLoyaltyGateway(snapshot: _boncukSnapshot()),
    );
    await tester.tap(find.byKey(const Key('boncukToggle')));
    await tester.pumpAndSettle();

    const methodLabels = [
      'Nakit',
      'Kredi/Banka Kartı',
      'Pluxee',
      'Multinet',
      'Setcard',
      'Edenred',
      'MetropolCard',
    ];
    for (final label in methodLabels) {
      expect(find.text(label), findsOneWidget,
          reason: '$label ödeme seçeneği Boncuk açıkken de görünür olmalı');
    }

    await tester.tap(find.text('Multinet'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Siparişi Ver'));
    await tester.pumpAndSettle();

    expect(pumped.gateway.lastPaymentMethodId, 'multinet');
    expect(pumped.gateway.lastRequestedBoncukAmount, 1);
    expect(find.byType(OrderSuccessScreen), findsOneWidget);
  });
}
