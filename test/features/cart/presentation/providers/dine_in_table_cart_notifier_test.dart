import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/cart/data/table_session_cart_firestore_client.dart';
import 'package:abakus_one_v2/features/cart/domain/models/cart_item.dart';
import 'package:abakus_one_v2/features/cart/presentation/providers/cart_provider.dart';
import 'package:abakus_one_v2/features/cart/presentation/providers/table_session_cart_dependencies_provider.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_channel.dart';
import 'package:abakus_one_v2/features/qr/data/technical_identity_provider.dart';
import 'package:abakus_one_v2/features/qr/domain/models/active_table_context.dart';
import 'package:abakus_one_v2/features/qr/domain/models/guest_session.dart';
import 'package:abakus_one_v2/features/qr/domain/models/table_session.dart';
import 'package:abakus_one_v2/features/qr/presentation/providers/active_table_context_provider.dart';
import 'package:abakus_one_v2/features/qr/presentation/providers/table_guest_session_dependencies_provider.dart';

class _RecordedCall {
  final String method;
  final Map<String, Object?> args;
  _RecordedCall(this.method, this.args);
}

/// Records every call and exposes a controllable stream per table session —
/// stands in for the real Firestore-backed client so these tests never
/// need the (unavailable in this environment) Firestore emulator.
class _FakeTableSessionCartFirestoreClient
    implements TableSessionCartFirestoreClient {
  final List<_RecordedCall> calls = [];
  final Map<String, StreamController<List<CartItem>>> _controllers = {};

  StreamController<List<CartItem>> controllerFor(String tableSessionId) {
    return _controllers.putIfAbsent(
      tableSessionId,
      () => StreamController<List<CartItem>>.broadcast(),
    );
  }

  @override
  Stream<List<CartItem>> watchLines(String tableSessionId) {
    return controllerFor(tableSessionId).stream;
  }

  @override
  Future<void> upsertLine({
    required String tableSessionId,
    required CartItem item,
  }) async {
    calls.add(_RecordedCall('upsertLine', {
      'tableSessionId': tableSessionId,
      'item': item,
    }));
  }

  @override
  Future<void> adjustLineQuantity({
    required String tableSessionId,
    required String addedBySubAccountId,
    required String customizationsKey,
    required int delta,
  }) async {
    calls.add(_RecordedCall('adjustLineQuantity', {
      'tableSessionId': tableSessionId,
      'addedBySubAccountId': addedBySubAccountId,
      'customizationsKey': customizationsKey,
      'delta': delta,
    }));
  }

  @override
  Future<void> setLineQuantity({
    required String tableSessionId,
    required String addedBySubAccountId,
    required String customizationsKey,
    required int quantity,
  }) async {
    calls.add(_RecordedCall('setLineQuantity', {
      'tableSessionId': tableSessionId,
      'addedBySubAccountId': addedBySubAccountId,
      'customizationsKey': customizationsKey,
      'quantity': quantity,
    }));
  }

  @override
  Future<void> removeLine({
    required String tableSessionId,
    required String addedBySubAccountId,
    required String customizationsKey,
  }) async {
    calls.add(_RecordedCall('removeLine', {
      'tableSessionId': tableSessionId,
      'addedBySubAccountId': addedBySubAccountId,
      'customizationsKey': customizationsKey,
    }));
  }
}

class _FakeTechnicalIdentityProvider implements TechnicalIdentityProvider {
  _FakeTechnicalIdentityProvider(this.uid);
  final String? uid;

  @override
  String? get currentUid => uid;

  @override
  Future<String> ensureSignedIn() async => uid ?? 'fake-uid';
}

ActiveTableContext _buildTableContext({
  required String tableSessionId,
  required DateTime now,
}) {
  return ActiveTableContext(
    restaurantId: 'restaurant-1',
    branchId: 'branch-1',
    branchName: 'Abaküs Ortaköy',
    tableId: 'table-1',
    tableName: 'Masa 12',
    session: TableSession(
      id: tableSessionId,
      restaurantId: 'restaurant-1',
      branchId: 'branch-1',
      tableId: 'table-1',
      status: TableSessionStatus.active,
      openedAt: now,
      guestSessionIds: const [],
      activeOrderIds: const [],
    ),
    guestSession: GuestSession(
      id: 'gsession-1',
      tableSessionId: tableSessionId,
      branchId: 'branch-1',
      tableId: 'table-1',
      detectedLanguageCode: 'tr',
      selectedLanguageCode: 'tr',
      createdAt: now,
      lastSeenAt: now,
      status: GuestSessionStatus.active,
    ),
  );
}

