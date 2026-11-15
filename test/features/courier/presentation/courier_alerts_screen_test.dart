import 'dart:typed_data';

import 'package:abakus_one_v2/features/courier/data/courier_oversight_gateway.dart';
import 'package:abakus_one_v2/features/courier/presentation/providers/courier_oversight_providers.dart';
import 'package:abakus_one_v2/features/courier/presentation/screens/courier_alerts_screen.dart';
import 'package:abakus_one_v2/features/pos/data/cash_register_gateway.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// ADR-085 stage 6C-1 — "Kurye Uyarıları" and the day-end lock message.
class _FakeGateway implements CourierOversightGateway {
  List<CourierOperationalAlert> openAlerts = const [];
  CourierOperationSettings current =
      (cashLimitMinorUnits: 300000, lateDeliveryMinutes: 35);
  CourierOperationSettings? saved;
  CourierOversightException? saveError;

  @override
  Future<List<CourierOperationalAlert>> alerts({
    required String organizationId,
  }) async =>
      openAlerts;

  @override
  Future<CourierOperationSettings> settings({
    required String organizationId,
    required String branchId,
  }) async =>
      current;

  @override
  Future<void> saveSettings({
    required String organizationId,
    required String branchId,
    required CourierOperationSettings settings,
  }) async {
    final e = saveError;
    if (e != null) throw e;
    saved = settings;
  }

  @override
  Future<List<CourierPaymentChange>> paymentChanges({
    required String organizationId,
  }) async =>
      const [];

  @override
  Future<void> markReviewed({
    required String organizationId,
    required String orderId,
    String? note,
  }) async {}

  @override
  Future<Uint8List> slipPhoto({
    required String organizationId,
    required String orderId,
  }) async =>
      Uint8List(0);
}

Future<_FakeGateway> _pump(WidgetTester tester, _FakeGateway gateway) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [courierOversightGatewayProvider.overrideWithValue(gateway)],
    child: const MaterialApp(
      home: CourierAlertsScreen(organizationId: 'org-1', branchId: 'branch-1'),
    ),
  ));
  await tester.pumpAndSettle();
  return gateway;
}

void main() {
  testWidgets('cash-limit and late alerts are listed in red', (tester) async {
    await _pump(
        tester,
        _FakeGateway()
          ..openAlerts = [
            CourierOperationalAlert(
              alertId: 'cashLimit-c1',
              type: CourierAlertType.cashLimit,
              courierName: 'Ali Kurye',
              orderId: null,
              orderNumber: null,
              amountMinorUnits: 320000,
              limitMinorUnits: 300000,
              minutes: null,
              openedAt: DateTime(2026, 11, 15, 14, 5),
            ),
            CourierOperationalAlert(
              alertId: 'late-o1',
              type: CourierAlertType.late,
              courierName: 'Ali Kurye',
              orderId: 'o1',
              orderNumber: 'DL-0001',
              amountMinorUnits: null,
              limitMinorUnits: null,
              minutes: 42,
              openedAt: DateTime(2026, 11, 15, 14, 10),
            ),
          ]);
    expect(find.text('Ali Kurye — nakit limiti doldu'), findsOneWidget);
    expect(find.textContaining('3.200 TL · limit 3.000 TL'), findsOneWidget);
    expect(find.text('DL-0001 — GECİKTİ (42 dk)'), findsOneWidget);
    // Let the one-minute refresh timer go, so no timer is left pending.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('no alerts is an explicit empty state', (tester) async {
    await _pump(tester, _FakeGateway());
    expect(find.byKey(const Key('noCourierAlerts')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a manager changes the cash limit and the late threshold',
      (tester) async {
    final gateway = await _pump(tester, _FakeGateway());
    await tester.tap(find.byKey(const Key('courierSettingsOpen')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('settingsCashLimit')))
            .controller
            ?.text,
        '3000');
    await tester.enterText(find.byKey(const Key('settingsCashLimit')), '2500');
    await tester.enterText(find.byKey(const Key('settingsLateMinutes')), '2');
    await tester.tap(find.byKey(const Key('settingsSave')));
    await tester.pumpAndSettle();
    expect(find.text('5 ile 240 dakika arasında olmalı'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('settingsLateMinutes')), '30');
    await tester.tap(find.byKey(const Key('settingsSave')));
    await tester.pumpAndSettle();
    expect(
        gateway.saved, (cashLimitMinorUnits: 250000, lateDeliveryMinutes: 30));
    expect(find.text('Kurye ayarları kaydedildi.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  test('the day-end lock lists every open courier item in Turkish', () {
    final message = courierWorkOpenMessage({
      'code': 'courierWorkOpen',
      'openCourierPackages': [
        {'orderId': 'o1', 'orderNumber': 'DL-1', 'delivered': true},
        {'orderId': 'o2', 'orderNumber': 'DL-2', 'delivered': false},
      ],
      'pendingCancellations': [
        {'orderNumber': 'DL-3', 'courierName': 'Ali'},
      ],
      'pendingPaymentChanges': [
        {'orderNumber': 'DL-4', 'courierName': 'Ali'},
      ],
    })!;
    expect(message, contains('Gün sonu yapılamaz'));
    expect(
        message, contains('DL-1: kasada mutabakatı yapılmadı (teslim edildi)'));
    expect(
        message, contains('DL-2: kasada mutabakatı yapılmadı (kurye yolda)'));
    expect(
        message, contains("DL-3: Ali iptal talebi Onay Kutusu'nda bekliyor"));
    expect(message, contains("Kurye Denetimi'nde incelenmedi"));
    expect(courierWorkOpenMessage({'code': 'openTables'}), isNull);
  });
}
