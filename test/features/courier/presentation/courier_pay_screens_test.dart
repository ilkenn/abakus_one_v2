import 'package:abakus_one_v2/features/courier/data/courier_pay_gateway.dart';
import 'package:abakus_one_v2/features/courier/domain/pay/courier_pay_models.dart';
import 'package:abakus_one_v2/features/courier/presentation/providers/courier_pay_providers.dart';
import 'package:abakus_one_v2/features/courier/presentation/screens/courier_pay_management_screen.dart';
import 'package:abakus_one_v2/features/courier/presentation/widgets/courier_earnings_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'courier_pay_test_support.dart';

/// ADR-085 stage 5 — "Kazancım" (courier app) and "Kurye Vardiya & Kazanç"
/// (panel), against an in-memory gateway.
final _now = DateTime.utc(2026, 11, 15, 12);

Future<void> _pump(
    WidgetTester tester, FakeCourierPayGateway gateway, Widget child) async {
  await tester.binding.setSurfaceSize(const Size(480, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ProviderScope(
    overrides: [
      courierPayGatewayProvider.overrideWithValue(gateway),
      courierPayClockProvider.overrideWithValue(() => _now),
    ],
    child: MaterialApp(home: child),
  ));
  await tester.pumpAndSettle();
}

CourierShift _shift(CourierShiftStatus status, {String id = 's1'}) =>
    CourierShift(
      shiftId: id,
      branchId: 'branch-1',
      staffUid: 'courier-1',
      courierName: 'Ali Kurye',
      status: status,
      requestedStartAt: DateTime.now().subtract(const Duration(hours: 3)),
      approvedStartAt: status == CourierShiftStatus.startRequested
          ? null
          : DateTime.now().subtract(const Duration(hours: 3)),
      requestedEndAt: status == CourierShiftStatus.endRequested
          ? DateTime.now().subtract(const Duration(minutes: 5))
          : null,
    );

void main() {
  group('Kazancım (courier app)', () {
    testWidgets(
        'a shop courier sees its rate, starts a shift and sees the totals',
        (tester) async {
      final gateway = FakeCourierPayGateway()
        ..myPayResult = emptyMyPay(
          rate: shopRate,
          totals: const CourierEarningsTotals(
            packageCount: 2,
            packageMinorUnits: 8000,
            shiftMinutes: 443,
            shiftMinorUnits: 110750,
            totalMinorUnits: 118750,
          ),
          lines: [
            CourierEarningLine(
              lineId: 'pkg-o1',
              kind: CourierEarningKind.package,
              orderNumber: 'DL-0012',
              unitRateMinorUnits: 4000,
              quantity: 1,
              amountMinorUnits: 4000,
              earnedAt: _now,
              earnedDate: '2026-11-15',
            ),
          ],
        );
      await _pump(tester, gateway, const Scaffold(body: CourierEarningsTab()));

      expect(gateway.calls, ['myPay:2026-11-15..2026-11-15']);
      expect(find.text('Ücretiniz: Paket başı 40 TL · Saatlik 150 TL'),
          findsOneWidget);
      expect(find.text('1.187,50 TL'), findsOneWidget);
      expect(find.text('Vardiya: 7 sa 23 dk · 1.107,50 TL'), findsOneWidget);
      expect(find.text('Paket DL-0012'), findsOneWidget);

      gateway.myPayResult = emptyMyPay(
          rate: shopRate, openShift: _shift(CourierShiftStatus.startRequested));
      await tester.tap(find.byKey(const Key('shiftStart')));
      await tester.pumpAndSettle();
      expect(gateway.calls, contains('startShift'));
      expect(find.text('Vardiya başlangıcı müdür onayına gönderildi.'),
          findsOneWidget);
      expect(find.textContaining('Başlangıç onayı bekliyor'), findsOneWidget);
      expect(find.byKey(const Key('shiftStart')), findsNothing);

      await tester.tap(find.byKey(const Key('earningsPeriod-thisWeek')));
      await tester.pumpAndSettle();
      expect(gateway.calls.last, 'myPay:2026-11-09..2026-11-15');
    });

    testWidgets('an active shift offers Vardiya Bitir; a refusal is in Turkish',
        (tester) async {
      final gateway = FakeCourierPayGateway()
        ..myPayResult = emptyMyPay(
            rate: shopRate, openShift: _shift(CourierShiftStatus.active));
      await _pump(tester, gateway, const Scaffold(body: CourierEarningsTab()));
      expect(find.textContaining('Vardiyadasınız'), findsOneWidget);

      gateway.error = const CourierPayException('Açık vardiyanız yok.');
      await tester.tap(find.byKey(const Key('shiftEnd')));
      await tester.pumpAndSettle();
      expect(gateway.calls, contains('endShift'));
      expect(find.text('Açık vardiyanız yok.'), findsOneWidget);
    });

    testWidgets('a pool courier has no shift card; no rate yet is explained',
        (tester) async {
      final gateway = FakeCourierPayGateway()
        ..myPayResult = emptyMyPay(shiftsEnabled: false);
      await _pump(tester, gateway, const Scaffold(body: CourierEarningsTab()));
      expect(find.byKey(const Key('courierShiftCard')), findsNothing);
      expect(find.text('Ücretiniz henüz tanımlanmadı.'), findsOneWidget);
      expect(find.byKey(const Key('noEarnings')), findsOneWidget);
    });
  });

  group('Kurye Vardiya & Kazanç (panel)', () {
    testWidgets('approve a start, reject one, correct an end with a reason',
        (tester) async {
      final gateway = FakeCourierPayGateway()
        ..openShifts = [
          _shift(CourierShiftStatus.startRequested, id: 'a'),
          _shift(CourierShiftStatus.startRequested, id: 'b'),
          _shift(CourierShiftStatus.endRequested, id: 'c'),
          _shift(CourierShiftStatus.active, id: 'd'),
        ];
      await _pump(tester, gateway,
          const CourierPayManagementScreen(organizationId: 'org-1'));

      expect(find.text('Onay Bekleyenler'), findsOneWidget);
      expect(find.byKey(const Key('approveShift-d')), findsNothing,
          reason: 'a running shift waits for nothing');
      expect(find.byKey(const Key('rejectShift-c')), findsNothing,
          reason: 'an end cannot be rejected');

      await tester.tap(find.byKey(const Key('approveShift-a')));
      await tester.pumpAndSettle();
      expect(gateway.calls, ['approve:a']);
      expect(gateway.lastApprovedAt, isNull);

      await tester.tap(find.byKey(const Key('rejectShift-b')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('rejectShiftReason')), 'Bugün izinli');
      await tester.tap(find.byKey(const Key('rejectShiftConfirm')));
      await tester.pumpAndSettle();
      expect(gateway.calls.last, 'reject:b');
      expect(gateway.lastReason, 'Bugün izinli');

      await tester.tap(find.byKey(const Key('adjustShift-c')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('adjustShiftSave')));
      await tester.pumpAndSettle();
      expect(find.text('Gerekçe yazın.'), findsOneWidget);
      await tester.enterText(
          find.byKey(const Key('adjustShiftReason')), 'Erken çıktı');
      await tester.tap(find.byKey(const Key('adjustShiftSave')));
      await tester.pumpAndSettle();
      expect(gateway.calls.last, 'approve:c');
      expect(gateway.lastReason, 'Erken çıktı');
      expect(gateway.lastApprovedAt, isNotNull);
    });

    testWidgets('earnings per courier for the chosen period', (tester) async {
      final gateway = FakeCourierPayGateway()
        ..report = CourierEarningsReport(
          totalMinorUnits: 52500,
          truncated: false,
          couriers: [
            CourierEarningsEntry(
              staffUid: 'courier-1',
              courierName: 'Ali Kurye',
              totals: const CourierEarningsTotals(
                packageCount: 3,
                packageMinorUnits: 12000,
                shiftMinutes: 162,
                shiftMinorUnits: 40500,
                totalMinorUnits: 52500,
              ),
              lines: [
                CourierEarningLine(
                  lineId: 'shift-s1',
                  kind: CourierEarningKind.shift,
                  orderNumber: null,
                  unitRateMinorUnits: 15000,
                  quantity: 162,
                  amountMinorUnits: 40500,
                  earnedAt: _now,
                  earnedDate: '2026-11-15',
                ),
              ],
            ),
          ],
        );
      await _pump(tester, gateway,
          const CourierPayManagementScreen(organizationId: 'org-1'));
      await tester.tap(find.byKey(const Key('tabCourierEarnings')));
      await tester.pumpAndSettle();

      expect(gateway.calls, contains('earnings:2026-11-15..2026-11-15'));
      expect(find.text('Toplam: 525 TL'), findsOneWidget);
      expect(find.text('3 paket · 2 sa 42 dk vardiya'), findsOneWidget);

      await tester.tap(find.byKey(const Key('courierEarnings-courier-1')));
      await tester.pumpAndSettle();
      expect(find.text('Vardiya 2 sa 42 dk'), findsOneWidget);

      await tester.tap(find.byKey(const Key('panelEarningsPeriod-thisMonth')));
      await tester.pumpAndSettle();
      expect(gateway.calls.last, 'earnings:2026-11-01..2026-11-15');
    });

    testWidgets('nothing open is an explicit empty state', (tester) async {
      await _pump(tester, FakeCourierPayGateway(),
          const CourierPayManagementScreen(organizationId: 'org-1'));
      expect(find.byKey(const Key('noOpenShifts')), findsOneWidget);
    });
  });
}
