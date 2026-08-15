import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/auth/domain/models/auth_session.dart';
import 'package:abakus_one_v2/features/auth/presentation/providers/auth_provider.dart';
import 'package:abakus_one_v2/features/cart/presentation/providers/cart_provider.dart';
import 'package:abakus_one_v2/features/cart/presentation/screens/dine_in_checkout_screen.dart';
import 'package:abakus_one_v2/features/cart/presentation/screens/order_success_screen.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_channel.dart';
import 'package:abakus_one_v2/features/orders/presentation/providers/orders_provider.dart';
import 'package:abakus_one_v2/features/qr/domain/models/active_table_context.dart';
import 'package:abakus_one_v2/features/qr/domain/models/guest_session.dart';
import 'package:abakus_one_v2/features/qr/domain/models/table_session.dart';
import 'package:abakus_one_v2/features/qr/data/table_guest_session_firestore_client.dart';
import 'package:abakus_one_v2/features/qr/data/technical_identity_provider.dart';
import 'package:abakus_one_v2/features/qr/presentation/providers/active_table_context_provider.dart';
import 'package:abakus_one_v2/features/qr/presentation/providers/table_guest_session_dependencies_provider.dart';

/// Test double for [TableGuestSessionFirestoreClient] — the real
/// implementation talks to Firestore, which isn't available under
/// `flutter test`; every test here seeds this in-memory map instead of a
/// real `tableGuestSessions` document.
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

/// Test double for [TechnicalIdentityProvider] — the real implementation
/// talks to `FirebaseAuth.instance`, unavailable under `flutter test`.
/// [DineInCheckoutScreen] only ever reads [currentUid] (a passive
/// snapshot), never calls [ensureSignedIn] itself (that's
/// `OpenTableGuestSessionFromQrScan`'s job, during the QR scan step, not
/// checkout) — [ensureSignedIn] throws here to prove that assumption
/// holds.
class _FakeTechnicalIdentityProvider implements TechnicalIdentityProvider {
  _FakeTechnicalIdentityProvider(this._currentUid);

  final String? _currentUid;

  @override
  String? get currentUid => _currentUid;

