import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abakus_one_v2/features/admin/data/takeaway_order_response_gateway.dart';
import 'package:abakus_one_v2/features/admin/presentation/providers/admin_dependencies_provider.dart';
import 'package:abakus_one_v2/features/cart/domain/models/cart_item.dart';
import 'package:abakus_one_v2/features/orders/data/canonical_order_repository.dart';
import 'package:abakus_one_v2/features/orders/domain/mappers/cart_to_order_mapper.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_actor.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_channel.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_number.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_status.dart';
import 'package:abakus_one_v2/features/orders/presentation/providers/orders_provider.dart';
import 'package:abakus_one_v2/features/pos/data/kitchen_action_gateway.dart';
import 'package:abakus_one_v2/features/pos/data/pos_action_gateway.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/kds_dependencies_provider.dart';
import 'package:abakus_one_v2/features/pos/presentation/screens/pos_takeaway_orders_screen.dart';

/// Adım 5 (2026-11-07) — "Paket / Gel-Al" screen. Fakes only RECORD calls
/// (mirrors `admin_orders_screen_test.dart`'s own `_FakeTakeawayOrderResponseGateway`
/// shape exactly) rather than mutating the in-memory order repository —
/// this file proves the screen calls the right real gateway method with
/// the right orderId/targetStatus, which is the actual wiring gap this
/// item closes; it does not re-prove the backend's own lifecycle rules.
class _FakeTakeawayOrderResponseGateway
    implements TakeawayOrderResponseGateway {
  int confirmCallCount = 0;
  int rejectCallCount = 0;
  String? lastOrderId;
  TakeawayRejectionReasonCode? lastReasonCode;

  @override
  Future<void> confirm({required String orderId}) async {
    confirmCallCount += 1;
    lastOrderId = orderId;
  }

  @override
  Future<void> reject({
    required String orderId,
    required TakeawayRejectionReasonCode reasonCode,
    String? reasonMessage,
  }) async {
    rejectCallCount += 1;
    lastOrderId = orderId;
    lastReasonCode = reasonCode;
  }
}

class _FakeKitchenActionGateway implements KitchenActionGateway {
  int advanceCallCount = 0;
  String? lastOrderId;
  String? lastChannel;
  String? lastTargetStatus;

  @override
  Future<KitchenActionResult> transitionWorkItem({
    required String workItemId,
    required dynamic to,
    required int expectedRevision,
    String? reason,
  }) {
    throw UnimplementedError('not exercised by this screen');
  }

  @override
  Future<void> advanceOrderStatus({
    required String orderId,
    required String channel,
    required String targetStatus,
    String? reasonCode,
    String? reasonMessage,
  }) async {
    advanceCallCount += 1;
    lastOrderId = orderId;
    lastChannel = channel;
    lastTargetStatus = targetStatus;
  }
}

const _ctx = PosDeviceContext(
  organizationId: 'org-1',
  branchId: 'branch-1',
  deviceId: 'device-1',
  deviceSessionId: 'session-1',
);

Order _buildTakeawayOrder({
  required String orderId,
  required OrderStatus targetStatus,
}) {
  final now = DateTime(2026, 11, 7, 12, 0);
  var order = CartToOrderMapper.map(
    orderId: OrderId(orderId),
    orderNumber: OrderNumber('TA-${orderId.toUpperCase()}'),
    cartItems: [
      const CartItem(
          id: 'p1', name: 'Paket Kutu', desc: '', price: 100, quantity: 1),
    ],
    channel: OrderChannel.takeaway,
    branchId: _ctx.branchId,
    restaurantId: 'restaurant-1',
    contactFirstName: 'Ahmet',
    contactLastName: 'Yılmaz',
    contactPhone: '+905551112233',
    now: now,
  );
  const chain = [
    OrderStatus.pendingConfirmation,
    OrderStatus.confirmed,
    OrderStatus.preparing,
    OrderStatus.ready,
  ];
  for (final status in chain) {
    order = order.transitionTo(
      status,
      actor: OrderActor.staff,
      at: now,
      auditEntryId: '$orderId-transition-${status.name}',
    );
    if (status == targetStatus) break;
  }
  return order;
}

Future<
    (
      InMemoryCanonicalOrderRepository,
      _FakeTakeawayOrderResponseGateway,
      _FakeKitchenActionGateway
    )> _pump(
  WidgetTester tester, {
  required List<Order> orders,
}) async {
  final repository = InMemoryCanonicalOrderRepository();
  for (final order in orders) {
    await repository.submitOrder(order);
  }
  final responseGateway = _FakeTakeawayOrderResponseGateway();
  final kitchenGateway = _FakeKitchenActionGateway();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        canonicalOrderRepositoryProvider.overrideWithValue(repository),
        takeawayOrderResponseGatewayProvider.overrideWithValue(responseGateway),
        kitchenActionGatewayProvider.overrideWithValue(kitchenGateway),
      ],
      child: const MaterialApp(
        home: Scaffold(body: PosTakeawayOrdersScreen(ctx: _ctx)),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return (repository, responseGateway, kitchenGateway);
}

