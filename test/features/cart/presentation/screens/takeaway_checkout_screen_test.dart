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
import 'package:abakus_one_v2/features/orders/domain/mappers/cart_to_order_mapper.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_actor.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_channel.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_status.dart';
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
  }) async {
    callCount += 1;
    lastRequestItems = [for (final item in items) item.toJson()];
    lastRestaurantId = restaurantId;
    lastBranchId = branchId;
    lastPickupTime = pickupTime;

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
    })> pumpCheckout(
  WidgetTester tester, {
  AuthState? authState,
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

  container = ProviderContainer(
    overrides: [
      authProvider.overrideWith(() => SeededAuthNotifier(resolvedAuthState)),
      canonicalOrderRepositoryProvider.overrideWithValue(gateway.repository),
      orderIdentityProvider.overrideWithValue(gateway.identityProvider),
      submitTakeawayOrderGatewayProvider.overrideWithValue(gateway),
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
  return (container: container, gateway: gateway);
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
}
