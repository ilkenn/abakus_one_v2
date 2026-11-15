import 'dart:typed_data';

import 'package:abakus_one_v2/features/admin/domain/approval/approval_request.dart';
import 'package:abakus_one_v2/features/courier/data/courier_oversight_gateway.dart';
import 'package:abakus_one_v2/features/courier/presentation/providers/courier_oversight_providers.dart';
import 'package:abakus_one_v2/features/courier/presentation/screens/courier_oversight_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// ADR-085 stage 6B — "Kurye Denetimi": payment-method changes at the door.
class _FakeGateway implements CourierOversightGateway {
  List<CourierPaymentChange> changes = const [];
  List<CourierOperationalAlert> openAlerts = const [];
  CourierOperationSettings current =
      (cashLimitMinorUnits: 300000, lateDeliveryMinutes: 35);
  CourierOperationSettings? saved;

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
    saved = settings;
  }

  final calls = <String>[];
  String? lastNote;

  @override
  Future<List<CourierPaymentChange>> paymentChanges({
    required String organizationId,
  }) async =>
      changes;

  @override
  Future<void> markReviewed({
    required String organizationId,
    required String orderId,
    String? note,
  }) async {
    calls.add('reviewed:$orderId');
    lastNote = note;
  }

  @override
  Future<Uint8List> slipPhoto({
    required String organizationId,
    required String orderId,
  }) async {
    calls.add('slip:$orderId');
    return Uint8List.fromList(const [
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
      0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
      0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
      0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
      0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
    ]);
  }
}

CourierPaymentChange _change(String id,
        {CourierPaymentChangeStatus status =
            CourierPaymentChangeStatus.pendingReview,
        bool hasSlip = true}) =>
    CourierPaymentChange(
      orderId: id,
      orderNumber: 'DL-$id',
      courierName: 'Ali Kurye',
      fromLabel: 'Nakit',
      toLabel: 'Multinet',
      amountDueMinorUnits: 45000,
      hasSlip: hasSlip,
      status: status,
      reportedAt: DateTime(2026, 11, 15, 14, 5),
      reviewNote: null,
    );

Future<_FakeGateway> _pump(WidgetTester tester, _FakeGateway gateway) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [courierOversightGatewayProvider.overrideWithValue(gateway)],
    child: const MaterialApp(
        home: CourierOversightScreen(organizationId: 'org-1')),
  ));
  await tester.pumpAndSettle();
  return gateway;
}

void main() {
  testWidgets('a change shows old → new, opens the slip and is marked reviewed',
      (tester) async {
    final gateway = await _pump(
        tester,
        _FakeGateway()
          ..changes = [
            _change('a'),
            _change('b', status: CourierPaymentChangeStatus.reviewed),
          ]);
    expect(find.text('1 değişiklik inceleme bekliyor.'), findsOneWidget);
    expect(find.text('Nakit → Multinet · 450 TL'), findsNWidgets(2));
    expect(find.byKey(const Key('markReviewed-b')), findsNothing);

    await tester.tap(find.byKey(const Key('showSlip-a')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('slipImage')), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('markReviewed-a')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('reviewNote')), 'Slip uygun');
    await tester.tap(find.byKey(const Key('reviewConfirm')));
    await tester.pumpAndSettle();
    expect(gateway.calls, ['slip:a', 'reviewed:a']);
    expect(gateway.lastNote, 'Slip uygun');
  });

  testWidgets('a switch to cash has no slip; nothing changed is explicit',
      (tester) async {
    await _pump(
        tester, _FakeGateway()..changes = [_change('c', hasSlip: false)]);
    expect(find.text('Nakde geçildi — slip yok.'), findsOneWidget);
  });

  testWidgets('empty state', (tester) async {
    await _pump(tester, _FakeGateway());
    expect(find.byKey(const Key('noPaymentChanges')), findsOneWidget);
  });

  test('the Onay Kutusu knows the courier cancellation request', () {
    expect(approvalActionTypeFromWire('courierOrderCancellation'),
        ApprovalActionType.courierOrderCancellation);
  });
}