void main() {
  testWidgets(
      'onay bekleyen bir siparis "Onay Bekliyor" rozeti ve Onayla/Reddet '
      'butonlariyla gorunur; Onayla gercek gateway.confirm cagirir',
      (tester) async {
    final order = _buildTakeawayOrder(
        orderId: 'order-1', targetStatus: OrderStatus.pendingConfirmation);
    final (_, responseGateway, _) = await _pump(tester, orders: [order]);

    expect(find.text('Onay Bekliyor'), findsOneWidget);
    expect(find.text('Onayla'), findsOneWidget);
    expect(find.text('Reddet'), findsOneWidget);

    await tester.tap(find.text('Onayla'));
    await tester.pump();

    expect(responseGateway.confirmCallCount, 1);
    expect(responseGateway.lastOrderId, 'order-1');
  });

  testWidgets('Reddet diyalogu secilen gerekceyle gateway.reject cagirir',
      (tester) async {
    final order = _buildTakeawayOrder(
        orderId: 'order-2', targetStatus: OrderStatus.pendingConfirmation);
    final (_, responseGateway, _) = await _pump(tester, orders: [order]);

    await tester.tap(find.text('Reddet'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kapasite yetersiz'));
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Reddet'));
    await tester.pumpAndSettle();

    expect(responseGateway.rejectCallCount, 1);
    expect(responseGateway.lastOrderId, 'order-2');
    expect(responseGateway.lastReasonCode,
        TakeawayRejectionReasonCode.capacityUnavailable);
  });

  testWidgets(
      'confirmed bir siparis "Hazirlaniyor Olarak Isaretle" gosterir, '
      'basinca advanceOrderStatus(targetStatus: preparing) cagirir',
      (tester) async {
    final order = _buildTakeawayOrder(
        orderId: 'order-3', targetStatus: OrderStatus.confirmed);
    final (_, _, kitchenGateway) = await _pump(tester, orders: [order]);

    expect(find.text('Onaylandı'), findsOneWidget);
    await tester.tap(find.text('Hazırlanıyor Olarak İşaretle'));
    await tester.pump();

    expect(kitchenGateway.advanceCallCount, 1);
    expect(kitchenGateway.lastOrderId, 'order-3');
    expect(kitchenGateway.lastChannel, 'takeaway');
    expect(kitchenGateway.lastTargetStatus, 'preparing');
  });

  testWidgets(
      'ready bir siparis "Teslim Edildi" gosterir, basinca '
      'advanceOrderStatus(targetStatus: completed) cagirir', (tester) async {
    final order = _buildTakeawayOrder(
        orderId: 'order-4', targetStatus: OrderStatus.ready);
    final (_, _, kitchenGateway) = await _pump(tester, orders: [order]);

    expect(find.text('Hazır, Gelip Alabilir'), findsOneWidget);
    await tester.tap(find.text('Teslim Edildi'));
    await tester.pump();

    expect(kitchenGateway.advanceCallCount, 1);
    expect(kitchenGateway.lastTargetStatus, 'completed');
  });

  testWidgets(
      'hic aktif paket siparisi yokken bos durum mesaji gosterir, asla '
      'bos bir liste degil', (tester) async {
    await _pump(tester, orders: []);

    expect(
        find.textContaining('aktif paket/gel-al siparişi yok'), findsOneWidget);
  });

  testWidgets('dineInQr kanalindaki bir siparis bu listede hic gorunmez',
      (tester) async {
    final now = DateTime(2026, 11, 7, 12, 0);
    final dineInOrder = CartToOrderMapper.map(
      orderId: OrderId('dinein-1'),
      orderNumber: OrderNumber('D-001'),
      cartItems: [
        const CartItem(
            id: 'p1', name: 'Klasik Bowl', desc: '', price: 100, quantity: 1),
      ],
      channel: OrderChannel.dineInQr,
      branchId: _ctx.branchId,
      restaurantId: 'restaurant-1',
      now: now,
    );
    await _pump(tester, orders: [dineInOrder]);

    expect(find.text('Klasik Bowl'), findsNothing);
    expect(
        find.textContaining('aktif paket/gel-al siparişi yok'), findsOneWidget);
  });
}
