import 'dart:async';
import 'dart:typed_data';

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
  Future<void> reportDelivered(
    String orderId,
    String? paymentMethodId, {
    Uint8List? slipPhoto,
  }) {
    lastSlip = slipPhoto;
    return _record('delivered:$orderId:$paymentMethodId');
  }

  Uint8List? lastSlip;

  @override
  Future<void> requestCancellation(String orderId, String reason) {
    lastCancelReason = reason;
    return _record('cancel:$orderId');
  }

  String? lastCancelReason;

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

CourierWorkOrder _order(CourierWorkOrderStatus status,
        {String? phone, String plannedMethod = 'cash'}) =>
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
      plannedPaymentMethodId: plannedMethod,
      reportedPaymentMethodId:
          status == CourierWorkOrderStatus.deliveredAwaitingSettlement
              ? 'multinet'
              : null,
      status: status,
    );

/// A 1×1 transparent PNG — a decodable "slip photo" for the camera fake.
final _slipPng = Uint8List.fromList(const [
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

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
      courierUriLauncherProvider.overrideWithValue((uri) async {
        dialed.add(uri.toString());
      }),
      // ADR-085 stage 6B — the camera returns a tiny real PNG.
      courierSlipCameraProvider.overrideWithValue(() async => _slipPng),
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
    expect(fakes.dialed, ['tel:+905321112233']);
    expect(find.text('Müşteriyi Ara'), findsOneWidget);

    // ADR-085 stage 4 — "Konuma Git" by the written address (no pin).
    await tester.tap(find.byKey(const Key('navigate-o1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('navigateWith-Yandex Haritalar')));
    await tester.pumpAndSettle();
    expect(
        fakes.dialed.last, startsWith('https://yandex.com.tr/harita/?text='));

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
    // ADR-085 stage 6B — cash → Multinet: flagged, and a slip photo first.
    expect(find.byKey(const Key('deliveryMethodChanged')), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('confirmDelivered')))
          .onPressed,
      isNull,
      reason: 'no "Teslim Ettim" without the slip photo',
    );
    await tester.tap(find.byKey(const Key('slipCapture')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('slipPreview')), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirmDelivered')));
    await tester.pumpAndSettle();
    expect(fakes.gateway.calls, ['departed:o1', 'delivered:o1:multinet']);
    expect(fakes.gateway.lastSlip, _slipPng);

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

  testWidgets(
      'a card-at-the-door order asks "POS Cihazı Kontrolü" before departing; '
      'a cash order does not', (tester) async {
    final repository = _FakeRepository()
      ..account = _account()
      ..latestOrders = [
        _order(CourierWorkOrderStatus.assigned, plannedMethod: 'credit_card')
      ];
    final fakes = await _pump(tester, repository);

    await tester.tap(find.byKey(const Key('departed-o1')));
    await tester.pumpAndSettle();
    expect(find.text('POS Cihazı Kontrolü'), findsOneWidget);
    expect(find.textContaining('KAPIDA POS ile ödenecektir (POS)'),
        findsOneWidget);
    expect(
      tester
          .widget<ElevatedButton>(
              find.byKey(const Key('posDeviceConfirmDepart')))
          .onPressed,
      isNull,
      reason: 'not before the box is ticked',
    );
    await tester.tap(find.byKey(const Key('posDeviceCancel')));
    await tester.pumpAndSettle();
    expect(fakes.gateway.calls, isEmpty, reason: 'no departure without POS');

    await tester.tap(find.byKey(const Key('departed-o1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('posDeviceTaken')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('posDeviceConfirmDepart')));
    await tester.pumpAndSettle();
    expect(fakes.gateway.calls, ['departed:o1']);

    // A meal card is swiped on the POS too.
    expect(courierNeedsPosDevice('multinet'), isTrue);
    expect(courierNeedsPosDevice('cash'), isFalse);
    expect(courierNeedsPosDevice(null), isFalse);
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

  testWidgets(
      'ADR-085 stage 6B: cash needs no photo; an order paid online asks no '
      'method; a cancellation is only a request with a reason', (tester) async {
    final repository = _FakeRepository()
      ..account = _account()
      ..latestOrders = [_order(CourierWorkOrderStatus.departed)];
    final fakes = await _pump(tester, repository);

    await tester.tap(find.byKey(const Key('delivered-o1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('slipCapture')), findsNothing);
    expect(
        find.byKey(const Key('deliveryMethod-metropol_card')), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirmDelivered')));
    await tester.pumpAndSettle();
    expect(fakes.gateway.calls, ['delivered:o1:cash']);
    expect(fakes.gateway.lastSlip, isNull);

    repository.emitOrders([
      _order(CourierWorkOrderStatus.departed, plannedMethod: 'online_card'),
    ]);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delivered-o1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('deliveryPaidOnline')), findsOneWidget);
    expect(find.byKey(const Key('deliveryMethod-cash')), findsNothing);
    await tester.tap(find.byKey(const Key('confirmDelivered')));
    await tester.pumpAndSettle();
    expect(fakes.gateway.calls.last, 'delivered:o1:null');

    await tester.tap(find.byKey(const Key('requestCancel-o1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('cancelReason')), 'yok');
    await tester.tap(find.byKey(const Key('cancelReasonSend')));
    await tester.pumpAndSettle();
    expect(find.text('En az 5 karakterlik bir gerekçe yazın'), findsOneWidget);
    await tester.enterText(
        find.byKey(const Key('cancelReason')), 'Müşteri adreste yok');
    await tester.tap(find.byKey(const Key('cancelReasonSend')));
    await tester.pumpAndSettle();
    expect(fakes.gateway.calls.last, 'cancel:o1');
    expect(fakes.gateway.lastCancelReason, 'Müşteri adreste yok');
    expect(find.textContaining('iptal talebiniz müdür onayına gönderildi'),
        findsOneWidget);

    repository.emitOrders([
      CourierWorkOrder.fromFirestore('o1', const {
        'orderNumber': 'DL-0001',
        'status': 'departed',
        'cancellationRequestStatus': 'pending',
      }),
    ]);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cancelPending-o1')), findsOneWidget);
    expect(find.byKey(const Key('requestCancel-o1')), findsNothing);
  });

  testWidgets(
      'ADR-085 stage 6C-1: the cash-limit banner, a red late badge, and no '
      'Yola Çıktım before the counter hand-over', (tester) async {
    final repository = _FakeRepository()
      ..account = CourierWorkAccount.fromFirestore('uid-1', const {
        'organizationId': 'org-1',
        'courierId': 'courier-1',
        'type': 'pool',
        'status': 'active',
        'carriedCashMinorUnits': 320000,
        'cashLimitMinorUnits': 300000,
        'cashLimitExceeded': true,
      })
      ..latestOrders = [
        CourierWorkOrder.fromFirestore('o1', {
          'orderNumber': 'DL-0001',
          'status': 'departed',
          'departedAt': DateTime.now().subtract(const Duration(minutes: 40)),
          'lateDeliveryMinutes': 35,
        }),
        CourierWorkOrder.fromFirestore('o2', const {
          'orderNumber': 'DL-0002',
          'status': 'assigned',
          'handedOver': false,
        }),
      ];
    await _pump(tester, repository);

    expect(find.byKey(const Key('courierCashLimitBanner')), findsOneWidget);
    expect(find.textContaining('Nakit limitiniz doldu'), findsOneWidget);
    expect(find.byKey(const Key('courierLate-o1')), findsOneWidget);
    expect(find.textContaining('GECİKTİ · 40 dk'), findsOneWidget);
    expect(find.byKey(const Key('courierLate-o2')), findsNothing);
    expect(find.byKey(const Key('courierNotHandedOver-o2')), findsOneWidget);
    expect(find.byKey(const Key('departed-o2')), findsNothing);
  });
}
