import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abakus_one_v2/features/pos/data/cash_register_gateway.dart';
import 'package:abakus_one_v2/features/pos/data/courier_settlement_gateway.dart';
import 'package:abakus_one_v2/features/pos/data/kitchen_action_gateway.dart';
import 'package:abakus_one_v2/features/pos/data/pos_action_gateway.dart';
import 'package:abakus_one_v2/features/pos/domain/cash/z_report_content.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/kds_dependencies_provider.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/pos_workspace_providers.dart';
import 'package:abakus_one_v2/features/pos/presentation/screens/pos_courier_settlement_screen.dart';

/// 2026-11-11 (Faz 2b) — "Kurye Hesap Kapat".
class _FakeSettlementGateway implements CourierSettlementGateway {
  List<CourierSettlementOrder> orders = [];
  int previewCalls = 0;
  int settleCalls = 0;
  List<CourierSettlementDelivery>? lastDeliveries;
  int? lastReceived;
  String? lastReason;
  String? lastCashSessionId;
  CourierSettlementException? error;

  @override
  Future<CourierSettlementPreview> preview({
    required PosDeviceContext ctx,
    required String courierId,
  }) async {
    previewCalls += 1;
    return CourierSettlementPreview(
        courierId: courierId, courierName: 'Mehmet', orders: orders);
  }

  @override
  Future<CourierSettlementResult> settle({
    required PosDeviceContext ctx,
    required String courierId,
    required String cashSessionId,
    required String settlementKey,
    required List<CourierSettlementDelivery> deliveries,
    required int receivedCashMinorUnits,
    String? differenceReason,
  }) async {
    final e = error;
    if (e != null) throw e;
    settleCalls += 1;
    lastDeliveries = deliveries;
    lastReceived = receivedCashMinorUnits;
    lastReason = differenceReason;
    lastCashSessionId = cashSessionId;
    return const CourierSettlementResult(
      settlementId: 'cs-1',
      duplicate: false,
      differenceMinorUnits: 0,
      totalCollectedMinorUnits: 40000,
    );
  }
}

class _FakeCashGateway implements CashRegisterGateway {
  _FakeCashGateway({this.active = true});
  final bool active;

