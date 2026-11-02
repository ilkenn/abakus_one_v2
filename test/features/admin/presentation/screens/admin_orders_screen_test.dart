import 'package:abakus_one_v2/features/admin/data/dine_in_order_response_gateway.dart';
import 'package:abakus_one_v2/features/admin/data/takeaway_order_response_gateway.dart';
import 'package:abakus_one_v2/features/admin/presentation/providers/admin_dependencies_provider.dart';
import 'package:abakus_one_v2/features/admin/presentation/providers/admin_orders_provider.dart';
import 'package:abakus_one_v2/features/admin/presentation/screens/admin_orders_screen.dart';
import 'package:abakus_one_v2/features/orders/domain/models/dine_in_line_status.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_channel.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_line.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_line_approval_state.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_number.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_status.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_timestamps.dart';
import 'package:abakus_one_v2/features/orders/domain/pricing/price_calculator.dart';
import 'package:abakus_one_v2/features/orders/domain/pricing/tax_policy.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:abakus_one_v2/shared/widgets/feedback/error_view.dart';
import 'package:abakus_one_v2/shared/widgets/feedback/loading_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Order _buildOrder({
  required String id,
  required OrderStatus status,
  OrderChannel channel = OrderChannel.dineInStaff,
  DateTime? created,
  String? tableNumber,
  String? tableSection,
  List<OrderLineApprovalState> lineApprovalStates = const [],
}) {
  final line = OrderLine.create(
    productId: 'p1',
    productName: 'Mexifit Bowl',
    quantity: 1,
    unitPrice: Money.fromWhole(194, Currency.tryLira),
    taxRate: TaxPolicy.defaultRate,
  );
  return Order(
    id: OrderId(id),
    orderNumber: OrderNumber(id.toUpperCase()),
    status: status,
    channel: channel,
    branchId: 'branch-1',
    restaurantId: 'restaurant-1',
    lines: [line],
    lineApprovalStates: lineApprovalStates,
    pricing:
        PriceCalculator.calculate(lines: [line], currency: Currency.tryLira),
    timestamps: OrderTimestamps(created: created ?? DateTime(2026, 10, 27, 12)),
    tableNumber: tableNumber,
    tableSection: tableSection,
  );
}

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

class _FakeDineInOrderResponseGateway implements DineInOrderResponseGateway {
  int confirmCallCount = 0;
  int rejectCallCount = 0;
  String? lastOrderId;
  List<int>? lastPendingLineIndexes;
  DineInRejectionReasonCode? lastReasonCode;

  @override
  Future<void> confirm({
    required String orderId,
    required List<int> pendingLineIndexes,
  }) async {
    confirmCallCount += 1;
    lastOrderId = orderId;
    lastPendingLineIndexes = pendingLineIndexes;
  }

  @override
  Future<void> reject({
    required String orderId,
    required DineInRejectionReasonCode reasonCode,
    String? reasonMessage,
  }) async {
    rejectCallCount += 1;
    lastOrderId = orderId;
    lastReasonCode = reasonCode;
  }
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required AsyncValue<List<Order>> state,
  TakeawayOrderResponseGateway? responseGateway,
  DineInOrderResponseGateway? dineInResponseGateway,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        adminOrdersProvider.overrideWith((ref) {
          return switch (state) {
            AsyncData(:final value) => Stream.value(value),
            AsyncError(:final error) => Stream<List<Order>>.error(error),
            _ => const Stream<List<Order>>.empty(),
          };
        }),
        if (responseGateway != null)
          takeawayOrderResponseGatewayProvider
              .overrideWithValue(responseGateway),
        if (dineInResponseGateway != null)
          dineInOrderResponseGatewayProvider
              .overrideWithValue(dineInResponseGateway),
      ],
      child: const MaterialApp(home: AdminOrdersScreen()),
    ),
  );
}

