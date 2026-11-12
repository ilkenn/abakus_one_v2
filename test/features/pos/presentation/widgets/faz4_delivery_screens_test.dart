import 'package:abakus_one_v2/features/pos/data/delivery_operations_gateway.dart';
import 'package:abakus_one_v2/features/pos/domain/delivery/courier_delivery_report.dart';
import 'package:abakus_one_v2/features/pos/domain/delivery/delivery_zone.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/courier_dispatch_dependencies_provider.dart';
import 'package:abakus_one_v2/features/pos/presentation/screens/courier_delivery_report_screen.dart';
import 'package:abakus_one_v2/features/pos/presentation/widgets/delivery_zones_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-11-12 — Faz 4: "Teslimat Bölgeleri" dialog and "Kurye & Paket
/// Raporu" screen against a fake gateway.
class _FakeGateway implements DeliveryOperationsGateway {
  List<DeliveryZone> zones = [];
  DeliveryOperationsException? upsertError;
  final List<Map<String, Object?>> upserts = [];
  CourierDeliveryReport? report;
  DeliveryOperationsException? reportError;
  final List<(DateTime, DateTime)> reportRanges = [];

  @override
  Future<BranchDeliveryZones> listZones({
    required String organizationId,
    required String branchId,
  }) async =>
      BranchDeliveryZones(defaultDeliveryDistrictId: 'kadikoy', zones: zones);

  @override
  Future<DeliveryZone> upsertZone({
    required String organizationId,
    required String branchId,
    required String neighborhoodName,
    String districtName = '',
    required int minimumOrderMinorUnits,
    int? estimatedDeliveryMinutes,
    bool enabled = true,
  }) async {
    final e = upsertError;
    if (e != null) throw e;
    upserts.add({
      'neighborhoodName': neighborhoodName,
      'districtName': districtName,
      'minimumOrderMinorUnits': minimumOrderMinorUnits,
      'estimatedDeliveryMinutes': estimatedDeliveryMinutes,
      'enabled': enabled,
    });
    final zone = DeliveryZone(
      id: 'zone-${zones.length + 1}',
      districtId: districtName.isEmpty ? 'kadikoy' : districtName,
      neighborhoodId: neighborhoodName.toLowerCase(),
      neighborhoodName: neighborhoodName,
      minimumOrderMinorUnits: minimumOrderMinorUnits,
      estimatedDeliveryMinutes: estimatedDeliveryMinutes,
      enabled: enabled,
    );
    zones = [...zones, zone];
    return zone;
  }

  @override
  Future<CourierDeliveryReport> courierReport({
    required String organizationId,
    required String branchId,
    required DateTime from,
    required DateTime to,
  }) async {
    reportRanges.add((from, to));
    final e = reportError;
    if (e != null) throw e;
    return report!;
  }
}

CourierReportAggregate _aggregate({
  int packages = 0,
  int collected = 0,
  int difference = 0,
  List<PaymentMethodTotal> methods = const [],
}) =>
    CourierReportAggregate(
      packageCount: packages,
      collectedMinorUnits: collected,
      averagePreparationMinutes: packages == 0 ? null : 15,
      averageDeliveryMinutes: packages == 0 ? null : 32.5,
      cashDifferenceMinorUnits: difference,
      settlementCount: packages == 0 ? 0 : 1,
      paymentMethods: methods,
    );

