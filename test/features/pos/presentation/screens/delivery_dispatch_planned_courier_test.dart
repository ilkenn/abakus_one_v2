import 'package:abakus_one_v2/features/courier/data/courier_dispatch_gateway.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_channel.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_line.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_number.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_status.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_timestamps.dart';
import 'package:abakus_one_v2/features/orders/domain/pricing/price_calculator.dart';
import 'package:abakus_one_v2/features/orders/domain/pricing/tax_policy.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/courier_dispatch_dependencies_provider.dart';
import 'package:abakus_one_v2/features/pos/presentation/screens/delivery_order_dispatch_screen.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:abakus_one_v2/shared/models/courier_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-11-11 (Faz 2) — the dispatch board shows a staff-opened order's
/// courier note and planned courier, assigns the planned courier with one
/// tap (never automatically) and offers a courier-slip reprint.
const _branchId = 'branch-1';

class _FakeDispatchGateway implements CourierDispatchGateway {
  final assigned = <(String, String)>[];
  bool? lastPackingVerified;
  final handedOver = <String>[];

  @override
  Future<void> confirmPackageHandover({required String orderId}) async {
    handedOver.add(orderId);
  }

  CourierDispatchException? error;

  @override
  Future<CourierAssignmentResult> assignCourierToOrder({
    required String orderId,
    required String courierId,
    bool packingVerified = false,
  }) async {
    final e = error;
    if (e != null) throw e;
    lastPackingVerified = packingVerified;
    assigned.add((orderId, courierId));
    return CourierAssignmentResult(
      orderId: orderId,
      courierId: courierId,
      trackingToken: 'token',
      status: 'outForDelivery',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Order _order({
  String? plannedCourierId,
  String? assignedCourierId,
  OrderStatus status = OrderStatus.ready,
  CourierType? courierType,
  bool packingVerified = false,
}) {
  final line = OrderLine.create(
    productId: 'p1',
    productName: 'Test',
    quantity: 1,
    unitPrice: Money.fromWhole(100, Currency.tryLira),
    taxRate: TaxPolicy.defaultRate,
  );
  return Order(
    id: OrderId('order-1'),
    orderNumber: OrderNumber('DL-ABCD1234'),
    status: status,
    channel: OrderChannel.delivery,
    branchId: _branchId,
    restaurantId: 'restaurant-1',
    lines: [line],
    pricing:
        PriceCalculator.calculate(lines: [line], currency: Currency.tryLira),
    timestamps: OrderTimestamps(created: DateTime(2026, 11, 11)),
    contactFirstName: 'Ayşe',
    contactLastName: 'Demir',
    customerNote: 'Zile basmayın',
    plannedCourierId: plannedCourierId,
    plannedCourierName: plannedCourierId == null ? null : 'Mehmet',
    assignedCourierId: assignedCourierId,
    courierType: courierType,
    packingVerified: packingVerified,
  );
}

Future<_FakeDispatchGateway> _pump(WidgetTester tester, Order order) async {
  await tester.binding.setSurfaceSize(const Size(1200, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final gateway = _FakeDispatchGateway();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        assignableDeliveryOrdersProvider(
                (organizationId: 'org-1', branchId: _branchId))
            .overrideWith((ref) => Stream.value([order])),
        allCouriersForBranchProvider(
                (organizationId: 'org-1', branchId: _branchId))
            .overrideWith((ref) => Stream.value(const [])),
        courierDispatchGatewayProvider.overrideWithValue(gateway),
      ],
      child: const MaterialApp(
        home: DeliveryOrderDispatchScreen(
            organizationId: 'org-1', branchId: _branchId),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return gateway;
}

void main() {
  testWidgets(
      'shows the courier note and the planned courier; one tap assigns them',
      (tester) async {
    final gateway = await _pump(tester, _order(plannedCourierId: 'courier-2'));

    expect(find.text('Kurye Notu: Zile basmayın'), findsOneWidget);
    expect(find.text('Planlanan kurye: Mehmet'), findsOneWidget);
    expect(gateway.assigned, isEmpty, reason: 'never assigned automatically');

    await tester.tap(find.byKey(const Key('assignPlanned-order-1')));
    await tester.pumpAndSettle();
    // ADR-085 stage 6C-1 — "Eksiksiz Hazırlandı" first; Vazgeç assigns nothing.
    expect(find.byKey(const Key('packingCheckDialog')), findsOneWidget);
    expect(
      tester
          .widget<ElevatedButton>(find.byKey(const Key('packingConfirm')))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const Key('packingCancel')));
    await tester.pumpAndSettle();
    expect(gateway.assigned, isEmpty);

    await tester.tap(find.byKey(const Key('assignPlanned-order-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('packingChecked')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('packingConfirm')));
    await tester.pumpAndSettle();

    expect(gateway.assigned, [('order-1', 'courier-2')]);
    expect(gateway.lastPackingVerified, isTrue);
    expect(find.text('DL-ABCD1234 Mehmet atandı.'), findsOneWidget);
  });

  testWidgets('an order that is not ready yet gets a plain Turkish message',
      (tester) async {
    final gateway = await _pump(tester, _order(plannedCourierId: 'courier-2'));
    gateway.error = const CourierDispatchException(
        'failed-precondition', 'Order is not ready.');

    await tester.tap(find.byKey(const Key('assignPlanned-order-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('packingChecked')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('packingConfirm')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Sipariş henüz hazır değil'), findsOneWidget);
  });

  testWidgets(
      'no planned-courier button without a plan or once a courier is assigned; '
      'the slip reprint is always offered', (tester) async {
    await _pump(tester, _order());
    expect(find.byKey(const Key('assignPlanned-order-1')), findsNothing);
    expect(find.byKey(const Key('reprintSlip-order-1')), findsOneWidget);
  });

  testWidgets('an already-assigned order shows no planned-courier button',
      (tester) async {
    await _pump(tester,
        _order(plannedCourierId: 'courier-2', assignedCourierId: 'courier-1'));
    expect(find.byKey(const Key('assignPlanned-order-1')), findsNothing);
  });

  testWidgets(
      'ADR-085 stage 6C-1: a pool courier collecting at the counter gets '
      '"Teslim Et" after the packing check', (tester) async {
    final gateway = await _pump(
        tester,
        _order(
          assignedCourierId: 'pool-1',
          status: OrderStatus.outForDelivery,
          courierType: CourierType.pool,
        ));
    await tester.tap(find.byKey(const Key('handOver-order-1')));
    await tester.pumpAndSettle();
    expect(find.text('1 × Test'), findsOneWidget, reason: 'the ticket lines');
    await tester.tap(find.byKey(const Key('packingChecked')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('packingConfirm')));
    await tester.pumpAndSettle();
    expect(gateway.handedOver, ['order-1']);
    expect(find.text('DL-ABCD1234 kuryeye teslim edildi.'), findsOneWidget);
  });

  testWidgets('no "Teslim Et" once handed over, nor for a restaurant courier',
      (tester) async {
    await _pump(
        tester,
        _order(
          assignedCourierId: 'pool-1',
          status: OrderStatus.outForDelivery,
          courierType: CourierType.pool,
          packingVerified: true,
        ));
    expect(find.byKey(const Key('handOver-order-1')), findsNothing);
  });
}
