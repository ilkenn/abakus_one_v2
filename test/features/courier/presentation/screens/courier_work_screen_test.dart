import 'dart:async';

import 'package:abakus_one_v2/features/courier/data/courier_work_repository.dart';
import 'package:abakus_one_v2/features/courier/domain/work/courier_work_models.dart';
import 'package:abakus_one_v2/features/courier/presentation/providers/courier_work_providers.dart';
import 'package:abakus_one_v2/features/courier/presentation/screens/courier_work_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-11-12 (Faz 3b) — "Kurye Ekranım": the courier's own orders with
/// Yola Çıktım / Teslim Ettim / Ara, the pool and own requests for an
/// external courier, and the not-linked state.
class _FakeRepository implements CourierWorkRepository {
  CourierWorkAccount? account;
  final orders = StreamController<List<CourierWorkOrder>>.broadcast();
  List<CourierWorkOrder> latestOrders = const [];
  List<CourierPoolPackage> packages = const [];
  List<CourierOwnPoolRequest> requests = const [];
  List<String>? watchedDistricts;

  void emitOrders(List<CourierWorkOrder> value) {
    latestOrders = value;
    orders.add(value);
  }

  @override
  Stream<CourierWorkAccount?> watchAccount(String uid) => Stream.value(account);

  @override
  Stream<List<CourierWorkOrder>> watchAssignedOrders({
    required String uid,
    required String organizationId,
  }) async* {
    yield latestOrders;
    yield* orders.stream;
  }

  @override
  Stream<List<CourierPoolPackage>> watchPoolPackages({
    required String organizationId,
    required List<String> districtIds,
  }) {
    watchedDistricts = districtIds;
    return Stream.value(packages);
  }

  @override
  Stream<List<CourierOwnPoolRequest>> watchOwnRequests({
    required String uid,
    required String organizationId,
  }) =>
      Stream.value(requests);
}

class _FakeGateway implements CourierWorkGateway {
  final calls = <String>[];
  CourierWorkException? error;

  Future<void> _record(String call) async {
    final e = error;
    if (e != null) throw e;
    calls.add(call);
  }

  @override
  Future<void> markDeparted(String orderId) => _record('departed:$orderId');

  @override
  Future<void> reportDelivered(String orderId, String paymentMethodId) =>
      _record('delivered:$orderId:$paymentMethodId');

  @override
  Future<void> requestPoolOrder(String orderId) => _record('request:$orderId');
}

CourierWorkAccount _account({bool external = false}) => CourierWorkAccount(
      uid: 'uid-1',
      organizationId: 'org-1',
      courierId: 'courier-1',
      displayName: 'Ali',
      isExternal: external,
      serviceDistrictIds: external ? const ['kadikoy', 'uskudar'] : const [],
      isActive: true,
    );

CourierWorkOrder _order(CourierWorkOrderStatus status, {String? phone}) =>
    CourierWorkOrder(
      orderId: 'o1',
      orderNumber: 'DL-0001',
      branchName: 'Moda Şube',
      customerName: 'Ayşe Demir',
      customerPhone: phone,
      neighborhoodName: 'Caferağa',
      addressLine: 'Moda Caddesi No: 12',
      courierNote: 'Zile basmayın',
      amountDueMinorUnits: 45000,
      plannedPaymentMethodId: 'cash',
      reportedPaymentMethodId:
          status == CourierWorkOrderStatus.deliveredAwaitingSettlement
              ? 'multinet'
              : null,
      status: status,
    );

class _Fakes {
  _Fakes(this.repository, this.gateway, this.dialed);
  final _FakeRepository repository;
  final _FakeGateway gateway;
  final List<String> dialed;
}

