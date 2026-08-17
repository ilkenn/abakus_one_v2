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
import 'package:abakus_one_v2/features/delivery/data/check_delivery_eligibility_gateway.dart';
import 'package:abakus_one_v2/features/delivery/data/submit_delivery_order_gateway.dart';
import 'package:abakus_one_v2/features/delivery/presentation/providers/delivery_dependencies_provider.dart';
import 'package:abakus_one_v2/features/delivery/presentation/screens/delivery_checkout_screen.dart';
import 'package:abakus_one_v2/features/orders/data/canonical_order_repository.dart';
import 'package:abakus_one_v2/features/orders/data/saved_address_repository.dart';
import 'package:abakus_one_v2/features/orders/domain/identity/order_identity.dart';
import 'package:abakus_one_v2/features/orders/domain/mappers/cart_to_order_mapper.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_actor.dart';
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
  SubmitDeliveryOrderException? errorToThrow;

  @override
  Future<SubmitDeliveryOrderResult> submit({
    required String submissionKey,
    required String savedAddressId,
    required String paymentMethodId,
    required List<DeliveryOrderItem> items,
    ClientLocationEvidence? deviceLocation,
    String? deviceLocationUnavailableReason,
  }) async {
    callCount += 1;
    lastSavedAddressId = savedAddressId;
    lastPaymentMethodId = paymentMethodId;
    lastRequestItems = [for (final item in items) item.toJson()];
    lastDeviceLocation = deviceLocation;
    lastDeviceLocationUnavailableReason = deviceLocationUnavailableReason;

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
    })> pumpCheckout(
  WidgetTester tester, {
  AuthState? authState,
  List<SavedAddress>? addresses,
  DeliveryEligibilityResult? eligibilityResult,
  DeviceLocationCaptureResult? locationCaptureResult,
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
}