CourierDeliveryReport _report() {
  const cash = PaymentMethodTotal(
      paymentMethodId: 'cash',
      displayName: 'Nakit',
      reportingCategory: 'cash',
      count: 2,
      amountMinorUnits: 75000);
  const multinet = PaymentMethodTotal(
      paymentMethodId: 'multinet',
      displayName: 'Multinet',
      reportingCategory: 'mealCard',
      count: 1,
      amountMinorUnits: 20000);
  return CourierDeliveryReport(
    from: DateTime(2026, 11, 12),
    to: DateTime(2026, 11, 13),
    totals: _aggregate(
        packages: 3,
        collected: 95000,
        difference: -1000,
        methods: [cash, multinet]),
    internal: _aggregate(
        packages: 2, collected: 75000, difference: -1000, methods: [cash]),
    pool: _aggregate(packages: 1, collected: 20000, methods: [multinet]),
    couriers: [
      CourierReportRow(
          courierId: 'c1',
          courierName: 'Mehmet',
          kind: CourierKind.internal,
          aggregate: _aggregate(
              packages: 2,
              collected: 75000,
              difference: -1000,
              methods: [cash])),
      CourierReportRow(
          courierId: 'c2',
          courierName: 'Ali',
          kind: CourierKind.pool,
          aggregate:
              _aggregate(packages: 1, collected: 20000, methods: [multinet])),
    ],
    poolOrders: [
      PoolOrderReportRow(
        orderId: 'o3',
        orderNumber: 'DL-3',
        courierName: 'Ali',
        neighborhoodName: 'Moda',
        amountMinorUnits: 20000,
        paymentMethodDisplayName: 'Multinet',
        collectedAt: DateTime.utc(2026, 11, 12, 11),
        deliveryMinutes: 18,
      ),
    ],
    truncated: false,
  );
}

Widget _app(_FakeGateway gateway, Widget child) => ProviderScope(
      overrides: [deliveryOperationsGatewayProvider.overrideWithValue(gateway)],
      child: MaterialApp(home: child),
    );

