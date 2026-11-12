import 'dart:async';

import 'package:abakus_one_v2/features/orders/data/order_firestore_mapper.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_channel.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_line.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_number.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_status.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_timestamps.dart';
import 'package:abakus_one_v2/features/orders/domain/pricing/price_calculator.dart';
import 'package:abakus_one_v2/features/orders/domain/pricing/tax_policy.dart';
import 'package:abakus_one_v2/features/pos/data/courier_pool_gateway.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/courier_dispatch_dependencies_provider.dart';
import 'package:abakus_one_v2/features/pos/presentation/screens/delivery_order_dispatch_screen.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-11-12 (Faz 3a) — the dispatch board's external-courier pool:
/// "Havuza Gönder" / "Havuzdan Geri Al", the live request panel (badge +
/// alert sound on a new request) with approve/reject, and the delivery
/// progress labels.
const _branchId = 'branch-1';

class _FakePoolGateway implements CourierPoolGateway {
  final calls = <String>[];
  CourierPoolException? error;

  Future<void> _record(String call) async {
    final e = error;
    if (e != null) throw e;
    calls.add(call);
  }

  @override
  Future<void> publish({required String orderId}) =>
      _record('publish:$orderId');

  @override
  Future<void> withdraw({required String orderId}) =>
      _record('withdraw:$orderId');

  @override
  Future<void> respond({required String requestId, required bool approve}) =>
      _record('${approve ? 'approve' : 'reject'}:$requestId');
}

class _FakeRequestRepository implements CourierPoolRequestRepository {
  final controller = StreamController<List<CourierPoolRequest>>.broadcast();
  List<CourierPoolRequest> latest = const [];

  void emit(List<CourierPoolRequest> requests) {
    latest = requests;
    controller.add(requests);
  }

  @override
  Stream<List<CourierPoolRequest>> watchPending({
    required String organizationId,
    required String branchId,
  }) async* {
    yield latest;
    yield* controller.stream;
  }
}

CourierPoolRequest _request(String id, String courier) => CourierPoolRequest(
      requestId: id,
      orderId: 'order-1',
      orderNumber: 'DL-ABCD1234',
      courierId: 'c-$courier',
      courierName: courier,
      neighborhoodName: 'Caferağa',
      amountDueMinorUnits: 45000,
    );

Order _order({
  OrderStatus status = OrderStatus.ready,
  String? poolStatus,
  bool departed = false,
  bool delivered = false,
  String? assignedCourierId,
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
    timestamps: OrderTimestamps(created: DateTime(2026, 11, 12)),
    contactFirstName: 'Ayşe',
    contactLastName: 'Demir',
    poolStatus: poolStatus,
    courierDeparted: departed,
    courierReportedDelivered: delivered,
    assignedCourierId: assignedCourierId,
  );
}

class _Fakes {
  _Fakes(this.pool, this.requests);
  final _FakePoolGateway pool;
  final _FakeRequestRepository requests;
}

