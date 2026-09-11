import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abakus_one_v2/features/pos/data/cash_register_gateway.dart';
import 'package:abakus_one_v2/features/pos/data/pos_action_gateway.dart';
import 'package:abakus_one_v2/features/pos/data/pos_operational_view_gateway.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/pos_workspace_providers.dart';
import 'package:abakus_one_v2/features/pos/presentation/screens/end_of_day_screen.dart';

class _FakePosOperationalViewGateway implements PosOperationalViewGateway {
  List<PosBranchTableSummary> tables = const [];

  @override
  Future<PosBranchOverviewPage> getBranchOverview({
    required String organizationId,
    required String branchId,
    required String deviceId,
    required String deviceSessionId,
    String? cursor,
    String? ifNoneMatchVersion,
  }) async {
    return PosBranchOverviewPage(
        tables: tables, nextCursor: null, version: 'v1', unchanged: false);
  }

  @override
  Future<PosTableOperationalView> getTableView({
    required String organizationId,
    required String branchId,
    required String tableId,
    required String deviceId,
    required String deviceSessionId,
  }) async =>
      throw UnimplementedError();
}

class _FakeCashRegisterGateway implements CashRegisterGateway {
  List<CashDrawerSummary> drawers = const [];
  CashSessionView? sessionView;
  DailyRevenueSummary? revenueSummary;

  @override
  Future<String> createCashDrawer({
    required PosDeviceContext ctx,
    required String name,
  }) async =>
      throw UnimplementedError();

  @override
  Future<List<CashDrawerSummary>> listCashDrawers({
    required PosDeviceContext ctx,
  }) async =>
      drawers;

  @override
  Future<CashSessionView> getCashSessionView({
    required PosDeviceContext ctx,
    required String sessionId,
  }) async =>
      sessionView!;

  @override
  Future<DailyRevenueSummary> getDailyRevenueSummary({
    required PosDeviceContext ctx,
    required String sessionId,
  }) async =>
      revenueSummary!;

  @override
  Future<CashSessionOpenResult> requestCashSessionOpen({
    required PosDeviceContext ctx,
    required String drawerId,
    required int openingFloatAmountMinorUnits,
    required String currencyCode,
    required String reason,
  }) async =>
      throw UnimplementedError();

  @override
  Future<CashRequestResult> requestCashMovement({
    required PosDeviceContext ctx,
    required String sessionId,
    required String movementType,
    required int amountMinorUnits,
    required String reason,
  }) async =>
      throw UnimplementedError();

  @override
  Future<CashRequestResult> requestCashAdjustment({
    required PosDeviceContext ctx,
    required String sessionId,
    required int amountMinorUnits,
    required String reason,
  }) async =>
      throw UnimplementedError();

  @override
  Future<CashCountResult> submitCashCount({
    required PosDeviceContext ctx,
    required String sessionId,
    required int actualAmountMinorUnits,
    String notes = '',
  }) async =>
      throw UnimplementedError();

  @override
  Future<void> closeCashSession({
    required PosDeviceContext ctx,
    required String sessionId,
  }) async =>
      throw UnimplementedError();
}

const _ctx = PosDeviceContext(
  organizationId: 'org-1',
  branchId: 'branch-1',
  deviceId: 'device-1',
  deviceSessionId: 'session-1',
);

void main() {
  testWidgets(
      'an occupied table locks the screen with a warning card listing it, never showing the count UI',
      (tester) async {
    final overviewGateway = _FakePosOperationalViewGateway()
      ..tables = [
        const PosBranchTableSummary(
          tableId: 'table-1',
          displayName: 'Masa 5',
          status: 'occupied',
          activeTableSessionId: 'tsess-1',
          pendingQrLineCount: 0,
        ),
      ];
    final cashGateway = _FakeCashRegisterGateway();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          posOperationalViewGatewayProvider.overrideWithValue(overviewGateway),
          cashRegisterGatewayProvider.overrideWithValue(cashGateway),
          posDeviceContextProvider.overrideWithValue(_ctx),
        ],
        child: const MaterialApp(home: EndOfDayScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('masa hâlâ açık'), findsOneWidget);
    expect(find.text('Masa 5'), findsOneWidget);
    expect(find.byKey(const Key('actualAmountField')), findsNothing);
  });

  testWidgets('no open tables and no open cash session shows the empty state',
      (tester) async {
    final overviewGateway = _FakePosOperationalViewGateway();
    final cashGateway = _FakeCashRegisterGateway()..drawers = const [];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          posOperationalViewGatewayProvider.overrideWithValue(overviewGateway),
          cashRegisterGatewayProvider.overrideWithValue(cashGateway),
          posDeviceContextProvider.overrideWithValue(_ctx),
        ],
        child: const MaterialApp(home: EndOfDayScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('Kapatılacak açık bir kasa oturumu'), findsOneWidget);
  });

  testWidgets(
      'no open tables, an open session: shows Nakit/Kredi Kartı/Diğer summary and a live variance preview as the count is typed',
      (tester) async {
    final overviewGateway = _FakePosOperationalViewGateway();
    final cashGateway = _FakeCashRegisterGateway()
      ..drawers = [
        const CashDrawerSummary(
          drawerId: 'drawer-1',
          name: 'Ana Kasa',
          isActive: true,
          openSession: CashOpenSessionSummary(sessionId: 'sess-1', status: 'approved'),
        ),
      ]
      ..sessionView = CashSessionView(
        exists: true,
        sessionId: 'sess-1',
        drawerId: 'drawer-1',
        status: 'active',
        businessDate: '2026-09-11',
        openingFloatAmountMinorUnits: 5000,
        settledAmountMinorUnits: 5000,
        currencyCode: 'TRY',
        cashRegisterModel: 'sharedDrawer',
        movements: [
          CashMovementSummary(
            type: 'cashSale',
            amountMinorUnits: 10000,
            reason: 'Satış',
            timestamp: DateTime(2026, 9, 11, 10),
          ),
        ],
      )
      ..revenueSummary = const DailyRevenueSummary(
        sessionId: 'sess-1',
        currencyCode: 'TRY',
        cashMinorUnits: 10000,
        cardMinorUnits: 20000,
        otherMinorUnits: 500,
        totalMinorUnits: 30500,
      );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          posOperationalViewGatewayProvider.overrideWithValue(overviewGateway),
          cashRegisterGatewayProvider.overrideWithValue(cashGateway),
          posDeviceContextProvider.overrideWithValue(_ctx),
        ],
        child: const MaterialApp(home: EndOfDayScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Expected (BR-CASH-004 mirror): openingFloat 5000 + movements 10000 = 15000.
    expect(find.byKey(const Key('actualAmountField')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('actualAmountField')), '150.00');
    await tester.pump();
    expect(find.textContaining('Tahmini Fark: Tam'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('actualAmountField')), '148.00');
    await tester.pump();
    expect(find.textContaining('Tahmini Fark: Eksik'), findsOneWidget);
  });
}
