import 'package:abakus_one_v2/features/admin/data/manager_oversight_gateway.dart';
import 'package:abakus_one_v2/features/admin/presentation/providers/manager_oversight_providers.dart';
import 'package:abakus_one_v2/features/admin/presentation/screens/manager_actions_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// ADR-085 stage 6C-2 — "Müdür İşlemleri" (admin/owner).
class _FakeGateway implements ManagerOversightGateway {
  List<ManagerActionAlert> items = const [];
  ManagerOversightException? listError;
  final acknowledged = <String>[];

  @override
  Future<List<ManagerActionAlert>> alerts(
      {required String organizationId}) async {
    final e = listError;
    if (e != null) throw e;
    return [
      for (final a in items)
        acknowledged.contains(a.alertId)
            ? ManagerActionAlert(
                alertId: a.alertId,
                branchId: a.branchId,
                type: a.type,
                actorName: a.actorName,
                orderNumber: a.orderNumber,
                amountMinorUnits: a.amountMinorUnits,
                detail: a.detail,
                reason: a.reason,
                createdAt: a.createdAt,
                acknowledged: true,
              )
            : a,
    ];
  }

  @override
  Future<void> acknowledge({
    required String organizationId,
    required String alertId,
  }) async =>
      acknowledged.add(alertId);
}

ManagerActionAlert _alert(String id, ManagerActionType type,
        {int? amount, String? detail, String? order, bool seen = false}) =>
    ManagerActionAlert(
      alertId: id,
      branchId: 'branch-1',
      type: type,
      actorName: 'Ayşe Müdür',
      orderNumber: order,
      amountMinorUnits: amount,
      detail: detail,
      reason: 'Gerekçe $id',
      createdAt: DateTime(2026, 11, 15, 21, 5),
      acknowledged: seen,
    );

Future<void> _pump(WidgetTester tester, _FakeGateway gateway) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [managerOversightGatewayProvider.overrideWithValue(gateway)],
    child:
        const MaterialApp(home: ManagerActionsScreen(organizationId: 'org-1')),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists unseen manager actions with their reasons and amounts',
      (tester) async {
    await _pump(
        tester,
        _FakeGateway()
          ..items = [
            _alert('c1', ManagerActionType.comp,
                amount: 123450, detail: 'complimentary'),
            _alert('v1', ManagerActionType.cashVariance,
                amount: 30000, detail: 'short'),
            _alert('o1', ManagerActionType.orderCancellation,
                amount: 25000, order: 'DL-0042'),
            _alert('old', ManagerActionType.lineCancellation, seen: true),
          ]);
    expect(find.text('İkram / İndirim'), findsOneWidget);
    expect(find.textContaining('1.234,50 TL'), findsOneWidget);
    expect(find.textContaining('-300 TL · Kasa açığı'), findsOneWidget);
    expect(find.textContaining('DL-0042'), findsOneWidget);
    expect(find.text('Gerekçe: Gerekçe c1'), findsOneWidget);
    expect(find.byKey(const Key('managerAction-old')), findsNothing,
        reason: 'already seen — only under "Tümü"');

    await tester.tap(find.text('Tümü'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('managerAction-old')), findsOneWidget);
  });

  testWidgets('"Görüldü" marks an action read and it leaves the unseen list',
      (tester) async {
    final gateway = _FakeGateway()
      ..items = [_alert('c1', ManagerActionType.comp, amount: 5000)];
    await _pump(tester, gateway);
    await tester.tap(find.byKey(const Key('acknowledge-c1')));
    await tester.pumpAndSettle();
    expect(gateway.acknowledged, ['c1']);
    expect(find.byKey(const Key('noManagerActions')), findsOneWidget);
  });

  testWidgets('an empty list is an explicit state', (tester) async {
    await _pump(tester, _FakeGateway());
    expect(find.text('Görülmemiş müdür işlemi yok.'), findsOneWidget);
  });

  testWidgets('a refused list shows the Turkish reason', (tester) async {
    await _pump(
        tester,
        _FakeGateway()
          ..listError = const ManagerOversightException(
              'Müdür işlemlerini yalnızca Yönetici ve İşletme Sahibi görebilir.'));
    expect(
        find.text(
            'Müdür işlemlerini yalnızca Yönetici ve İşletme Sahibi görebilir.'),
        findsOneWidget);
  });

  test('formatting', () {
    expect(formatLira(123450), '1.234,50 TL');
    expect(formatLira(-30000), '-300 TL');
    expect(formatLira(100000000), '1.000.000 TL');
    expect(ManagerActionType.parse('managerCashVariance'),
        ManagerActionType.cashVariance);
    expect(ManagerActionType.parse('managerOrderCancellation').label,
        'Sipariş İptali');
  });
}