void main() {
  group('Teslimat Bölgeleri', () {
    Future<void> openDialog(WidgetTester tester, _FakeGateway gateway) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_app(
        gateway,
        const Scaffold(
          body: DeliveryZonesDialog(organizationId: 'org-1', branchId: 'b1'),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('empty list, then a new rule is saved in minor units',
        (tester) async {
      final gateway = _FakeGateway();
      await openDialog(tester, gateway);
      expect(find.byKey(const Key('zonesEmpty')), findsOneWidget);

      await tester.enterText(
          find.byKey(const Key('zoneNeighborhoodField')), 'Caferağa');
      await tester.enterText(find.byKey(const Key('zoneMinimumField')), '250');
      await tester.enterText(find.byKey(const Key('zoneEtaField')), '35');
      await tester.tap(find.byKey(const Key('saveZoneButton')));
      await tester.pumpAndSettle();

      expect(gateway.upserts.single, {
        'neighborhoodName': 'Caferağa',
        'districtName': '',
        'minimumOrderMinorUnits': 25000,
        'estimatedDeliveryMinutes': 35,
        'enabled': true,
      });
      expect(find.textContaining('Min. 250,00 TL'), findsOneWidget);
      expect(find.textContaining('~35 dk'), findsOneWidget);
    });

    testWidgets('validation and the server refusals are explained',
        (tester) async {
      final gateway = _FakeGateway();
      await openDialog(tester, gateway);

      await tester.tap(find.byKey(const Key('saveZoneButton')));
      await tester.pumpAndSettle();
      expect(find.text('Mahalle adını girin.'), findsOneWidget);

      await tester.enterText(
          find.byKey(const Key('zoneNeighborhoodField')), 'Moda');
      await tester.enterText(find.byKey(const Key('zoneEtaField')), '2');
      await tester.tap(find.byKey(const Key('saveZoneButton')));
      await tester.pumpAndSettle();
      expect(find.textContaining('5 ile 240 dakika'), findsOneWidget);
      expect(gateway.upserts, isEmpty);

      await tester.enterText(find.byKey(const Key('zoneEtaField')), '30');
      gateway.upsertError = const DeliveryOperationsException(
          'failed_precondition', 'x',
          detailCode: 'deliveryZone/covered-by-other-branch');
      await tester.tap(find.byKey(const Key('saveZoneButton')));
      await tester.pumpAndSettle();
      expect(find.textContaining('başka bir şube'), findsOneWidget);

      gateway.upsertError =
          const DeliveryOperationsException('permission_denied', 'x');
      await tester.tap(find.byKey(const Key('saveZoneButton')));
      await tester.pumpAndSettle();
      expect(find.textContaining('yalnızca müdür ve üstü'), findsOneWidget);
    });

    testWidgets('editing an existing rule fills the form', (tester) async {
      final gateway = _FakeGateway()
        ..zones = const [
          DeliveryZone(
            id: 'zone-1',
            districtId: 'kadikoy',
            neighborhoodId: 'caferaga',
            neighborhoodName: 'Caferağa',
            minimumOrderMinorUnits: 30000,
            estimatedDeliveryMinutes: 40,
            enabled: true,
          ),
        ];
      await openDialog(tester, gateway);
      await tester.tap(find.byKey(const Key('editZone-zone-1')));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<TextField>(find.byKey(const Key('zoneMinimumField')))
              .controller!
              .text,
          '300');
      expect(
          tester
              .widget<TextField>(find.byKey(const Key('zoneEtaField')))
              .controller!
              .text,
          '40');
    });
  });

  group('Kurye & Paket Raporu', () {
    Future<void> pumpReport(WidgetTester tester, _FakeGateway gateway) async {
      await tester.binding.setSurfaceSize(const Size(1400, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_app(
        gateway,
        CourierDeliveryReportScreen(
          organizationId: 'org-1',
          branchId: 'b1',
          clock: () => DateTime(2026, 11, 12, 15),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets(
        'shows totals, both courier kinds, tender mix, cash difference and '
        'pool orders for today', (tester) async {
      final gateway = _FakeGateway()..report = _report();
      await pumpReport(tester, gateway);

      expect(gateway.reportRanges.single,
          (DateTime(2026, 11, 12), DateTime(2026, 11, 13)));
      expect(find.byKey(const Key('courierReportBody')), findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const Key('statPackages')),
              matching: find.text('3')),
          findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const Key('statCashDifference')),
              matching: find.text('-10,00 TL')),
          findsOneWidget);
      expect(find.text('Restoran Kuryeleri'), findsOneWidget);
      expect(find.text('Kayıtlı Dış Kuryeler'), findsOneWidget);
      expect(find.textContaining('Yemek Kartı — Multinet'), findsWidgets);
      expect(find.byKey(const Key('reportCourier-c1')), findsOneWidget);
      expect(find.byKey(const Key('reportCourier-c2')), findsOneWidget);
      expect(find.byKey(const Key('poolOrder-o3')), findsOneWidget);
      expect(find.text('DL-3 · Ali'), findsOneWidget);
    });

    testWidgets('a preset reloads the range', (tester) async {
      final gateway = _FakeGateway()..report = _report();
      await pumpReport(tester, gateway);
      await tester.tap(find.byKey(const Key('reportPreset-last7Days')));
      await tester.pumpAndSettle();
      expect(gateway.reportRanges.last,
          (DateTime(2026, 11, 6), DateTime(2026, 11, 13)));
      expect(find.text('06.11.2026 – 12.11.2026'), findsOneWidget);
    });

    testWidgets('empty range and permission error states', (tester) async {
      final empty = _FakeGateway()
        ..report = CourierDeliveryReport(
          from: DateTime(2026, 11, 12),
          to: DateTime(2026, 11, 13),
          totals: CourierReportAggregate.empty,
          internal: CourierReportAggregate.empty,
          pool: CourierReportAggregate.empty,
          couriers: const [],
          poolOrders: const [],
          truncated: false,
        );
      await pumpReport(tester, empty);
      expect(
          find.textContaining('hesabı kapatılmış paket yok'), findsOneWidget);

      final denied = _FakeGateway()
        ..reportError =
            const DeliveryOperationsException('permission_denied', 'x');
      await pumpReport(tester, denied);
      expect(find.text('Bu raporu görüntüleme yetkiniz yok.'), findsOneWidget);
    });
  });
}