void main() {
  late ProviderContainer container;
  late _FakeTableSessionCartFirestoreClient fakeClient;
  const uid = 'guest-uid-1';
  const tableSessionId = 'ts-1';
  const expectedSubAccountId = 'subaccount-$tableSessionId-$uid';

  setUp(() {
    fakeClient = _FakeTableSessionCartFirestoreClient();
    container = ProviderContainer(
      overrides: [
        tableSessionCartFirestoreClientProvider.overrideWithValue(fakeClient),
        technicalIdentityProviderProvider
            .overrideWithValue(_FakeTechnicalIdentityProvider(uid)),
      ],
    );
  });

  tearDown(() => container.dispose());

  group('aktif masa baglami yokken (takeaway/delivery/personal)', () {
    test('addToCart yerel state\'i degistirir, Firestore\'a hic yazmaz', () {
      container.read(cartProvider.notifier).addToCart(
            id: 'prod-1',
            name: 'Test Ürün',
            desc: 'açıklama',
            price: 50,
          );

      expect(container.read(cartProvider), hasLength(1));
      expect(container.read(cartProvider).first.addedBySubAccountId, isNull);
      expect(fakeClient.calls, isEmpty);
    });
  });

  group('aktif masa baglami varken (Self-Order QR Faz 3 paylasimli sepet)', () {
    void activateTableContext() {
      container.read(activeTableContextProvider.notifier).set(
            _buildTableContext(
              tableSessionId: tableSessionId,
              now: DateTime(2026, 11, 5),
            ),
          );
      // Forces `cartProvider`'s own `build()` (and therefore its
      // `watchLines` subscription) to run now — the fake controller below
      // is a broadcast stream, which drops anything emitted before a
      // listener attaches, exactly like the real Firestore SDK's own
      // snapshot stream would for a late subscriber.
      container.read(cartProvider);
    }

    test(
        'addToCart yerel state\'i DEGISTIRMEZ, Firestore client\'ina '
        'dogru tableSessionId/addedBySubAccountId ile yazar', () {
      activateTableContext();

      container.read(cartProvider.notifier).addToCart(
            id: 'prod-1',
            name: 'Test Ürün',
            desc: 'açıklama',
            price: 50,
          );

      // State hala bos — gercek guncelleme sadece gelen snapshot'tan gelir.
      expect(container.read(cartProvider), isEmpty);
      expect(fakeClient.calls, hasLength(1));
      final call = fakeClient.calls.single;
      expect(call.method, 'upsertLine');
      expect(call.args['tableSessionId'], tableSessionId);
      final item = call.args['item'] as CartItem;
      expect(item.addedBySubAccountId, expectedSubAccountId);
      expect(item.pricedForChannel, OrderChannel.dineInQr);
      expect(item.id, 'prod-1');
    });

    test(
        'Firestore\'dan gelen bir snapshot cartProvider state\'ini '
        'guncelleyecektir (diger misafirlerin satirlari dahil)', () async {
      activateTableContext();
      const mine = CartItem(
        id: 'prod-1',
        name: 'Benim Ürünüm',
        desc: '',
        price: 50,
        quantity: 1,
        customizationsKey: 'prod-1',
        addedBySubAccountId: expectedSubAccountId,
      );
      const theirs = CartItem(
        id: 'prod-2',
        name: 'Başka Misafirin Ürünü',
        desc: '',
        price: 30,
        quantity: 1,
        customizationsKey: 'prod-2',
        addedBySubAccountId: 'subaccount-ts-1-guest-uid-2',
      );

      fakeClient.controllerFor(tableSessionId).add([mine, theirs]);
      await Future<void>.delayed(Duration.zero);

      expect(container.read(cartProvider), [mine, theirs]);
    });

    test(
        'baska bir misafirin satirina incrementQuantity cagirmak hicbir '
        'sey yapmaz (sahiplik korumasi)', () async {
      activateTableContext();
      const theirs = CartItem(
        id: 'prod-2',
        name: 'Başka Misafirin Ürünü',
        desc: '',
        price: 30,
        quantity: 1,
        customizationsKey: 'prod-2',
        addedBySubAccountId: 'subaccount-ts-1-guest-uid-2',
      );
      fakeClient.controllerFor(tableSessionId).add([theirs]);
      await Future<void>.delayed(Duration.zero);

      container.read(cartProvider.notifier).incrementQuantity('prod-2');

      expect(fakeClient.calls, isEmpty);
    });

    test(
        'kendi satirina incrementQuantity cagirmak adjustLineQuantity\'i '
        'delta: 1 ile cagirir', () async {
      activateTableContext();
      const mine = CartItem(
        id: 'prod-1',
        name: 'Benim Ürünüm',
        desc: '',
        price: 50,
        quantity: 1,
        customizationsKey: 'prod-1',
        addedBySubAccountId: expectedSubAccountId,
      );
      fakeClient.controllerFor(tableSessionId).add([mine]);
      await Future<void>.delayed(Duration.zero);

      container.read(cartProvider.notifier).incrementQuantity('prod-1');

      final call = fakeClient.calls.single;
      expect(call.method, 'adjustLineQuantity');
      expect(call.args['delta'], 1);
      expect(call.args['addedBySubAccountId'], expectedSubAccountId);
    });

    test(
        'miktari 1 olan kendi satirina decrementQuantity cagirmak '
        'removeLine cagirir (adjustLineQuantity degil)', () async {
      activateTableContext();
      const mine = CartItem(
        id: 'prod-1',
        name: 'Benim Ürünüm',
        desc: '',
        price: 50,
        quantity: 1,
        customizationsKey: 'prod-1',
        addedBySubAccountId: expectedSubAccountId,
      );
      fakeClient.controllerFor(tableSessionId).add([mine]);
      await Future<void>.delayed(Duration.zero);

      container.read(cartProvider.notifier).decrementQuantity('prod-1');

      final call = fakeClient.calls.single;
      expect(call.method, 'removeLine');
    });

    test(
        'clearCart SADECE kendi satirlarini kaldirir, baska misafirin '
        'satirina dokunmaz', () async {
      activateTableContext();
      const mine = CartItem(
        id: 'prod-1',
        name: 'Benim Ürünüm',
        desc: '',
        price: 50,
        quantity: 1,
        customizationsKey: 'prod-1',
        addedBySubAccountId: expectedSubAccountId,
      );
      const theirs = CartItem(
        id: 'prod-2',
        name: 'Başka Misafirin Ürünü',
        desc: '',
        price: 30,
        quantity: 1,
        customizationsKey: 'prod-2',
        addedBySubAccountId: 'subaccount-ts-1-guest-uid-2',
      );
      fakeClient.controllerFor(tableSessionId).add([mine, theirs]);
      await Future<void>.delayed(Duration.zero);

      container.read(cartProvider.notifier).clearCart();

      expect(fakeClient.calls, hasLength(1));
      final call = fakeClient.calls.single;
      expect(call.method, 'removeLine');
      expect(call.args['addedBySubAccountId'], expectedSubAccountId);
      expect(call.args['customizationsKey'], 'prod-1');
    });

    test(
        'masa oturumu temizlenince (activeTableContextProvider.clear()) '
        'state bosalir ve sonraki addToCart yerel moda doner', () {
      activateTableContext();

      container.read(activeTableContextProvider.notifier).clear();

      expect(container.read(cartProvider), isEmpty);

      container.read(cartProvider.notifier).addToCart(
            id: 'prod-9',
            name: 'Takeaway Ürünü',
            desc: '',
            price: 20,
          );

      expect(container.read(cartProvider), hasLength(1));
      expect(container.read(cartProvider).first.addedBySubAccountId, isNull);
      expect(fakeClient.calls, isEmpty);
    });
  });
}