  @override
  Future<List<CashDrawerSummary>> listCashDrawers({
    required PosDeviceContext ctx,
  }) async =>
      [
        CashDrawerSummary(
          drawerId: 'drawer-1',
          name: 'Ana Kasa',
          isActive: true,
          openSession: active
              ? const CashOpenSessionSummary(
                  sessionId: 'session-cash-1', status: 'active')
              : null,
        ),
      ];

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FakeKitchenGateway implements KitchenActionGateway {
  final cancelled = <(String, String)>[];

  @override
  Future<void> cancelOrder({
    required String orderId,
    required String channel,
    required DineInCancellationReasonCode reasonCode,
    String? reasonMessage,
  }) async {
    cancelled.add((orderId, channel));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

const _ctx = PosDeviceContext(
  organizationId: 'org-1',
  branchId: 'branch-1',
  deviceId: 'device-1',
  deviceSessionId: 'session-1',
);

CourierSettlementOrder _order(String id, int amount, String planned) =>
    CourierSettlementOrder(
      orderId: id,
      orderNumber: 'DL-$id',
      status: 'outForDelivery',
      customerName: 'Ayşe Demir',
      addressSummary: 'Caferağa, Moda Caddesi',
      amountDueMinorUnits: amount,
      plannedPaymentMethodId: planned,
    );

class _Fakes {
  _Fakes(this.settlement, this.kitchen);
  final _FakeSettlementGateway settlement;
  final _FakeKitchenGateway kitchen;
}

Future<_Fakes> _pump(WidgetTester tester,
    {bool cashSessionActive = true,
    List<CourierSettlementOrder>? orders}) async {
  await tester.binding.setSurfaceSize(const Size(1200, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final settlement = _FakeSettlementGateway()
    ..orders = orders ??
        [
          _order('a', 20000, 'cash'),
          _order('b', 10000, 'credit_card'),
          _order('c', 10000, 'cash'),
        ];
  final kitchen = _FakeKitchenGateway();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        courierSettlementGatewayProvider.overrideWithValue(settlement),
        cashRegisterGatewayProvider
            .overrideWithValue(_FakeCashGateway(active: cashSessionActive)),
        kitchenActionGatewayProvider.overrideWithValue(kitchen),
      ],
      child: const MaterialApp(
        home: PosCourierSettlementScreen(ctx: _ctx, courierId: 'courier-1'),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _Fakes(settlement, kitchen);
}

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

Future<void> _settle(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('settleCourierButton')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'expected cash is the cash-planned orders; every order is sent with its '
      'method and the received cash', (tester) async {
    final fakes = await _pump(tester);

    expect(_text(tester, 'expectedCash'), '300 TL');
    await _settle(tester);

    expect(fakes.settlement.settleCalls, 1);
    expect(fakes.settlement.lastCashSessionId, 'session-cash-1');
    expect(fakes.settlement.lastReceived, 30000);
    expect(fakes.settlement.lastReason, isNull);
    expect(
      fakes.settlement.lastDeliveries!
          .map((d) => (d.orderId, d.paymentMethodId)),
      [('a', 'cash'), ('b', 'credit_card'), ('c', 'cash')],
    );
  });

  testWidgets(
      'the customer paid Multinet instead of cash: expected cash drops, the '
      'change is flagged, a slip number can be entered', (tester) async {
    final fakes = await _pump(tester);

    await tester.tap(find.byKey(const Key('method-c-multinet')));
    await tester.pumpAndSettle();

    expect(_text(tester, 'expectedCash'), '200 TL');
    expect(find.textContaining('planlanan yöntemden farklı'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('slip-c')), '778899');
    await _settle(tester);

    final c =
        fakes.settlement.lastDeliveries!.firstWhere((d) => d.orderId == 'c');
    expect(c.paymentMethodId, 'multinet');
    expect(c.slipNumber, '778899');
    expect(fakes.settlement.lastReceived, 20000);
  });

  testWidgets(
      'a cash difference needs a reason; the server refusal for staff is '
      'explained', (tester) async {
    final fakes = await _pump(tester);

    await tester.enterText(find.byKey(const Key('receivedCashField')), '290');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('differenceNotice')), findsOneWidget);
    expect(find.textContaining('Kurye Farkı: -10 TL'), findsOneWidget);

    await _settle(tester);
    expect(fakes.settlement.settleCalls, 0);
    expect(find.text('Fark var: fark açıklaması zorunludur.'), findsOneWidget);

    fakes.settlement.error = const CourierSettlementException(
        'permission-denied',
        'A cash difference can only be closed by a manager.');
    await tester.enterText(
        find.byKey(const Key('differenceReasonField')), '10 TL eksik');
    await _settle(tester);
    expect(find.textContaining('yalnızca yönetici'), findsWidgets);

    fakes.settlement.error = null;
    await _settle(tester);
    expect(fakes.settlement.lastReceived, 29000);
    expect(fakes.settlement.lastReason, '10 TL eksik');
  });

  testWidgets('no active cash session: explained and closing is disabled',
      (tester) async {
    await _pump(tester, cashSessionActive: false);

    expect(find.byKey(const Key('noCashSessionNotice')), findsOneWidget);
    expect(
        tester
            .widget<ElevatedButton>(
                find.byKey(const Key('settleCourierButton')))
            .onPressed,
        isNull);
  });

  testWidgets(
      'Teslim Edilemedi goes through the staff cancellation with a reason, '
      'then the list reloads', (tester) async {
    final fakes = await _pump(tester);
    final before = fakes.settlement.previewCalls;

    await tester.tap(find.byKey(const Key('undelivered-b')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Siparişi İptal Et').last);
    await tester.pumpAndSettle();

    expect(fakes.kitchen.cancelled, [('b', 'delivery')]);
    expect(fakes.settlement.previewCalls, before + 1);
  });

  testWidgets('a courier with no open orders can still be marked returned',
      (tester) async {
    final fakes = await _pump(tester, orders: const []);

    expect(find.textContaining('açık sipariş yok'), findsOneWidget);
    await _settle(tester);
    expect(fakes.settlement.settleCalls, 1);
    expect(fakes.settlement.lastDeliveries, isEmpty);
    expect(fakes.settlement.lastReceived, 0);
  });

  testWidgets(
      'Faz 3a: the method the courier reported is preselected and labelled; '
      'the cashier can still change it', (tester) async {
    final fakes = await _pump(tester, orders: const [
      CourierSettlementOrder(
        orderId: 'd',
        orderNumber: 'DL-d',
        status: 'outForDelivery',
        customerName: 'Ayşe Demir',
        addressSummary: 'Caferağa',
        amountDueMinorUnits: 20000,
        plannedPaymentMethodId: 'cash',
        courierReportedPaymentMethodId: 'multinet',
        courierReportedDelivered: true,
      ),
    ]);

    expect(_text(tester, 'courierReported-d'), 'Kurye bildirdi: Multinet');
    expect(_text(tester, 'expectedCash'), '0 TL');

    await tester.tap(find.byKey(const Key('method-d-cash')));
    await tester.pumpAndSettle();
    expect(_text(tester, 'courierReported-d'),
        'Kurye bildirdi: Multinet — kasiyer değiştirdi');
    await _settle(tester);
    expect(fakes.settlement.lastDeliveries!.single.paymentMethodId, 'cash');
  });

  test('Z report: Paket Servis Tahsilatı and Kurye Farkı lines', () {
    final summary = DailyRevenueSummary.fromWire({
      'sessionId': 's',
      'currencyCode': 'TRY',
      'cashMinorUnits': 0,
      'cardMinorUnits': 0,
      'otherMinorUnits': 0,
      'totalMinorUnits': 0,
      'deliveryCollectionMinorUnits': 40000,
      'courierDifferenceMinorUnits': -1000,
    });
    expect(summary.deliveryCollectionMinorUnits, 40000);
    expect(summary.courierDifferenceMinorUnits, -1000);

    final text = ZReportContent(
      branchDisplayName: 'Merkez',
      sessionId: 's',
      businessDate: '2026-11-11',
      openedAt: DateTime(2026, 11, 11, 9),
      closedAt: DateTime(2026, 11, 11, 23),
      currencySymbol: 'TL',
      openingFloatMinorUnits: 0,
      cashMinorUnits: 30000,
      cardMinorUnits: 10000,
      otherMinorUnits: 0,
      deliveryCollectionMinorUnits: 40000,
      courierDifferenceMinorUnits: -1000,
      totalMinorUnits: 40000,
      expectedAmountMinorUnits: 29000,
      actualAmountMinorUnits: 29000,
      varianceType: 'exact',
      varianceAmountMinorUnits: 0,
    ).toReceiptText();
    expect(text, contains('Paket Servis Tahsilatı: TL400.00'));
    expect(text, contains('Kurye Farkı: TL-10.00'));
  });
}