Future<_Fakes> _pump(WidgetTester tester, Order order) async {
  await tester.binding.setSurfaceSize(const Size(1200, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final pool = _FakePoolGateway();
  final requests = _FakeRequestRepository();
  addTearDown(requests.controller.close);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        assignableDeliveryOrdersProvider(_branchId)
            .overrideWith((ref) => Stream.value([order])),
        allCouriersForBranchProvider(_branchId)
            .overrideWith((ref) => Stream.value(const [])),
        courierPoolGatewayProvider.overrideWithValue(pool),
        courierPoolRequestRepositoryProvider.overrideWithValue(requests),
      ],
      child: const MaterialApp(
        home: DeliveryOrderDispatchScreen(
            organizationId: 'org-1', branchId: _branchId),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _Fakes(pool, requests);
}

void main() {
  testWidgets('an order still in the kitchen can be sent to the pool',
      (tester) async {
    final fakes = await _pump(tester, _order(status: OrderStatus.preparing));

    expect(find.text('Mutfakta hazırlanıyor'), findsOneWidget);
    expect(find.text('Havuza Gönder'), findsOneWidget);
    await tester.tap(find.byKey(const Key('togglePool-order-1')));
    await tester.pumpAndSettle();

    expect(fakes.pool.calls, ['publish:order-1']);
    expect(find.text('DL-ABCD1234 dış kurye havuzuna gönderildi.'),
        findsOneWidget);
  });

  testWidgets(
      'a pooled order shows its request count and can be taken back; '
      'an unresolved region is explained', (tester) async {
    final fakes = await _pump(tester, _order(poolStatus: 'published'));
    expect(find.text('Havuzda · talep bekleniyor'), findsOneWidget);

    fakes.requests.emit([_request('r1', 'Ali'), _request('r2', 'Veli')]);
    await tester.pumpAndSettle();
    expect(find.text('Havuzda · 2 kurye talebi'), findsOneWidget);

    await tester.tap(find.text('Havuzdan Geri Al'));
    await tester.pumpAndSettle();
    expect(fakes.pool.calls, ['withdraw:order-1']);

    fakes.pool.error = const CourierPoolException('failed-precondition',
        'The delivery region (district) of this order could not be determined.');
    await tester.tap(find.text('Havuzdan Geri Al'));
    await tester.pumpAndSettle();
    expect(find.textContaining('teslimat bölgesi (ilçe) belirlenemedi'),
        findsOneWidget);
  });

  testWidgets(
      'a new request rings once and shows on the badge; the panel approves '
      'and rejects', (tester) async {
    final sounds = <Object?>[];
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemSound.play') sounds.add(call.arguments);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    final fakes = await _pump(tester, _order(poolStatus: 'published'));
    expect(sounds, isEmpty, reason: 'no sound for what was already there');

    fakes.requests.emit([_request('r1', 'Ali')]);
    await tester.pumpAndSettle();
    expect(sounds, hasLength(1));
    expect(
        find.descendant(
            of: find.byKey(const Key('openPoolRequestsButton')),
            matching: find.text('1')),
        findsOneWidget);

    fakes.requests.emit([_request('r1', 'Ali')]);
    await tester.pumpAndSettle();
    expect(sounds, hasLength(1), reason: 'same request, no second ring');

    fakes.requests.emit([_request('r1', 'Ali'), _request('r2', 'Veli')]);
    await tester.pumpAndSettle();
    expect(sounds, hasLength(2));

    await tester.tap(find.byKey(const Key('openPoolRequestsButton')));
    await tester.pumpAndSettle();
    expect(find.text('Ali → DL-ABCD1234'), findsOneWidget);
    expect(find.text('Caferağa · 450 TL'), findsWidgets);

    await tester.tap(find.byKey(const Key('approvePoolRequest-r2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('rejectPoolRequest-r1')));
    await tester.pumpAndSettle();
    expect(fakes.pool.calls, ['approve:r2', 'reject:r1']);

    fakes.pool.error =
        const CourierPoolException('permission-denied', 'denied');
    await tester.tap(find.byKey(const Key('approvePoolRequest-r1')));
    await tester.pumpAndSettle();
    expect(
        find.text('Kurye taleplerini onaylama yetkiniz yok.'), findsOneWidget);
  });

  testWidgets(
      'courier progress: on the road, then Teslim Edildi — Mutabakat '
      'Bekliyor; no pool button once a courier holds it', (tester) async {
    await _pump(
        tester,
        _order(
            status: OrderStatus.outForDelivery,
            assignedCourierId: 'c-1',
            departed: true,
            delivered: true));
    expect(find.text('Teslim Edildi — Mutabakat Bekliyor'), findsOneWidget);
    expect(find.byKey(const Key('togglePool-order-1')), findsNothing);
  });

  test('the order mapper reads the server-written pool and courier fields', () {
    final data =
        OrderFirestoreMapper.toFirestore(_order(), organizationId: 'org-1')
          ..addAll({
            'poolStatus': 'published',
            'departedAt': '2026-11-12T10:00:00Z',
            'courierReportedDeliveredAt': '2026-11-12T10:30:00Z',
            'courierReportedPaymentMethodId': 'multinet',
          });
    final order = OrderFirestoreMapper.fromFirestore(data);
    expect(order.isInDeliveryPool, isTrue);
    expect(order.courierDeparted, isTrue);
    expect(order.courierReportedDelivered, isTrue);
    expect(order.courierReportedPaymentMethodId, 'multinet');
    expect(
        OrderFirestoreMapper.fromFirestore(OrderFirestoreMapper.toFirestore(
                _order(),
                organizationId: 'org-1'))
            .courierReportedDelivered,
        isFalse);
  });
}
