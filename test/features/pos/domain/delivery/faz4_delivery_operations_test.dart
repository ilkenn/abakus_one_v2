import 'package:abakus_one_v2/features/pos/data/delivery_operations_gateway.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/pos_authorized_action.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/role_permission_map.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/staff_role.dart';
import 'package:abakus_one_v2/features/pos/domain/delivery/courier_delivery_report.dart';
import 'package:abakus_one_v2/features/pos/domain/delivery/delivery_zone.dart';
import 'package:abakus_one_v2/features/pos/presentation/screens/courier_delivery_report_screen.dart';
import 'package:abakus_one_v2/features/pos/presentation/widgets/delivery_order_dialogs.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-11-12 — Faz 4 client-side rules and wire mapping.
DeliveryZone _zone(String id, String district, String neighborhood,
        {bool enabled = true}) =>
    DeliveryZone(
      id: id,
      districtId: district,
      neighborhoodId: neighborhood,
      neighborhoodName: neighborhood,
      minimumOrderMinorUnits: 25000,
      estimatedDeliveryMinutes: 35,
      enabled: enabled,
    );

void main() {
  group('neighborhoodKey (mirror of the server slug)', () {
    test('Turkish letters, case and spaces', () {
      expect(neighborhoodKey('Caferağa'), 'caferaga');
      expect(neighborhoodKey('  CAFERAĞA '), 'caferaga');
      expect(neighborhoodKey('İçerenköy'), 'icerenkoy');
      expect(neighborhoodKey('Kozyatağı Mah.'), 'kozyatagi_mah');
      expect(neighborhoodKey('Şaşkınbakkal'), 'saskinbakkal');
      expect(neighborhoodKey(''), '');
    });
  });

  group('BranchDeliveryZones.zoneFor', () {
    test('enabled match only; unknown → null', () {
      final zones =
          BranchDeliveryZones(defaultDeliveryDistrictId: null, zones: [
        _zone('a', 'kadikoy', 'caferaga'),
        _zone('b', 'kadikoy', 'moda', enabled: false),
      ]);
      expect(zones.zoneFor('Caferağa')?.id, 'a');
      expect(zones.zoneFor('Moda'), isNull);
      expect(zones.zoneFor('Fenerbahçe'), isNull);
      expect(zones.zoneFor(''), isNull);
    });

    test('a name shared by two districts resolves to the default district', () {
      final zones = [
        _zone('a', 'kadikoy', 'caferaga'),
        _zone('b', 'uskudar', 'caferaga'),
      ];
      expect(
          BranchDeliveryZones(
                  defaultDeliveryDistrictId: 'uskudar', zones: zones)
              .zoneFor('Caferağa')
              ?.id,
          'b');
      expect(
          BranchDeliveryZones(defaultDeliveryDistrictId: null, zones: zones)
              .zoneFor('Caferağa'),
          isNull);
    });
  });

  test('Faz 4 actions are manager-tier and above', () {
    for (final action in [
      PosAuthorizedAction.viewDeliveryReport,
      PosAuthorizedAction.overrideDeliveryMinimumOrder,
      PosAuthorizedAction.erasePosCustomerData,
    ]) {
      for (final role in [
        StaffRole.manager,
        StaffRole.admin,
        StaffRole.tenantOwner,
      ]) {
        expect(RolePermissionMap.allows({role}, action), isTrue,
            reason: '$role $action');
      }
      for (final role in [
        StaffRole.staff,
        StaffRole.cashier,
        StaffRole.packingLead,
        StaffRole.courier,
      ]) {
        expect(RolePermissionMap.allows({role}, action), isFalse,
            reason: '$role must not $action');
      }
    }
  });

  test('formatTlMinor groups thousands and keeps kuruş', () {
    expect(formatTlMinor(25000), '250,00 TL');
    expect(formatTlMinor(100000), '1.000,00 TL');
    expect(formatTlMinor(1234567), '12.345,67 TL');
    expect(formatTlMinor(-500), '-5,00 TL');
    expect(formatTlMinor(0), '0,00 TL');
  });

  test('courierReportRangeFor: local day ranges', () {
    final now = DateTime(2026, 11, 12, 15, 30);
    final today = courierReportRangeFor(CourierReportPreset.today, now);
    expect(today.from, DateTime(2026, 11, 12));
    expect(today.to, DateTime(2026, 11, 13));
    final yesterday = courierReportRangeFor(CourierReportPreset.yesterday, now);
    expect(yesterday.from, DateTime(2026, 11, 11));
    expect(yesterday.to, DateTime(2026, 11, 12));
    final week = courierReportRangeFor(CourierReportPreset.last7Days, now);
    expect(week.from, DateTime(2026, 11, 6));
    expect(week.to, DateTime(2026, 11, 13));
    final month = courierReportRangeFor(CourierReportPreset.thisMonth, now);
    expect(month.from, DateTime(2026, 11, 1));
  });

  test('courierDeliveryReportFromWire maps the server report', () {
    final report = courierDeliveryReportFromWire({
      'fromIso': '2026-11-10T00:00:00.000Z',
      'toIso': '2026-11-11T00:00:00.000Z',
      'totals': {
        'packageCount': 3,
        'collectedMinorUnits': 95000,
        'averagePreparationMinutes': 20,
        'averageDeliveryMinutes': 31.5,
        'cashDifferenceMinorUnits': -500,
        'settlementCount': 2,
        'paymentMethods': [
          {
            'paymentMethodId': 'cash',
            'displayName': 'Nakit',
            'reportingCategory': 'cash',
            'count': 1,
            'amountMinorUnits': 45000,
          },
          {
            'paymentMethodId': 'multinet',
            'displayName': 'Multinet',
            'reportingCategory': 'mealCard',
            'count': 1,
            'amountMinorUnits': 20000,
          },
        ],
      },
      'byKind': {
        'internal': {'packageCount': 2, 'paymentMethods': []},
        'pool': {'packageCount': 1, 'paymentMethods': []},
      },
      'couriers': [
        {
          'courierId': 'c1',
          'courierName': 'Ali',
          'courierKind': 'pool',
          'packageCount': 1,
          'paymentMethods': [],
        },
      ],
      'poolOrders': [
        {
          'orderId': 'o3',
          'orderNumber': 'DL-3',
          'courierName': 'Ali',
          'neighborhoodName': 'Moda',
          'amountMinorUnits': 20000,
          'paymentMethodDisplayName': 'Multinet',
          'collectedAt': '2026-11-10T11:00:00.000Z',
          'deliveryMinutes': 18,
        },
      ],
      'truncated': false,
    });
    expect(report.totals.packageCount, 3);
    expect(report.totals.averageDeliveryMinutes, 31.5);
    expect(report.totals.cashDifferenceMinorUnits, -500);
    expect(report.totals.paymentMethods.map((m) => m.label),
        ['Nakit', 'Yemek Kartı — Multinet']);
    expect(report.internal.packageCount, 2);
    expect(report.pool.packageCount, 1);
    expect(report.couriers.single.kind, CourierKind.pool);
    expect(report.poolOrders.single.deliveryMinutes, 18);
    expect(report.isEmpty, isFalse);
  });

  test('branchDeliveryZonesFromWire maps the list', () {
    final zones = branchDeliveryZonesFromWire({
      'defaultDeliveryDistrictId': 'kadikoy',
      'zones': [
        {
          'id': 'z1',
          'districtId': 'kadikoy',
          'neighborhoodId': 'caferaga',
          'neighborhoodName': 'Caferağa',
          'minimumOrderMinorUnits': 25000,
          'estimatedDeliveryMinutes': null,
          'enabled': true,
        },
      ],
    });
    expect(zones.defaultDeliveryDistrictId, 'kadikoy');
    expect(zones.zones.single.estimatedDeliveryMinutes, isNull);
    expect(zones.zoneFor('caferağa')?.minimumOrderMinorUnits, 25000);
  });
}
