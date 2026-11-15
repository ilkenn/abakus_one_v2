import 'package:flutter_test/flutter_test.dart';

import 'package:abakus_one_v2/features/courier/domain/pay/courier_pay_models.dart';

void main() {
  group('amounts (ADR-085 stage 5)', () {
    test('parses lira as typed into kuruş', () {
      expect(parseLiraToMinorUnits('150'), 15000);
      expect(parseLiraToMinorUnits('150,5'), 15050);
      expect(parseLiraToMinorUnits(' 45.75 '), 4575);
      expect(parseLiraToMinorUnits('0'), 0);
      for (final bad in ['', '-5', '1,234', 'abc', '12,']) {
        expect(parseLiraToMinorUnits(bad), isNull, reason: bad);
      }
    });

    test('formats amounts and shift time in Turkish', () {
      expect(formatPayAmount(147667), '1.476,67 TL');
      expect(formatPayAmount(15000), '150 TL');
      expect(formatPayAmount(123456700), '1.234.567 TL');
      expect(minorUnitsToLiraText(15050), '150,50');
      expect(minorUnitsToLiraText(4000), '40');
      expect(formatShiftMinutes(443), '7 sa 23 dk');
      expect(formatShiftMinutes(45), '45 dk');
      expect(formatShiftMinutes(120), '2 sa');
    });
  });

  group('periods', () {
    test('use the Istanbul day; weeks start on Monday', () {
      // Sunday 2026-11-15 22:30 UTC is already Monday 16th in Istanbul.
      final late = DateTime.utc(2026, 11, 15, 22, 30);
      expect(CourierPayPeriod.today.range(late),
          (fromDate: '2026-11-16', toDate: '2026-11-16'));
      final sunday = DateTime.utc(2026, 11, 15, 10);
      expect(CourierPayPeriod.thisWeek.range(sunday),
          (fromDate: '2026-11-09', toDate: '2026-11-15'));
      expect(CourierPayPeriod.thisMonth.range(sunday),
          (fromDate: '2026-11-01', toDate: '2026-11-15'));
    });
  });

  group('rates', () {
    test('parse from the server and summarize', () {
      final shop = CourierPayRate.fromJson(const {
        'versionId': 'v2',
        'courierKind': 'shop',
        'perPackageMinorUnits': 4000,
        'hourlyMinorUnits': 15000,
        'effectiveFromDate': '2026-11-15',
      });
      expect(shop.summary, 'Paket başı 40 TL · Saatlik 150 TL');
      final pool = CourierPayRate.fromJson(const {
        'courierKind': 'pool',
        'perPackageMinorUnits': 9000,
        'hourlyMinorUnits': null,
      });
      expect(pool.kind, CourierPayKind.pool);
      expect(pool.summary, 'Paket başı 90 TL');
    });

    test('an input sends only what its kind uses and knows when it changed',
        () {
      const current = CourierPayRate(
        versionId: 'v1',
        kind: CourierPayKind.shop,
        perPackageMinorUnits: 4000,
        hourlyMinorUnits: 15000,
        effectiveFromDate: '2026-11-15',
      );
      const same = CourierPayRateInput(
          kind: CourierPayKind.shop,
          perPackageMinorUnits: 4000,
          hourlyMinorUnits: 15000);
      expect(same.differsFrom(current), isFalse);
      expect(same.differsFrom(null), isTrue);
      const pool = CourierPayRateInput(
          kind: CourierPayKind.pool,
          perPackageMinorUnits: 9000,
          hourlyMinorUnits: 100);
      expect(
          pool.toJson(), {'courierKind': 'pool', 'perPackageMinorUnits': 9000});
      const later = CourierPayRateInput(
          kind: CourierPayKind.shop,
          perPackageMinorUnits: 4000,
          hourlyMinorUnits: 15000,
          effectiveFromDate: '2026-12-01');
      expect(later.differsFrom(current), isTrue);
      expect(later.toJson()['effectiveFromDate'], '2026-12-01');
    });
  });

  test('my pay parses shift and lines', () {
    final pay = MyCourierPay.fromJson(const {
      'shiftsEnabled': true,
      'currentRate': null,
      'openShift': {
        'shiftId': 's1',
        'status': 'active',
        'courierName': 'Ali',
        'requestedStartAtMillis': 1763190000000,
        'approvedStartAtMillis': 1763189000000,
      },
      'packageCount': 2,
      'packageMinorUnits': 8000,
      'shiftMinutes': 90,
      'shiftMinorUnits': 22500,
      'totalMinorUnits': 30500,
      'lines': [
        {
          'lineId': 'shift-s0',
          'kind': 'shift',
          'quantity': 90,
          'unitRateMinorUnits': 15000,
          'amountMinorUnits': 22500,
          'earnedAtMillis': 1763190000000,
          'earnedDate': '2026-11-15',
        },
      ],
    });
    expect(pay.openShift!.status, CourierShiftStatus.active);
    expect(pay.totals.totalMinorUnits, 30500);
    expect(pay.lines.single.title, 'Vardiya 1 sa 30 dk');
  });
}
