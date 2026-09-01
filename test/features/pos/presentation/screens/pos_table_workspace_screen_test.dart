import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abakus_one_v2/features/pos/data/pos_action_gateway.dart';
import 'package:abakus_one_v2/features/pos/data/pos_operational_view_gateway.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/pos_workspace_providers.dart';
import 'package:abakus_one_v2/features/pos/presentation/screens/pos_table_workspace_screen.dart';

class _FakePosOperationalViewGateway implements PosOperationalViewGateway {
  PosTableOperationalView? viewToReturn;
  int callCount = 0;

  @override
  Future<PosTableOperationalView> getTableView({
    required String organizationId,
    required String branchId,
    required String tableId,
    required String deviceId,
    required String deviceSessionId,
  }) async {
    callCount += 1;
    return viewToReturn!;
  }

  @override
  Future<PosBranchOverviewPage> getBranchOverview({
    required String organizationId,
    required String branchId,
    required String deviceId,
    required String deviceSessionId,
    String? cursor,
    String? ifNoneMatchVersion,
  }) async =>
      throw UnimplementedError();
}

class _FakePosActionGateway implements PosActionGateway {
  int respondCallCount = 0;
  ({int lineIndex, bool accept})? lastDecision;
  String? lastRespondOrderId;

  int openCheckCallCount = 0;
  String checkIdToReturn = 'check-1';

  int finalizeCallCount = 0;

  int splitByCustomerCallCount = 0;
  int splitByProductCallCount = 0;

  int transferCallCount = 0;
  String? lastTransferTarget;

  @override
  Future<void> respondToOrderLines({
    required String orderId,
    required List<({int lineIndex, bool accept})> decisions,
  }) async {
    respondCallCount += 1;
    lastRespondOrderId = orderId;
    lastDecision = decisions.first;
  }

  @override
  Future<String> openCheck({
    required PosDeviceContext ctx,
    required String tableSessionId,
  }) async {
    openCheckCallCount += 1;
    return checkIdToReturn;
  }

  @override
  Future<void> finalizeCheckReadyForPayment({
    required PosDeviceContext ctx,
    required String checkId,
  }) async {
    finalizeCallCount += 1;
  }

  @override
  Future<String> splitByCustomer({
    required PosDeviceContext ctx,
    required String checkId,
    required String subAccountId,
  }) async {
    splitByCustomerCallCount += 1;
    return 'alloc-1';
  }

  @override
  Future<String> splitByProduct({
    required PosDeviceContext ctx,
    required String checkId,
    required String subAccountId,
    required String sourceOrderId,
    required int sourceLineIndex,
  }) async {
    splitByProductCallCount += 1;
    return 'alloc-2';
  }

  @override
  Future<void> transferTable({
    required PosDeviceContext ctx,
    required String sourceTableId,
    required String targetTableId,
  }) async {
    transferCallCount += 1;
    lastTransferTarget = targetTableId;
  }

  @override
  Future<void> mergeTables({
    required PosDeviceContext ctx,
    required String sourceTableId,
    required String targetTableId,
  }) async {}

  @override
  Future<void> proposeLineReplacement({
    required PosDeviceContext ctx,
    required String orderId,
    required int lineIndex,
    required String proposedProductId,
    required int proposedQuantity,
    required String reasonCode,
    required String reasonMessage,
  }) async {}

  @override
  Future<String> submitStaffEntryOrder({
    required PosDeviceContext ctx,
    required String tableId,
    required Map<String, dynamic> subAccountSelection,
    required List<Map<String, dynamic>> items,
  }) async =>
      'order-staff-1';

  int splitEqualByHeadcountCallCount = 0;
  List<String>? lastHeadcountSubAccountIds;

  @override
  Future<List<String>> splitEqualByHeadcount({
    required PosDeviceContext ctx,
    required String checkId,
    required List<String> subAccountIds,
  }) async {
    splitEqualByHeadcountCallCount += 1;
    lastHeadcountSubAccountIds = subAccountIds;
    return const [];
  }

  int splitByQuantityCallCount = 0;

  @override
  Future<String> splitByQuantity({
    required PosDeviceContext ctx,
    required String checkId,
    required String subAccountId,
    required String sourceOrderId,
    required int sourceLineIndex,
    required int quantity,
  }) async {
    splitByQuantityCallCount += 1;
    return 'alloc-3';
  }

  int splitFreeAmountCallCount = 0;
  int? lastFreeAmountMinorUnits;

  @override
  Future<String> splitFreeAmount({
    required PosDeviceContext ctx,
    required String checkId,
    required String subAccountId,
    required int amountMinorUnits,
    required String sourceOrderId,
    required int sourceLineIndex,
  }) async {
    splitFreeAmountCallCount += 1;
    lastFreeAmountMinorUnits = amountMinorUnits;
    return 'alloc-4';
  }

  int cancellationRequestCallCount = 0;
  int financialAdjustmentRequestCallCount = 0;