  @override
  Future<String> ensureSignedIn() async {
    throw StateError(
      'DineInCheckoutScreen must never call ensureSignedIn() itself — it '
      'only reads the already-established currentUid.',
    );
  }
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
  Future<ProviderContainer> pumpWithSeededCart(
    WidgetTester tester, {
    ActiveTableContext? tableContext,
    TableGuestSessionSnapshot? sessionSnapshot,
    AuthSession? signedInCustomer,
    String? technicalUid = 'guest-technical-uid-1',
  }) async {
    final fakeSessionClient = _FakeTableGuestSessionFirestoreClient();
    if (tableContext != null && sessionSnapshot != null) {
      fakeSessionClient.seed(tableContext.session.id, sessionSnapshot);
    }

    final container = ProviderContainer(
      overrides: [
        tableGuestSessionFirestoreClientProvider
            .overrideWithValue(fakeSessionClient),
        technicalIdentityProviderProvider.overrideWithValue(
          _FakeTechnicalIdentityProvider(technicalUid),
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
    return container;
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
    'guest (customer oturumu yok): customerId null, guestAuthUid teknik uid',
    (tester) async {
      final container = await pumpWithSeededCart(
        tester,
        tableContext: _context(),
        sessionSnapshot: TableGuestSessionSnapshot(
          status: 'active',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
        technicalUid: 'anon-technical-uid-1',
      );

      await tester.tap(
        find.widgetWithText(ElevatedButton, 'Siparişi Ver · 200 TL'),
      );
      await tester.pumpAndSettle();

      expect(find.byType(OrderSuccessScreen), findsOneWidget);
      expect(find.text('Abaküs Ortaköy · Masa 12'), findsOneWidget);
      expect(find.text('Siparişin Alındı!'), findsOneWidget);

      final orders = container.read(ordersProvider).value!;
      expect(orders, hasLength(1));
      final order = orders.first;
      expect(order.channel, OrderChannel.dineInQr);
      expect(order.tableId, 'dev-table-12');

      // The canonical Order (not just its OrderModel projection, which
      // doesn't carry customerId/guestAuthUid at all) is what actually
      // gets written to Firestore — Phase 3.1's real behavior lives here.
      final canonicalOrders =
          await container.read(canonicalOrderRepositoryProvider).findAll();
      expect(canonicalOrders, hasLength(1));
      expect(canonicalOrders.first.customerId, isNull);
      expect(canonicalOrders.first.guestAuthUid, 'anon-technical-uid-1');

      // The order id was attached onto the client-held TableSession via
      // the existing `withOrderAdded` domain seam (Phase 3: local-only —
      // `tableGuestSessions` has no client-writable order-list field).
      final updatedContext = container.read(activeTableContextProvider);
      expect(updatedContext!.session.activeOrderIds, hasLength(1));
      expect(updatedContext.session.activeOrderIds.first, order.id);

      // Cart was cleared after a successful submit.
      expect(container.read(cartProvider), isEmpty);
    },
  );

  testWidgets(
    'reservationContextId taşınan bir masa bağlamında sipariş, canonical Order üzerinde aynı reservationContextId ile oluşur',
    (tester) async {
      final container = await pumpWithSeededCart(
        tester,
        tableContext: _context(reservationContextId: 'RES_123'),
        sessionSnapshot: TableGuestSessionSnapshot(
          status: 'active',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
        technicalUid: 'anon-technical-uid-rc',
      );

      await tester.tap(
        find.widgetWithText(ElevatedButton, 'Siparişi Ver · 200 TL'),
      );
      await tester.pumpAndSettle();

      final canonicalOrders =
          await container.read(canonicalOrderRepositoryProvider).findAll();
      expect(canonicalOrders, hasLength(1));
      expect(canonicalOrders.first.reservationContextId, 'RES_123');
    },
  );

  testWidgets(
    'authenticated customer: customerId gercek uid, guestAuthUid ayni Firebase uid — mevcut auth session overwrite edilmez',
    (tester) async {
      final container = await pumpWithSeededCart(
        tester,
        tableContext: _context(),
        sessionSnapshot: TableGuestSessionSnapshot(
          status: 'active',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
        signedInCustomer: AuthSession(
          uid: 'real-customer-uid',
          phoneNumber: '+905551234567',
          createdAt: DateTime(2026, 8, 1),
          expiresAt: DateTime(2027, 8, 1),
        ),
        // The technical identity the Table Guest Session was opened with
        // matches the real customer's own uid — the expected shape when
        // `TechnicalIdentityProvider.ensureSignedIn()` correctly reused
        // an already-signed-in real customer instead of going anonymous.
        technicalUid: 'real-customer-uid',
      );

      await tester.tap(
        find.widgetWithText(ElevatedButton, 'Siparişi Ver · 200 TL'),
      );
      await tester.pumpAndSettle();

      expect(find.byType(OrderSuccessScreen), findsOneWidget);
      final canonicalOrders =
          await container.read(canonicalOrderRepositoryProvider).findAll();
      expect(canonicalOrders, hasLength(1));
      expect(canonicalOrders.first.customerId, 'real-customer-uid');
      expect(canonicalOrders.first.guestAuthUid, 'real-customer-uid');
    },
  );

  testWidgets(
    'authProvider.session.uid ile mevcut teknik Firebase uid uyusmazsa fail closed davranilir — order olusturulmaz',
    (tester) async {
      final container = await pumpWithSeededCart(
        tester,
        tableContext: _context(),
        sessionSnapshot: TableGuestSessionSnapshot(
          status: 'active',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
        signedInCustomer: AuthSession(
          uid: 'real-customer-uid',
          phoneNumber: '+905551234567',
          createdAt: DateTime(2026, 8, 1),
          expiresAt: DateTime(2027, 8, 1),
        ),
        // Deliberately mismatched — the app believes 'real-customer-uid'
        // is signed in, but the Table Guest Session was actually opened
        // with a different technical uid (should be unreachable in
        // practice; this proves the fail-closed guard, not a realistic
        // user flow).
        technicalUid: 'a-completely-different-uid',
      );

      await tester.tap(
        find.widgetWithText(ElevatedButton, 'Siparişi Ver · 200 TL'),
      );
      await tester.pumpAndSettle();

      expect(find.byType(OrderSuccessScreen), findsNothing);
      final canonicalOrders =
          await container.read(canonicalOrderRepositoryProvider).findAll();
      expect(canonicalOrders, isEmpty);
    },
  );

  testWidgets(
      'hizli cift dokunma sadece bir siparis olusturur (yinelenen '
      'gonderim engellenir)', (tester) async {
    final container = await pumpWithSeededCart(
      tester,
      tableContext: _context(),
      sessionSnapshot: TableGuestSessionSnapshot(
        status: 'active',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      ),
    );

    final button = find.widgetWithText(ElevatedButton, 'Siparişi Ver · 200 TL');
    // Two taps with no pump in between — the second must be swallowed by
    // the `_isSubmitting` guard, not create a second order.
    await tester.tap(button);
    await tester.tap(button);
    await tester.pumpAndSettle();

    final orders = container.read(ordersProvider).value!;
    expect(orders, hasLength(1));
  });

  testWidgets(
    'aktif masa baglami yoksa (kaybolmus baglam) siparis engellenir',
    (tester) async {
      final container = await pumpWithSeededCart(tester);

      await tester.tap(
        find.widgetWithText(ElevatedButton, 'Siparişi Ver · 200 TL'),
      );
      await tester.pumpAndSettle();

      expect(find.byType(OrderSuccessScreen), findsNothing);
      // The error banner is the last item in a non-lazy ListView whose
      // content exceeds the test surface's laid-out extent, so it's
      // genuinely rendered but excluded by the default offstage-skipping
      // finder — skipOffstage: false is required to see it here.
      expect(
        find.textContaining('Masa bilgisi bulunamadı', skipOffstage: false),
        findsOneWidget,
      );
      // `ordersProvider` is an `AsyncNotifier`; `.value` is legitimately
      // null until its `build()` resolves — nothing in this blocked-
      // submission path ever calls `addOrder` to force that, so asserting
      // on `.value` directly races the provider's own lifecycle. Await
      // `.future` first, matching this codebase's established pattern in
      // `orders_provider_test.dart`.
      final orders = await container.read(ordersProvider.future);
      expect(orders, isEmpty);
      expect(container.read(cartProvider), isNotEmpty);
    },
  );

  testWidgets(
    'oturum baska bir yerde kapatilmissa (gecersiz/kaybolmus oturum) '
    'siparis engellenir',
    (tester) async {
      // The context still claims to be active, but the *actual*
      // server-authoritative tableGuestSessions record has since been
      // revoked — e.g. staff closed the table while the customer was
      // sitting on this screen.
      final container = await pumpWithSeededCart(
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
      // Same non-lazy ListView / test-surface-extent artifact as the
      // missing-context test above — the banner is genuinely rendered.
      expect(
        find.textContaining(
          'Masa oturumun artık aktif değil',
          skipOffstage: false,
        ),
        findsOneWidget,
      );
      // Same `AsyncNotifier` lifecycle point as the missing-context test
      // above — await `.future` rather than reading `.value` directly.
      final orders = await container.read(ordersProvider.future);
      expect(orders, isEmpty);
    },
  );

  testWidgets(
    'oturumun suresi dolmussa (expiresAt gecmis) siparis engellenir',
    (tester) async {
      final container = await pumpWithSeededCart(
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
      expect(
        find.textContaining(
          'Masa oturumun artık aktif değil',
          skipOffstage: false,
        ),
        findsOneWidget,
      );
      final orders = await container.read(ordersProvider.future);
      expect(orders, isEmpty);
    },
  );

  testWidgets(
    'siparişin branchId alanı QR ile çözülen gerçek şubeden gelir, '
    'submitCustomerOrderProvider\'ın varsayılanından değil (Faz B)',
    (tester) async {
      final container = await pumpWithSeededCart(
        tester,
        // A branch distinct from submitCustomerOrderProvider's constructor
        // default ('branch-1') — proves the wiring, not a coincidence.
        tableContext: _context(branchId: 'branch-ortakoy-2'),
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
      final canonicalOrders =
          await container.read(canonicalOrderRepositoryProvider).findAll();
      expect(canonicalOrders, hasLength(1));
      expect(canonicalOrders.first.branchId, 'branch-ortakoy-2');
    },
  );

  testWidgets(
    'siparişin restaurantId alanı da QR ile çözülen gerçek işletmeden '
    'gelir, submitCustomerOrderProvider\'ın varsayılanından değil (Faz B.1)',
    (tester) async {
      final container = await pumpWithSeededCart(
        tester,
        // A restaurantId distinct from submitCustomerOrderProvider's
        // constructor default ('restaurant-1') — proves the wiring, not a
        // coincidence, and that branchId/restaurantId can vary
        // independently.
        tableContext: _context(
          branchId: 'branch-ortakoy-2',
          restaurantId: 'restaurant-abakus-2',
        ),
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
      final canonicalOrders =
          await container.read(canonicalOrderRepositoryProvider).findAll();
      expect(canonicalOrders, hasLength(1));
      expect(canonicalOrders.first.branchId, 'branch-ortakoy-2');
      expect(canonicalOrders.first.restaurantId, 'restaurant-abakus-2');
    },
  );
}
