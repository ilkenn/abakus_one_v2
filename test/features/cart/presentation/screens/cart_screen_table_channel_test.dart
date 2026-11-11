import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abakus_one_v2/features/cart/presentation/providers/cart_provider.dart';
import 'package:abakus_one_v2/features/cart/presentation/providers/shopping_channel_provider.dart';
import 'package:abakus_one_v2/features/cart/presentation/providers/table_session_cart_dependencies_provider.dart';
import 'package:abakus_one_v2/features/cart/presentation/screens/cart_screen.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_channel.dart';
import 'package:abakus_one_v2/features/qr/data/technical_identity_provider.dart';
import 'package:abakus_one_v2/features/qr/domain/models/active_table_context.dart';
import 'package:abakus_one_v2/features/qr/domain/models/guest_session.dart';
import 'package:abakus_one_v2/features/qr/domain/models/table_session.dart';
import 'package:abakus_one_v2/features/qr/presentation/providers/active_table_context_provider.dart';
import 'package:abakus_one_v2/features/qr/presentation/providers/table_guest_session_dependencies_provider.dart';

import '../../test_support/fake_table_session_cart_firestore_client.dart';

/// 2026-11-11 — at a QR table the shopping channel stayed `delivery`, so
/// every shared-cart line (always `dineInQr`) was flagged "farklı bir
/// sipariş modu için fiyatlandırılmış" and "Siparişi Tamamla" stayed
/// locked, even right after clearing the cart and adding one product.
class _FakeTechnicalIdentityProvider implements TechnicalIdentityProvider {
  @override
  String? get currentUid => 'guest-uid-1';

  @override
  Future<String> ensureSignedIn() async => 'guest-uid-1';
}

ActiveTableContext _tableContext() {
  final now = DateTime(2026, 11, 11);
  return ActiveTableContext(
    restaurantId: 'restaurant-1',
    branchId: 'branch-1',
    branchName: 'Merkez Şube',
    tableId: 'qr-test-1',
    tableName: 'QR Test Masası',
    sharedCartTableSessionId: 'tsess-1',
    session: TableSession(
      id: 'tgs-1',
      restaurantId: 'restaurant-1',
      branchId: 'branch-1',
      tableId: 'qr-test-1',
      status: TableSessionStatus.active,
      openedAt: now,
      guestSessionIds: const [],
      activeOrderIds: const [],
    ),
    guestSession: GuestSession(
      id: 'gsession-1',
      tableSessionId: 'tgs-1',
      branchId: 'branch-1',
      tableId: 'qr-test-1',
      detectedLanguageCode: 'tr',
      selectedLanguageCode: 'tr',
      createdAt: now,
      lastSeenAt: now,
      status: GuestSessionStatus.active,
    ),
  );
}

ProviderContainer _container() {
  final container = ProviderContainer(
    overrides: [
      tableSessionCartFirestoreClientProvider
          .overrideWithValue(FakeTableSessionCartFirestoreClient()),
      technicalIdentityProviderProvider
          .overrideWithValue(_FakeTechnicalIdentityProvider()),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test(
      'the shopping channel is dineInQr (with the table\'s branch) while a '
      'table session is active, and delivery again once it ends', () {
    final container = _container();
    expect(
        container.read(shoppingChannelProvider).channel, OrderChannel.delivery);

    container.read(activeTableContextProvider.notifier).set(_tableContext());
    final atTable = container.read(shoppingChannelProvider);
    expect(atTable.channel, OrderChannel.dineInQr);
    expect(atTable.restaurantId, 'restaurant-1');
    expect(atTable.branchId, 'branch-1');
    expect(atTable.branchDisplayName, 'Merkez Şube');

    container.read(activeTableContextProvider.notifier).clear();
    expect(
        container.read(shoppingChannelProvider).channel, OrderChannel.delivery);
  });

  testWidgets(
      'at a QR table, a product added to the shared cart shows no stale-'
      'channel warning and "Siparişi Tamamla" is enabled', (tester) async {
    final container = _container();
    container.read(activeTableContextProvider.notifier).set(_tableContext());
    container.read(cartProvider);

    container.read(cartProvider.notifier).addToCart(
          id: 'clasico',
          name: 'Clasico',
          desc: '',
          price: 320,
          pricedForChannel: container.read(shoppingChannelProvider).channel,
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: CartScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(container.read(cartProvider), hasLength(1));
    expect(container.read(cartProvider).single.pricedForChannel,
        OrderChannel.dineInQr);
    expect(
      find.textContaining('farklı bir sipariş modu için fiyatlandırılmış'),
      findsNothing,
    );
    final button = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Siparişi Tamamla'),
    );
    expect(button.onPressed, isNotNull);
  });
}