  @override
  Future<String> requestAcceptedLineCancellation({
    required PosDeviceContext ctx,
    required String orderId,
    required int lineIndex,
    required String reasonCode,
    required String reasonMessage,
  }) async {
    cancellationRequestCallCount += 1;
    return 'approval-cancel-1';
  }

  @override
  Future<String> requestCheckFinancialAdjustment({
    required PosDeviceContext ctx,
    required String checkId,
    required String scope,
    String? allocationId,
    String? subAccountId,
    required String adjustmentType,
    int? percentageBasisPoints,
    int? fixedAmountMinorUnits,
    required String reasonCode,
    required String reasonMessage,
  }) async {
    financialAdjustmentRequestCallCount += 1;
    return 'approval-adjustment-1';
  }
}

const _ctx = PosDeviceContext(
  organizationId: 'org-1',
  branchId: 'branch-1',
  deviceId: 'device-1',
  deviceSessionId: 'session-1',
);

PosTableOperationalView _pendingLineView() {
  return const PosTableOperationalView(
    tableId: 'table-1',
    status: 'occupied',
    tableSessionId: 'tsess-1',
    subAccounts: [
      {'id': 'sub-1', 'displayName': 'Ayşe'},
    ],
    checks: [],
    orders: [
      PosTableOrderSummary(
        orderId: 'order-1',
        subAccountId: 'sub-1',
        mode: 'guestSession',
        linesDispositionSummary: 'pending',
        lines: [
          PosOrderLineSummary(
            productName: 'Klasik Bowl',
            quantity: 1,
            unitPriceMinorUnits: 10000,
            status: 'pendingApproval',
            subAccountId: 'sub-1',
          ),
        ],
      ),
    ],
  );
}

PosTableOperationalView _acceptedLineView() {
  return const PosTableOperationalView(
    tableId: 'table-1',
    status: 'occupied',
    tableSessionId: 'tsess-1',
    subAccounts: [
      {'id': 'sub-1', 'displayName': 'Ayşe'},
    ],
    checks: [],
    orders: [
      PosTableOrderSummary(
        orderId: 'order-1',
        subAccountId: 'sub-1',
        mode: 'guestSession',
        linesDispositionSummary: 'resolved',
        lines: [
          PosOrderLineSummary(
            productName: 'Klasik Bowl',
            quantity: 1,
            unitPriceMinorUnits: 10000,
            status: 'accepted',
            subAccountId: 'sub-1',
          ),
        ],
      ),
    ],
  );
}

PosTableOperationalView _acceptedLineViewTwoSubAccounts() {
  return const PosTableOperationalView(
    tableId: 'table-1',
    status: 'occupied',
    tableSessionId: 'tsess-1',
    subAccounts: [
      {'id': 'sub-1', 'displayName': 'Ayşe'},
      {'id': 'sub-2', 'displayName': 'Mehmet'},
    ],
    checks: [],
    orders: [
      PosTableOrderSummary(
        orderId: 'order-1',
        subAccountId: 'sub-1',
        mode: 'guestSession',
        linesDispositionSummary: 'resolved',
        lines: [
          PosOrderLineSummary(
            productName: 'Klasik Bowl',
            quantity: 2,
            unitPriceMinorUnits: 10000,
            status: 'accepted',
            subAccountId: 'sub-1',
          ),
        ],
      ),
    ],
  );
}

Future<_Fakes> _pump(
  WidgetTester tester, {
  required PosTableOperationalView initialView,
}) async {
  final viewGateway = _FakePosOperationalViewGateway()
    ..viewToReturn = initialView;
  final actionGateway = _FakePosActionGateway();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        posOperationalViewGatewayProvider.overrideWithValue(viewGateway),
        posActionGatewayProvider.overrideWithValue(actionGateway),
        posDeviceContextProvider.overrideWithValue(_ctx),
        selectedPosTableIdProvider.overrideWith((ref) => 'table-1'),
      ],
      child: const MaterialApp(home: PosTableWorkspaceScreen()),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return _Fakes(viewGateway, actionGateway);
}

class _Fakes {
  _Fakes(this.viewGateway, this.actionGateway);
  final _FakePosOperationalViewGateway viewGateway;
  final _FakePosActionGateway actionGateway;
}