Future<_Fakes> _pump(WidgetTester tester, _FakeRepository repository) async {
  await tester.binding.setSurfaceSize(const Size(420, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  addTearDown(repository.orders.close);
  final gateway = _FakeGateway();
  final dialed = <String>[];
  await tester.pumpWidget(ProviderScope(
    overrides: [
      courierWorkRepositoryProvider.overrideWithValue(repository),
      courierWorkGatewayProvider.overrideWithValue(gateway),
      courierPhoneDialerProvider.overrideWithValue((phone) async {
        dialed.add(phone);
      }),
    ],
    child: const MaterialApp(home: CourierWorkScreen(uid: 'uid-1')),
  ));
  await tester.pumpAndSettle();
  return _Fakes(repository, gateway, dialed);
}

void main() {
  testWidgets('an account not linked to a courier is explained',
      (tester) async {
    await _pump(tester, _FakeRepository());
    expect(find.byKey(const Key('courierNotLinked')), findsOneWidget);
  });

  testWidgets(
      'a restaurant courier sees only its orders: call, Yola Çıktım, '
      'Teslim Ettim with the paid method', (tester) async {
    final repository = _FakeRepository()
      ..account = _account()
      ..latestOrders = [
        _order(CourierWorkOrderStatus.assigned, phone: '+905321112233')
      ];
    final fakes = await _pump(tester, repository);

    expect(find.byKey(const Key('tabPool')), findsNothing,
        reason: 'restaurant couriers never see the pool');
    expect(find.text('Alış: Moda Şube'), findsOneWidget);
    expect(find.text('Not: Zile basmayın'), findsOneWidget);

    await tester.tap(find.byKey(const Key('callCustomer-o1')));
    await tester.pumpAndSettle();
    expect(fakes.dialed, ['+905321112233']);

    await tester.tap(find.byKey(const Key('departed-o1')));
    await tester.pumpAndSettle();
    expect(fakes.gateway.calls, ['departed:o1']);

    repository.emitOrders(
        [_order(CourierWorkOrderStatus.departed, phone: '+905321112233')]);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('departed-o1')), findsNothing);

    await tester.tap(find.byKey(const Key('delivered-o1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('deliveryMethod-multinet')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmDelivered')));
    await tester.pumpAndSettle();
    expect(fakes.gateway.calls, ['departed:o1', 'delivered:o1:multinet']);

    // A stale copy that still carries personal data — the card must not
    // show any of it once delivered (ADR-085 stage 2, KVKK).
    repository.emitOrders([
      _order(CourierWorkOrderStatus.deliveredAwaitingSettlement,
          phone: '+905321112233')
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Teslim Edildi — Mutabakat Bekliyor'), findsOneWidget);
    expect(find.byKey(const Key('callCustomer-o1')), findsNothing,
        reason: 'KVKK: no phone after delivery');
    expect(find.text('Ayşe Demir'), findsNothing);
    expect(find.textContaining('Moda Caddesi'), findsNothing);
    expect(find.textContaining('Zile basmayın'), findsNothing);
    expect(find.text('Caferağa'), findsOneWidget);
    expect(find.byKey(const Key('courierPiiRemoved-o1')), findsOneWidget);
    expect(find.text('Tahsilat: Multinet'), findsOneWidget);
  });

  testWidgets('a refused action is explained in Turkish', (tester) async {
    final repository = _FakeRepository()
      ..account = _account()
      ..latestOrders = [_order(CourierWorkOrderStatus.assigned)];
    final fakes = await _pump(tester, repository);
    fakes.gateway.error =
        const CourierWorkException('permission-denied', 'not yours');

    await tester.tap(find.byKey(const Key('departed-o1')));
    await tester.pumpAndSettle();
    expect(find.textContaining('yetkiniz yok'), findsOneWidget);
  });

  testWidgets(
      'an external courier sees its districts\' pool, requests a package, '
      'and follows its requests', (tester) async {
    final repository = _FakeRepository()
      ..account = _account(external: true)
      ..packages = const [
        CourierPoolPackage(
          orderId: 'p1',
          orderNumber: 'DL-0002',
          branchName: 'Merkez Şube',
          neighborhoodName: 'Caferağa',
          addressLine: 'Moda Caddesi No: 12',
          amountDueMinorUnits: 30000,
          plannedPaymentMethodId: 'cash',
        ),
      ]
      ..requests = const [
        CourierOwnPoolRequest(
          requestId: 'r0',
          orderId: 'old',
          orderNumber: 'DL-0000',
          neighborhoodName: 'Moda',
          amountDueMinorUnits: 10000,
          status: CourierOwnRequestStatus.rejected,
          rejection: 'otherApproved',
        ),
      ];
    final fakes = await _pump(tester, repository);

    expect(find.byKey(const Key('noCourierOrders')), findsOneWidget);
    await tester.tap(find.byKey(const Key('tabPool')));
    await tester.pumpAndSettle();
    expect(repository.watchedDistricts, ['kadikoy', 'uskudar']);
    expect(find.text('300 TL'), findsOneWidget);
    expect(find.textContaining('Ayşe'), findsNothing);

    await tester.tap(find.byKey(const Key('requestPackage-p1')));
    await tester.pumpAndSettle();
    expect(fakes.gateway.calls, ['request:p1']);
    expect(find.textContaining('talebiniz şubeye iletildi'), findsOneWidget);

    await tester.tap(find.byKey(const Key('tabRequests')));
    await tester.pumpAndSettle();
    expect(find.text('Başka kuryeye verildi'), findsOneWidget);
  });

  testWidgets('a pending request disables Talep Oluştur for that package',
      (tester) async {
    final repository = _FakeRepository()
      ..account = _account(external: true)
      ..packages = const [
        CourierPoolPackage(
          orderId: 'p1',
          orderNumber: 'DL-0002',
          branchName: '',
          neighborhoodName: 'Caferağa',
          addressLine: '',
          amountDueMinorUnits: 30000,
          plannedPaymentMethodId: null,
        ),
      ]
      ..requests = const [
        CourierOwnPoolRequest(
          requestId: 'r1',
          orderId: 'p1',
          orderNumber: 'DL-0002',
          neighborhoodName: 'Caferağa',
          amountDueMinorUnits: 30000,
          status: CourierOwnRequestStatus.pending,
        ),
      ];
    await _pump(tester, repository);
    await tester.tap(find.byKey(const Key('tabPool')));
    await tester.pumpAndSettle();

    expect(find.text('Talep gönderildi'), findsOneWidget);
    expect(
      tester
          .widget<ButtonStyleButton>(find.byKey(const Key('requestPackage-p1')))
          .onPressed,
      isNull,
    );
  });

  test('models parse the server documents', () {
    final order = CourierWorkOrder.fromFirestore('o1', {
      'orderNumber': 'DL-1',
      'status': 'deliveredAwaitingSettlement',
      'amountDueMinorUnits': 45000,
      'reportedPaymentMethodId': 'pluxee',
    });
    expect(order.status, CourierWorkOrderStatus.deliveredAwaitingSettlement);
    expect(order.customerPhone, isNull);
    final account = CourierWorkAccount.fromFirestore('u', {
      'organizationId': 'org-1',
      'courierId': 'c1',
      'type': 'pool',
      'serviceDistrictIds': ['kadikoy'],
      'status': 'active',
    });
    expect(account.isExternal, isTrue);
    expect(formatCourierAmount(45050), '450,50 TL');
  });
}