void main() {
  testWidgets('loading state shows the loading view', (tester) async {
    await _pumpScreen(tester, state: const AsyncLoading());
    await tester.pump();

    expect(find.byType(LoadingView), findsOneWidget);
  });

  testWidgets('an empty branch shows the empty-state view', (tester) async {
    await _pumpScreen(tester, state: const AsyncData([]));
    await tester.pumpAndSettle();

    expect(find.text('Bu şubede henüz bir sipariş yok.'), findsOneWidget);
  });

  testWidgets('shows every order, newest first, with its status label',
      (tester) async {
    await _pumpScreen(
      tester,
      state: AsyncData([
        _buildOrder(
          id: 'order-1',
          status: OrderStatus.completed,
          created: DateTime(2026, 10, 27, 10),
        ),
        _buildOrder(
          id: 'order-2',
          status: OrderStatus.preparing,
          created: DateTime(2026, 10, 27, 14),
        ),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('ORDER-1'), findsOneWidget);
    expect(find.text('ORDER-2'), findsOneWidget);
    expect(find.text('Tamamlandı'), findsOneWidget);
    expect(find.text('Hazırlanıyor'), findsOneWidget);

    // Newest (order-2, 14:00) must render above the oldest (order-1, 10:00).
    final order1Top = tester.getTopLeft(find.text('ORDER-1')).dy;
    final order2Top = tester.getTopLeft(find.text('ORDER-2')).dy;
    expect(order2Top, lessThan(order1Top));
  });

  testWidgets(
      '2026-10-28 launch: a dine-in order with a table snapshot shows '
      'which table it came from', (tester) async {
    await _pumpScreen(
      tester,
      state: AsyncData([
        _buildOrder(
          id: 'order-3',
          status: OrderStatus.pendingConfirmation,
          channel: OrderChannel.dineInQr,
          tableNumber: 'İç Masa 1',
          tableSection: 'İç Mekan',
        ),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('İç Masa 1 (İç Mekan)'), findsOneWidget);
  });

  testWidgets(
      'a dine-in order with no table snapshot (pre-launch order) shows no '
      'table suffix, never a null/empty placeholder', (tester) async {
    await _pumpScreen(
      tester,
      state: AsyncData([
        _buildOrder(
          id: 'order-4',
          status: OrderStatus.pendingConfirmation,
          channel: OrderChannel.dineInStaff,
        ),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('null'), findsNothing);
    expect(
      find.text('Masa (Personel) · 27.10.2026 12:00'),
      findsOneWidget,
    );
  });

  testWidgets('an error shows the error view with a working retry',
      (tester) async {
    await _pumpScreen(tester,
        state: AsyncError(StateError('boom'), StackTrace.empty));
    await tester.pumpAndSettle();

    expect(find.text('Siparişler yüklenemedi.'), findsOneWidget);
    expect(find.byType(ErrorView), findsOneWidget);
  });

  testWidgets(
      'a pendingConfirmation takeaway order shows Kabul Et/Reddet; other orders never do',
      (tester) async {
    await _pumpScreen(
      tester,
      state: AsyncData([
        _buildOrder(
          id: 'order-1',
          status: OrderStatus.pendingConfirmation,
          channel: OrderChannel.takeaway,
        ),
        _buildOrder(
          id: 'order-2',
          status: OrderStatus.confirmed,
          channel: OrderChannel.takeaway,
        ),
        _buildOrder(
          id: 'order-3',
          status: OrderStatus.pendingConfirmation,
          channel: OrderChannel.dineInStaff,
        ),
      ]),
      responseGateway: _FakeTakeawayOrderResponseGateway(),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ElevatedButton, 'Kabul Et'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Reddet'), findsOneWidget);
  });

  testWidgets('tapping Kabul Et calls the gateway and refreshes the list',
      (tester) async {
    final gateway = _FakeTakeawayOrderResponseGateway();
    await _pumpScreen(
      tester,
      state: AsyncData([
        _buildOrder(
          id: 'order-1',
          status: OrderStatus.pendingConfirmation,
          channel: OrderChannel.takeaway,
        ),
      ]),
      responseGateway: gateway,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Kabul Et'));
    await tester.pumpAndSettle();

    expect(gateway.confirmCallCount, 1);
    expect(gateway.lastOrderId, 'order-1');
    expect(find.text('Sipariş kabul edildi.'), findsOneWidget);
  });

  testWidgets(
      'tapping Reddet opens a reason picker and calls the gateway with the selected reason',
      (tester) async {
    final gateway = _FakeTakeawayOrderResponseGateway();
    await _pumpScreen(
      tester,
      state: AsyncData([
        _buildOrder(
          id: 'order-1',
          status: OrderStatus.pendingConfirmation,
          channel: OrderChannel.takeaway,
        ),
      ]),
      responseGateway: gateway,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Reddet'));
    await tester.pumpAndSettle();

    expect(find.text('Siparişi Reddet'), findsOneWidget);
    await tester.tap(find.text('Mutfak müsait değil'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Reddet'));
    await tester.pumpAndSettle();

    expect(gateway.rejectCallCount, 1);
    expect(gateway.lastOrderId, 'order-1');
    expect(
        gateway.lastReasonCode, TakeawayRejectionReasonCode.kitchenUnavailable);
    expect(find.text('Sipariş reddedildi.'), findsOneWidget);
  });

  testWidgets(
      '2026-10-29: a pendingConfirmation dine-in (QR) order shows Onayla/'
      'Reddet too, mirroring takeaway', (tester) async {
    await _pumpScreen(
      tester,
      state: AsyncData([
        _buildOrder(
          id: 'order-5',
          status: OrderStatus.pendingConfirmation,
          channel: OrderChannel.dineInQr,
        ),
      ]),
      dineInResponseGateway: _FakeDineInOrderResponseGateway(),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ElevatedButton, 'Onayla'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Reddet'), findsOneWidget);
  });

  testWidgets(
      '2026-10-29: tapping Onayla on a dine-in order accepts every '
      'pendingApproval line then advances the order status, in that order',
      (tester) async {
    final gateway = _FakeDineInOrderResponseGateway();
    await _pumpScreen(
      tester,
      state: AsyncData([
        _buildOrder(
          id: 'order-5',
          status: OrderStatus.pendingConfirmation,
          channel: OrderChannel.dineInQr,
          lineApprovalStates: const [
            OrderLineApprovalState(
                lineIndex: 0, status: DineInLineStatus.pendingApproval),
          ],
        ),
      ]),
      dineInResponseGateway: gateway,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Onayla'));
    await tester.pumpAndSettle();

    expect(gateway.confirmCallCount, 1);
    expect(gateway.lastOrderId, 'order-5');
    expect(gateway.lastPendingLineIndexes, [0]);
    expect(find.text('Sipariş onaylandı.'), findsOneWidget);
  });

  testWidgets(
      '2026-10-29: tapping Reddet on a dine-in order opens a reason picker '
      'and calls the gateway with the selected reason', (tester) async {
    final gateway = _FakeDineInOrderResponseGateway();
    await _pumpScreen(
      tester,
      state: AsyncData([
        _buildOrder(
          id: 'order-5',
          status: OrderStatus.pendingConfirmation,
          channel: OrderChannel.dineInQr,
        ),
      ]),
      dineInResponseGateway: gateway,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Reddet'));
    await tester.pumpAndSettle();

    expect(find.text('Siparişi Reddet'), findsOneWidget);
    await tester.tap(find.text('Kapasite yetersiz'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Reddet'));
    await tester.pumpAndSettle();

    expect(gateway.rejectCallCount, 1);
    expect(gateway.lastOrderId, 'order-5');
    expect(
        gateway.lastReasonCode, DineInRejectionReasonCode.capacityUnavailable);
    expect(find.text('Sipariş reddedildi.'), findsOneWidget);
  });

  testWidgets(
      '2026-10-29: tapping an order card opens a detail sheet showing its '
      'line items and total', (tester) async {
    await _pumpScreen(
      tester,
      state: AsyncData([
        _buildOrder(id: 'order-6', status: OrderStatus.completed),
      ]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('ORDER-6'));
    await tester.pumpAndSettle();

    expect(find.text('1x Mexifit Bowl'), findsOneWidget);
    expect(find.text('Toplam'), findsOneWidget);
  });

  testWidgets(
      '2026-10-29: the detail sheet\'s own Onayla button also works for a '
      'pendingConfirmation dine-in order', (tester) async {
    final gateway = _FakeDineInOrderResponseGateway();
    await _pumpScreen(
      tester,
      state: AsyncData([
        _buildOrder(
          id: 'order-7',
          status: OrderStatus.pendingConfirmation,
          channel: OrderChannel.dineInQr,
        ),
      ]),
      dineInResponseGateway: gateway,
    );
    await tester.pumpAndSettle();

    // Opens the sheet via the order number (not 'Onayla' — the inline card
    // button already matches that text too, which would make this tap
    // ambiguous).
    await tester.tap(find.text('ORDER-7'));
    await tester.pumpAndSettle();

    // Now exactly two 'Onayla' buttons exist (the card's own, still in the
    // tree underneath, and the sheet's) — tap the last one (the sheet's,
    // painted on top).
    await tester.tap(find.widgetWithText(ElevatedButton, 'Onayla').last);
    await tester.pumpAndSettle();

    expect(gateway.confirmCallCount, 1);
    expect(gateway.lastOrderId, 'order-7');
  });
}