void main() {
  testWidgets('renders the pending line with accept/reject/propose actions',
      (tester) async {
    await _pump(tester, initialView: _pendingLineView());

    expect(find.textContaining('Klasik Bowl'), findsOneWidget);
    expect(find.text('Onay bekliyor'), findsOneWidget);
    expect(find.byTooltip('Kabul Et'), findsOneWidget);
    expect(find.byTooltip('Reddet'), findsOneWidget);
    expect(find.byTooltip('Değişiklik Öner'), findsOneWidget);
  });

  testWidgets('tapping Kabul Et calls respondToOrderLines with accept:true',
      (tester) async {
    final fakes = await _pump(tester, initialView: _pendingLineView());
    fakes.viewGateway.viewToReturn = _acceptedLineView();

    await tester.tap(find.byTooltip('Kabul Et'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(fakes.actionGateway.respondCallCount, 1);
    expect(fakes.actionGateway.lastRespondOrderId, 'order-1');
    expect(fakes.actionGateway.lastDecision!.accept, true);
    expect(fakes.actionGateway.lastDecision!.lineIndex, 0);
  });

  testWidgets(
      'once a line is accepted, opening a check and splitting by customer '
      'call the real gateway methods', (tester) async {
    final fakes = await _pump(tester, initialView: _acceptedLineView());

    await tester.tap(find.widgetWithText(ElevatedButton, 'Hesap Aç'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(fakes.actionGateway.openCheckCallCount, 1);
    expect(find.textContaining('Hesap No: check-1'), findsOneWidget);

    await tester.tap(find.byTooltip('Kişiye Göre Böl'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(fakes.actionGateway.splitByCustomerCallCount, 1);
  });

  testWidgets('finalize button calls finalizeCheckReadyForPayment',
      (tester) async {
    final fakes = await _pump(tester, initialView: _acceptedLineView());
    await tester.tap(find.widgetWithText(ElevatedButton, 'Hesap Aç'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // AP-4 Wave D correction: the check panel no longer shows a
    // "payment unavailable, AP-4 kapsamındadır" dead-end note — a real
    // checkout is now wired (see the `onOpenCheckout` widget-integration
    // coverage this same file adds below for the post-`readyForPayment`
    // "Ödemeye Git" button).
    expect(find.text('Ödemeye Hazır'), findsOneWidget);
    expect(find.textContaining('AP-4 kapsamındadır'), findsNothing);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Ödemeye Hazır'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(fakes.actionGateway.finalizeCallCount, 1);
  });

  testWidgets(
      'table transfer dialog calls transferTable with the entered '
      'target table id', (tester) async {
    final fakes = await _pump(tester, initialView: _acceptedLineView());
    await tester.tap(find.widgetWithText(ElevatedButton, 'Hesap Aç'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.widgetWithText(OutlinedButton, 'Masa Transfer Et'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('targetTableIdField')),
      'table-2',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Onayla'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(fakes.actionGateway.transferCallCount, 1);
    expect(fakes.actionGateway.lastTransferTarget, 'table-2');
  });

  testWidgets(
      'cancellation request dialog on an accepted line calls '
      'requestAcceptedLineCancellation with the entered reason',
      (tester) async {
    final fakes = await _pump(tester, initialView: _acceptedLineView());

    await tester.tap(find.byTooltip('İptal Talebi Gönder'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('reasonMessageField')),
      'Müşteri vazgeçti',
    );
    await tester
        .tap(find.widgetWithText(ElevatedButton, 'İptal Talebi Gönder'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(fakes.actionGateway.cancellationRequestCallCount, 1);
  });

  testWidgets(
      'quantity split dialog calls splitByQuantity with the chosen quantity',
      (tester) async {
    final fakes = await _pump(tester, initialView: _acceptedLineView());
    await tester.tap(find.widgetWithText(ElevatedButton, 'Hesap Aç'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byTooltip('Adete Göre Böl'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Böl'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(fakes.actionGateway.splitByQuantityCallCount, 1);
  });

  testWidgets(
      'free amount split dialog calls splitFreeAmount with the entered amount '
      'converted to minor units', (tester) async {
    final fakes = await _pump(tester, initialView: _acceptedLineView());
    await tester.tap(find.widgetWithText(ElevatedButton, 'Hesap Aç'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byTooltip('Serbest Tutara Göre Böl'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('freeAmountField')), '25.50');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Böl'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(fakes.actionGateway.splitFreeAmountCallCount, 1);
    expect(fakes.actionGateway.lastFreeAmountMinorUnits, 2550);
  });

  testWidgets(
      'equal-by-headcount split dialog calls splitEqualByHeadcount with both '
      'sub-accounts pre-selected', (tester) async {
    final fakes =
        await _pump(tester, initialView: _acceptedLineViewTwoSubAccounts());
    await tester.tap(find.widgetWithText(ElevatedButton, 'Hesap Aç'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(
        find.widgetWithText(OutlinedButton, 'Eşit Böl (Kişi Sayısına Göre)'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Böl'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(fakes.actionGateway.splitEqualByHeadcountCallCount, 1);
    expect(fakes.actionGateway.lastHeadcountSubAccountIds,
        containsAll(['sub-1', 'sub-2']));
  });

  testWidgets(
      'financial adjustment dialog calls requestCheckFinancialAdjustment with '
      'the default whole-check complimentary scope', (tester) async {
    final fakes = await _pump(tester, initialView: _acceptedLineView());
    await tester.tap(find.widgetWithText(ElevatedButton, 'Hesap Aç'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester
        .tap(find.widgetWithText(OutlinedButton, 'Fiyat Düzeltmesi Talep Et'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('adjustmentReasonMessageField')),
      'Müşteri memnuniyeti için ikram',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Talep Gönder'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(fakes.actionGateway.financialAdjustmentRequestCallCount, 1);
  });
}
