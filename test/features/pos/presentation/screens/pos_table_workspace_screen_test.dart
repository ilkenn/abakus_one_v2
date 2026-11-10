import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abakus_one_v2/features/menu/domain/models/menu_product.dart';
import 'package:abakus_one_v2/features/menu/domain/models/sale_unit.dart';
import 'package:abakus_one_v2/features/menu/presentation/providers/menu_catalog_provider.dart';
import 'package:abakus_one_v2/features/pos/data/kitchen_projection_repository.dart';
import 'package:abakus_one_v2/features/pos/data/pos_action_gateway.dart';
import 'package:abakus_one_v2/features/pos/data/pos_operational_view_gateway.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/actor_session.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/staff_role.dart';
import 'package:abakus_one_v2/features/pos/domain/kds/kitchen_line_status.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/actor_session_provider.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/kds_dependencies_provider.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/pos_workspace_providers.dart';
import 'package:abakus_one_v2/features/pos/presentation/screens/pos_table_workspace_screen.dart';

import '../../test_support/kds_test_fixtures.dart';

class _FakePosOperationalViewGateway implements PosOperationalViewGateway {
  PosTableOperationalView? viewToReturn;
  int callCount = 0;

  /// Empty by default — a realistic "no accepted orders in the lookback
  /// window yet" branch, so the default "Çok Tercih Edilenler" view renders
  /// the fixed showcase fallback rather than throwing for every test that
  /// doesn't specifically exercise this (most switch to another category
  /// tab immediately anyway).
  List<PosTopSellingProduct> topSellingProductsToReturn = const [];
  Object? topSellingProductsError;

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

  /// A couple of other tables by default, so the target-table picker
  /// (2026-11-04) has something real to show without every test needing
  /// to set this up itself.
  PosBranchOverviewPage branchOverviewToReturn = const PosBranchOverviewPage(
    tables: [
      PosBranchTableSummary(
        tableId: 'table-2',
        displayName: 'Masa 2',
        status: 'available',
        activeTableSessionId: null,
        pendingQrLineCount: 0,
      ),
      PosBranchTableSummary(
        tableId: 'table-3',
        displayName: 'Masa 3',
        status: 'occupied',
        activeTableSessionId: 'tsess-other',
        pendingQrLineCount: 0,
      ),
    ],
    nextCursor: null,
    version: 'v1',
    unchanged: false,
  );

  @override
  Future<PosBranchOverviewPage> getBranchOverview({
    required String organizationId,
    required String branchId,
    required String deviceId,
    required String deviceSessionId,
    String? cursor,
    String? ifNoneMatchVersion,
  }) async =>
      branchOverviewToReturn;

  @override
  Future<List<PosTopSellingProduct>> getTopSellingProducts({
    required String organizationId,
    required String branchId,
    required String deviceId,
    required String deviceSessionId,
  }) async {
    final error = topSellingProductsError;
    if (error != null) throw error;
    return topSellingProductsToReturn;
  }
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
  Future<void> resolveServiceRequest({
    required PosDeviceContext ctx,
    required String requestId,
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

  int submitStaffEntryOrderCallCount = 0;
  Map<String, dynamic>? lastStaffEntrySelection;
  List<Map<String, dynamic>>? lastStaffEntryItems;
  Object? staffEntryError;

  @override
  Future<String> submitStaffEntryOrder({
    required PosDeviceContext ctx,
    required String tableId,
    required Map<String, dynamic> subAccountSelection,
    required List<Map<String, dynamic>> items,
  }) async {
    submitStaffEntryOrderCallCount += 1;
    lastStaffEntrySelection = subAccountSelection;
    lastStaffEntryItems = items;
    final error = staffEntryError;
    if (error != null) throw error;
    return 'order-staff-1';
  }

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
  Future<AcceptedLineCancellationResult> requestAcceptedLineCancellation({
    required PosDeviceContext ctx,
    required String orderId,
    required int lineIndex,
    required String reasonCode,
    required String reasonMessage,
  }) async {
    cancellationRequestCallCount += 1;
    final gate = cancellationGate;
    if (gate != null) await gate.future;
    return AcceptedLineCancellationResult(
      cancellationRequestId: 'cancel-req-1',
      applied: cancellationAppliesDirectly,
      approvalRequestId:
          cancellationAppliesDirectly ? null : 'approval-cancel-1',
    );
  }

  /// ADR-066 — what the fake backend reports: `true` simulates a
  /// manager-tier caller (applied immediately).
  bool cancellationAppliesDirectly = false;

  /// When set, `requestAcceptedLineCancellation` stays in flight until this
  /// completes — simulates a slow backend for the double-tap test.
  Completer<void>? cancellationGate;

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
  KitchenProjectionRepository? kitchenRepo,
  List<Override> extraOverrides = const [],
}) async {
  final viewGateway = _FakePosOperationalViewGateway()
    ..viewToReturn = initialView;
  final actionGateway = _FakePosActionGateway();
  final kitchenRepository =
      kitchenRepo ?? InMemoryKitchenProjectionRepository();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        posOperationalViewGatewayProvider.overrideWithValue(viewGateway),
        posActionGatewayProvider.overrideWithValue(actionGateway),
        posDeviceContextProvider.overrideWithValue(_ctx),
        selectedPosTableIdProvider.overrideWith((ref) => 'table-1'),
        kitchenProjectionRepositoryProvider
            .overrideWithValue(kitchenRepository),
        ...extraOverrides,
      ],
      child: const MaterialApp(home: PosTableWorkspaceScreen()),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return _Fakes(viewGateway, actionGateway, kitchenRepository);
}

class _Fakes {
  _Fakes(this.viewGateway, this.actionGateway, this.kitchenRepository);
  final _FakePosOperationalViewGateway viewGateway;
  final _FakePosActionGateway actionGateway;
  final KitchenProjectionRepository kitchenRepository;
}

/// Opens the real check (ElevatedButton 'Hesap Aç', present whenever no
/// check is open yet) and then the "İşlemler" tools sheet — the common
/// setup every split/discount test below needs, now that those actions
/// live behind the "... Diğer" grid modal's "Hesabı Böl" tile instead of
/// being always-visible (2026-11-04 redesign, replacing the old flat
/// "İşlemler" sheet).
Future<void> _openCheckThenSplitSheet(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(ElevatedButton, 'Hesap Aç'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tap(find.widgetWithText(ElevatedButton, '... Diğer'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Hesabı Böl'));
  await tester.pumpAndSettle();
}

void main() {
  group('Onay Bekleyen Siparişler sheet (pending customer-line review)', () {
    // 2026-10-31 — relocated behind a badge/sheet (product owner's explicit
    // choice) instead of always-visible; `_OrderCard`/`_LineRow` themselves
    // are reused unchanged, so the actual accept/reject/propose behavior
    // and tooltips are identical to before the redesign.
    testWidgets(
        'a pending line shows the badge; opening it shows accept/reject/propose',
        (tester) async {
      await _pump(tester, initialView: _pendingLineView());

      expect(find.text('Onay Bekleyen Sipariş: 1'), findsOneWidget);
      await tester.tap(find.text('Onay Bekleyen Sipariş: 1'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Klasik Bowl'), findsWidgets);
      expect(find.text('Onay bekliyor'), findsOneWidget);
      expect(find.byTooltip('Kabul Et'), findsOneWidget);
      expect(find.byTooltip('Reddet'), findsOneWidget);
      expect(find.byTooltip('Değişiklik Öner'), findsOneWidget);
    });

    testWidgets(
        'tapping Kabul Et inside the sheet calls respondToOrderLines with accept:true',
        (tester) async {
      final fakes = await _pump(tester, initialView: _pendingLineView());

      await tester.tap(find.text('Onay Bekleyen Sipariş: 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Kabul Et'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(fakes.actionGateway.respondCallCount, 1);
      expect(fakes.actionGateway.lastRespondOrderId, 'order-1');
      expect(fakes.actionGateway.lastDecision!.accept, true);
      expect(fakes.actionGateway.lastDecision!.lineIndex, 0);
    });
  });

  group('Adisyon panel — accepted lines render directly', () {
    testWidgets('an accepted line shows inline with a cancel-request icon',
        (tester) async {
      await _pump(tester, initialView: _acceptedLineView());

      expect(find.textContaining('Klasik Bowl'), findsOneWidget);
      expect(find.byTooltip('İptal Talebi Gönder'), findsOneWidget);
    });

    testWidgets(
        'cancellation request dialog calls requestAcceptedLineCancellation '
        'with the entered reason', (tester) async {
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
  });

  group(
      'Payment button state machine — Hesap Aç -> Ödemeye Hazırla -> Ödeme Al',
      () {
    testWidgets('Hesap Aç opens the check and advances the button label',
        (tester) async {
      final fakes = await _pump(tester, initialView: _acceptedLineView());

      await tester.tap(find.widgetWithText(ElevatedButton, 'Hesap Aç'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(fakes.actionGateway.openCheckCallCount, 1);
      expect(find.widgetWithText(ElevatedButton, 'Ödemeye Hazırla'),
          findsOneWidget);
    });

    testWidgets('Ödemeye Hazırla calls finalizeCheckReadyForPayment',
        (tester) async {
      final fakes = await _pump(tester, initialView: _acceptedLineView());
      await tester.tap(find.widgetWithText(ElevatedButton, 'Hesap Aç'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.widgetWithText(ElevatedButton, 'Ödemeye Hazırla'));
      // Adım 3 (2026-11-06) — "Ödemeye Hazırla" now opens a "Tek Hesap
      // Olarak Öde" / "Parçalı Öde" choice sheet first; pumpAndSettle lets
      // the sheet's entrance animation finish before tapping into it.
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tek Hesap Olarak Öde'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(fakes.actionGateway.finalizeCallCount, 1);
    });

    testWidgets(
        'Ödemeye Hazırla with zero existing allocations auto-creates one '
        'per accepted line before finalizing (backend rejects a bare '
        'finalize otherwise)', (tester) async {
      final fakes = await _pump(tester, initialView: _acceptedLineView());
      await tester.tap(find.widgetWithText(ElevatedButton, 'Hesap Aç'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.widgetWithText(ElevatedButton, 'Ödemeye Hazırla'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tek Hesap Olarak Öde'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // _acceptedLineView has exactly one accepted line and no
      // allocations — one real splitByProduct call, then finalize.
      expect(fakes.actionGateway.splitByProductCallCount, 1);
      expect(fakes.actionGateway.finalizeCallCount, 1);
    });

    testWidgets(
        'Ödemeye Hazırla with an already-active allocation never creates '
        'a redundant one', (tester) async {
      const viewWithAllocation = PosTableOperationalView(
        tableId: 'table-1',
        status: 'occupied',
        tableSessionId: 'tsess-1',
        subAccounts: [
          {'id': 'sub-1', 'displayName': 'Ayşe'},
        ],
        checks: [],
        allocations: [
          PosCheckAllocationSummary(
            id: 'alloc-1',
            subAccountId: 'sub-1',
            status: 'active',
            allocatedAmountMinorUnits: 10000,
          ),
        ],
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
      final fakes = await _pump(tester, initialView: viewWithAllocation);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Hesap Aç'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.widgetWithText(ElevatedButton, 'Ödemeye Hazırla'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tek Hesap Olarak Öde'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(fakes.actionGateway.splitByProductCallCount, 0);
      expect(fakes.actionGateway.finalizeCallCount, 1);
    });
  });

  group('Parçalı Öde (Adım 3, 2026-11-06) — "Ödemeye Hazırla" seçim sayfası',
      () {
    testWidgets(
        'Esit Bolusum: en az 2 hesap secilmeden "Böl" butonu devre disi kalir',
        (tester) async {
      await _pump(tester, initialView: _acceptedLineViewTwoSubAccounts());
      await tester.tap(find.widgetWithText(ElevatedButton, 'Hesap Aç'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Ödemeye Hazırla'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Parçalı Öde'));
      await tester.pumpAndSettle();

      expect(find.text('Eşit Bölüşüm'), findsWidgets);
      final confirmButton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Böl'),
      );
      expect(confirmButton.onPressed, isNull,
          reason: 'henüz hiçbir hesap seçilmedi');

      await tester.tap(find.text('Ayşe'));
      await tester.pump();
      final stillDisabled = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Böl'),
      );
      expect(stillDisabled.onPressed, isNull,
          reason: 'sadece 1 hesap seçili, en az 2 gerekiyor');

      await tester.tap(find.text('Mehmet'));
      await tester.pump();
      final enabled = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Böl'),
      );
      expect(enabled.onPressed, isNotNull);
    });

    testWidgets(
        'Esit Bolusum onaylaninca splitEqualByHeadcount secilen hesaplarla '
        'cagrilir, sonra finalize edilir', (tester) async {
      final fakes =
          await _pump(tester, initialView: _acceptedLineViewTwoSubAccounts());
      await tester.tap(find.widgetWithText(ElevatedButton, 'Hesap Aç'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Ödemeye Hazırla'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Parçalı Öde'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ayşe'));
      await tester.tap(find.text('Mehmet'));
      await tester.pump();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Böl'));
      await tester.pumpAndSettle();

      expect(fakes.actionGateway.splitEqualByHeadcountCallCount, 1);
      expect(fakes.actionGateway.lastHeadcountSubAccountIds,
          unorderedEquals(['sub-1', 'sub-2']));
      expect(fakes.actionGateway.finalizeCallCount, 1);
    });

    testWidgets(
        'Kalem Secimi onaylaninca secili her satir icin splitByProduct '
        'hedef hesaba cagrilir, sonra finalize edilir', (tester) async {
      final fakes =
          await _pump(tester, initialView: _acceptedLineViewTwoSubAccounts());
      await tester.tap(find.widgetWithText(ElevatedButton, 'Hesap Aç'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Ödemeye Hazırla'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Parçalı Öde'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Kalem Seçimi'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining('Klasik Bowl'),
      ));
      await tester.pump();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mehmet').last);
      await tester.pumpAndSettle();

      final confirm = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Böl'),
      );
      expect(confirm.onPressed, isNotNull);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Böl'));
      await tester.pumpAndSettle();

      expect(fakes.actionGateway.splitByProductCallCount, 1);
      expect(fakes.actionGateway.finalizeCallCount, 1);
    });
  });

  group(
      '"... Diğer" grid modal — split / headcount / discount / transfer '
      '(2026-11-04 redesign)', () {
    testWidgets('Kişiye Göre Böl calls splitByCustomer', (tester) async {
      final fakes = await _pump(tester, initialView: _acceptedLineView());
      await _openCheckThenSplitSheet(tester);

      await tester.tap(find.byTooltip('Kişiye Göre Böl'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(fakes.actionGateway.splitByCustomerCallCount, 1);
    });

    testWidgets(
        '"Taşı" quick-action button opens a status-aware table picker — '
        'tapping a target table confirms the transfer immediately, no '
        'manual id entry, reachable with no check open at all', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final fakes = await _pump(tester, initialView: _acceptedLineView());

      // No "Hesap Aç" tap — "Taşı" must stay reachable regardless of check
      // status (BR-POS-002), confirmed by never opening a check here.
      await tester.tap(find.widgetWithText(ElevatedButton, 'Taşı'));
      await tester.pumpAndSettle();

      expect(find.text('Masa 2'), findsOneWidget);
      expect(find.text('Boş'), findsOneWidget);
      expect(find.text('Masa 3'), findsOneWidget);
      expect(find.text('Dolu'), findsOneWidget);
      await tester.tap(find.text('Masa 2'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(fakes.actionGateway.transferCallCount, 1);
      expect(fakes.actionGateway.lastTransferTarget, 'table-2');
    });

    testWidgets(
        'the current table itself renders disabled ("Bu Masa") in the '
        'picker — it can never be its own transfer target', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final fakes = await _pump(tester, initialView: _acceptedLineView());
      fakes.viewGateway.branchOverviewToReturn = PosBranchOverviewPage(
        tables: [
          const PosBranchTableSummary(
            tableId: 'table-1',
            displayName: 'Masa 1',
            status: 'occupied',
            activeTableSessionId: 'tsess-1',
            pendingQrLineCount: 0,
          ),
          ...fakes.viewGateway.branchOverviewToReturn.tables,
        ],
        nextCursor: null,
        version: 'v1',
        unchanged: false,
      );

      await tester.tap(find.widgetWithText(ElevatedButton, 'Taşı'));
      await tester.pumpAndSettle();

      expect(find.text('Bu Masa'), findsOneWidget);
      await tester.tap(find.text('Masa 1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(fakes.actionGateway.transferCallCount, 0,
          reason: 'tapping the disabled self-tile must not transfer');
    });

    testWidgets(
        '"Masa Taşıma" grid tile opens the exact same table picker as the '
        'quick-action "Taşı" button', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final fakes = await _pump(tester, initialView: _acceptedLineView());

      await tester.tap(find.widgetWithText(ElevatedButton, '... Diğer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Masa Taşıma'));
      await tester.pumpAndSettle();

      expect(find.text('Masa 3'), findsOneWidget);
      await tester.tap(find.text('Masa 3'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(fakes.actionGateway.transferCallCount, 1);
      expect(fakes.actionGateway.lastTransferTarget, 'table-3');
    });

    testWidgets(
        'quantity split dialog calls splitByQuantity with the chosen quantity',
        (tester) async {
      final fakes = await _pump(tester, initialView: _acceptedLineView());
      await _openCheckThenSplitSheet(tester);

      await tester.tap(find.byTooltip('Adete Göre Böl'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Böl'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(fakes.actionGateway.splitByQuantityCallCount, 1);
    });

    testWidgets(
        'free amount split dialog calls splitFreeAmount with the entered '
        'amount converted to minor units', (tester) async {
      final fakes = await _pump(tester, initialView: _acceptedLineView());
      await _openCheckThenSplitSheet(tester);

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
        'equal-by-headcount split dialog calls splitEqualByHeadcount with '
        'both sub-accounts pre-selected', (tester) async {
      final fakes =
          await _pump(tester, initialView: _acceptedLineViewTwoSubAccounts());
      await _openCheckThenSplitSheet(tester);

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
        'financial adjustment dialog calls requestCheckFinancialAdjustment '
        'with the default whole-check complimentary scope', (tester) async {
      final fakes = await _pump(tester, initialView: _acceptedLineView());
      await _openCheckThenSplitSheet(tester);

      await tester.tap(
          find.widgetWithText(OutlinedButton, 'Fiyat Düzeltmesi Talep Et'));
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

    testWidgets(
        'disabled tiles (e.g. "Grup Oluştur") show a "(Yakında)" label and '
        'are never tappable', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pump(tester, initialView: _acceptedLineView());

      await tester.tap(find.widgetWithText(ElevatedButton, '... Diğer'));
      await tester.pumpAndSettle();

      expect(find.text('Grup Oluştur (Yakında)'), findsOneWidget);
      expect(find.text('Stoğu Biten Ürünler (Yakında)'), findsOneWidget);
    });

    testWidgets('"Hesabı Göster" tile is disabled with no check open',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pump(tester, initialView: _acceptedLineView());

      await tester.tap(find.widgetWithText(ElevatedButton, '... Diğer'));
      await tester.pumpAndSettle();

      expect(find.text('Hesabı Göster (Yakında)'), findsOneWidget);
    });

    testWidgets(
        '"Hesabı Göster" tile becomes enabled once a check exists, and its '
        'dialog handles a PaymentGateway failure gracefully', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pump(tester, initialView: _acceptedLineView());
      await tester.tap(find.widgetWithText(ElevatedButton, 'Hesap Aç'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.widgetWithText(ElevatedButton, '... Diğer'));
      await tester.pumpAndSettle();
      expect(find.text('Hesabı Göster'), findsOneWidget);

      await tester.tap(find.text('Hesabı Göster'));
      await tester.pumpAndSettle();

      // No PaymentGateway override exists in this fake harness, so this
      // resolves to the real Unavailable fallback — confirming the dialog
      // handles that failure gracefully rather than crashing.
      expect(find.text('Hesap Görüntülenemedi'), findsOneWidget);
    });
  });

  group('Çoklu seçim ve toplu iptal (2026-11-04 redesign)', () {
    testWidgets(
        'checking an accepted line shows the "1 Seçili" badge and enables '
        'the bulk-cancel trash icon', (tester) async {
      await _pump(tester, initialView: _acceptedLineView());

      expect(find.text('1 Seçili'), findsNothing);
      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();

      expect(find.text('1 Seçili'), findsOneWidget);
      final trash = tester.widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.delete_outline));
      expect(trash.onPressed, isNotNull);
    });

    testWidgets(
        'tapping the trash icon with a line selected requests cancellation '
        'for that line', (tester) async {
      final fakes = await _pump(tester, initialView: _acceptedLineView());

      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();
      await tester.tap(find.widgetWithIcon(IconButton, Icons.delete_outline));
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
        'the big payment button shows the whole table\'s total once the '
        'check is already ready for payment', (tester) async {
      // A view whose check is already `readyForPayment` (status: 'occupied'
      // alone can't express this — the fake gateway never transitions a
      // check's status after `finalize`, so this is set up directly
      // instead of tapping through "Hesap Aç" → "Ödemeye Hazırla").
      const readyView = PosTableOperationalView(
        tableId: 'table-1',
        status: 'occupied',
        tableSessionId: 'tsess-1',
        subAccounts: [
          {'id': 'sub-1', 'displayName': 'Ayşe'},
        ],
        checks: [
          {'id': 'check-1', 'status': 'readyForPayment'},
        ],
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
      await _pump(tester, initialView: readyView);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Hesap Aç'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // The fake's default checkIdToReturn ('check-1') matches the check
      // above, so widget.checkId now resolves its real status.
      expect(find.widgetWithText(ElevatedButton, 'Ödeme Al: 100 ₺'),
          findsOneWidget);
    });
  });

  // 2026-09-28 — KDS & POS Çift Yönlü Entegrasyon: a live, order-level
  // kitchen-readiness badge, so staff can see prep status without walking
  // to the physical KDS screen. Order-level only (not per-line) —
  // `PosOrderLineSummary` has no stable per-line id. 2026-10-31 redesign:
  // still rendered directly above an order's accepted lines in the main
  // adisyon panel (never behind a sheet) — these three cases are
  // unchanged by the redesign.
  group('kitchen status badge', () {
    testWidgets('no kitchen work items for the order shows no badge',
        (tester) async {
      await _pump(tester, initialView: _acceptedLineView());

      expect(find.textContaining('hazır'), findsNothing);
      expect(find.text('Hazır'), findsNothing);
    });

    testWidgets('some ready, some not shows the "X/Y hazır" badge',
        (tester) async {
      final kitchenRepo = InMemoryKitchenProjectionRepository();
      await kitchenRepo.createInitial(buildTestKitchenWorkItem(
        workItemId: 'w1',
        kitchenTicketLineId: 'ticket-1-line-0',
        orderId: 'order-1',
        status: KitchenLineStatus.ready,
        quantity: 1,
        readyQuantity: 1,
      ));
      await kitchenRepo.createInitial(buildTestKitchenWorkItem(
        workItemId: 'w2',
        kitchenTicketLineId: 'ticket-1-line-1',
        orderId: 'order-1',
        status: KitchenLineStatus.preparing,
        quantity: 1,
        readyQuantity: 0,
      ));

      await _pump(tester,
          initialView: _acceptedLineView(), kitchenRepo: kitchenRepo);

      expect(find.text('1/2 hazır'), findsOneWidget);
    });

    testWidgets('every line ready shows the "Hazır" badge', (tester) async {
      final kitchenRepo = InMemoryKitchenProjectionRepository();
      await kitchenRepo.createInitial(buildTestKitchenWorkItem(
        workItemId: 'w1',
        kitchenTicketLineId: 'ticket-1-line-0',
        orderId: 'order-1',
        status: KitchenLineStatus.ready,
        quantity: 1,
        readyQuantity: 1,
      ));
      await kitchenRepo.createInitial(buildTestKitchenWorkItem(
        workItemId: 'w2',
        kitchenTicketLineId: 'ticket-1-line-1',
        orderId: 'order-1',
        status: KitchenLineStatus.ready,
        quantity: 1,
        readyQuantity: 1,
      ));

      await _pump(tester,
          initialView: _acceptedLineView(), kitchenRepo: kitchenRepo);

      expect(find.text('Hazır'), findsOneWidget);
    });
  });

  group('Personel Ürün Girişi — category/grid/cart POS entry (2026-10-31)', () {
    PosTableOperationalView emptyOpenTableView() {
      return const PosTableOperationalView(
        tableId: 'table-1',
        status: 'occupied',
        tableSessionId: 'tsess-1',
        subAccounts: [],
        checks: [],
        orders: [],
      );
    }

    testWidgets(
        'the category rail and product grid are visible immediately — no '
        'button needed, never the old single-item dropdown', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pump(tester, initialView: emptyOpenTableView());

      expect(find.text('İçecekler'), findsOneWidget);
      // The default "Tümü" filter has ~190 products across every active
      // category — CocaCola Şişe isn't necessarily within the grid's
      // initially-built range without first narrowing the filter.
      await tester.tap(find.text('İçecekler'));
      await tester.pump();
      expect(find.text('CocaCola Şişe'), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<MenuProduct>), findsNothing);
      expect(find.text('Ürün Ekle (Personel)'), findsNothing);
    });

    testWidgets(
        'tapping a product card twice accumulates quantity 2 in the cart, '
        'and Siparişi Onayla submits both units in one call', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final fakes = await _pump(tester, initialView: emptyOpenTableView());

      // Filter to "İçecekler" (8 products, vs. ~190 under "Tümü").
      await tester.tap(find.text('İçecekler'));
      await tester.pump();

      // Scoped to the grid specifically: once a line exists, the cart
      // section ALSO shows "CocaCola Şişe" as its line label, so a bare
      // `find.text(...)` becomes ambiguous after the first tap.
      final cocaColaCard = find.descendant(
        of: find.byType(GridView),
        matching: find.text('CocaCola Şişe'),
      );
      await tester.ensureVisible(cocaColaCard);
      await tester.tap(cocaColaCard);
      await tester.pump();
      await tester.tap(cocaColaCard);
      await tester.pump();

      expect(find.text('2'), findsOneWidget);
      expect(find.text('160 TL'), findsOneWidget);

      // No account-selection step first — "Masa Geneli" is the default
      // target the compact dropdown starts on, satisfying the redesign's
      // "tek dokunuşla anında sepete eklenmeli" requirement without a
      // blocking step before the first tap.
      await tester.tap(find.byKey(const Key('confirmStaffEntryOrderButton')));
      await tester.pumpAndSettle();

      expect(fakes.actionGateway.submitStaffEntryOrderCallCount, 1);
      expect(fakes.actionGateway.lastStaffEntrySelection,
          {'mode': 'staffGeneral'});
      expect(fakes.actionGateway.lastStaffEntryItems, [
        {
          'kind': 'product',
          'productId': 'prod_cocacola',
          'quantity': 2,
          'selectedModifiers': <Map<String, String>>[],
          'note': '',
          'excludedIngredients': <String>[],
        },
      ]);
    });

    testWidgets(
        'the send-cart button only appears once the cart has at least one '
        'line', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pump(tester, initialView: emptyOpenTableView());

      expect(
          find.byKey(const Key('confirmStaffEntryOrderButton')), findsNothing,
          reason: 'the whole send-cart section is hidden while empty');

      await tester.tap(find.text('İçecekler'));
      await tester.pump();
      final cocaColaCard = find.descendant(
        of: find.byType(GridView),
        matching: find.text('CocaCola Şişe'),
      );
      await tester.ensureVisible(cocaColaCard);
      await tester.tap(cocaColaCard);
      await tester.pump();

      expect(find.byKey(const Key('confirmStaffEntryOrderButton')),
          findsOneWidget);
    });
  });

  group('Ürün arama çubuğu (2026-11-03)', () {
    PosTableOperationalView emptyOpenTableView() {
      return const PosTableOperationalView(
        tableId: 'table-1',
        status: 'occupied',
        tableSessionId: 'tsess-1',
        subAccounts: [],
        checks: [],
        orders: [],
      );
    }

    testWidgets(
        'typing a name filters the grid to matching products across every '
        'category, live as each letter is typed', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pump(tester, initialView: emptyOpenTableView());

      // A non-empty search overrides the selected category/Top-20 filter
      // entirely (default state here, "Çok Tercih Edilenler") — CocaCola
      // Şişe should surface regardless of which tab happens to be selected.
      await tester.enterText(
          find.byKey(const Key('productSearchField')), 'cocacola');
      await tester.pump();

      final grid = find.byType(GridView);
      expect(find.descendant(of: grid, matching: find.text('CocaCola Şişe')),
          findsOneWidget);
      expect(
        find.descendant(of: grid, matching: find.text('Tatlı Ekşi Tavuk Bowl')),
        findsNothing,
        reason: 'a non-matching product must be filtered out',
      );
    });

    testWidgets(
        'clearing the search field restores the selected category\'s own '
        'grid (not a search result)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pump(tester, initialView: emptyOpenTableView());

      await tester.tap(find.text("Bowl'lar"));
      await tester.pump();
      await tester.enterText(
          find.byKey(const Key('productSearchField')), 'cocacola');
      await tester.pump();
      final gridWhileSearching = find.byType(GridView);
      expect(
        find.descendant(
            of: gridWhileSearching,
            matching: find.text('Tatlı Ekşi Tavuk Bowl')),
        findsNothing,
        reason: 'searching must override the Bowl category filter',
      );

      await tester.tap(find.byIcon(Icons.clear_rounded));
      await tester.pump();

      final grid = find.byType(GridView);
      expect(
        find.descendant(of: grid, matching: find.text('Tatlı Ekşi Tavuk Bowl')),
        findsOneWidget,
        reason: "clearing search must restore the Bowl'lar category grid",
      );
    });
  });

  group('Barkod okuyucu (Adım 4, 2026-11-07)', () {
    PosTableOperationalView emptyOpenTableView() {
      return const PosTableOperationalView(
        tableId: 'table-1',
        status: 'occupied',
        tableSessionId: 'tsess-1',
        subAccounts: [],
        checks: [],
        orders: [],
      );
    }

    const barcodedProduct = MenuProduct(
      id: 'prod_test_barcoded',
      categoryId: 'cat_test',
      name: 'Test Ürünü',
      description: 'Test açıklaması',
      basePrice: 50,
      imageKey: 'placeholder',
      barcode: '8690123456789',
    );

    List<Override> productOverrides() => [
          menuProductsProvider.overrideWithValue(const [barcodedProduct]),
        ];

    testWidgets(
        'eslesen bir barkod Enter ile gonderilince urun tek tikla sepete '
        'eklenir ve arama kutusu temizlenir', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pump(tester,
          initialView: emptyOpenTableView(),
          extraOverrides: productOverrides());

      await tester.enterText(
          find.byKey(const Key('productSearchField')), '8690123456789');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(
          find.byKey(const Key('confirmStaffEntryOrderButton')), findsOneWidget,
          reason: 'barkod eslesmesi urunu tek adimda sepete eklemeli');
      final searchField =
          tester.widget<TextField>(find.byKey(const Key('productSearchField')));
      expect(searchField.controller!.text, isEmpty);
    });

    testWidgets(
        'eslesmeyen bir barkod sepete hicbir sey eklemez ve hata metni '
        'gosterir', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pump(tester,
          initialView: emptyOpenTableView(),
          extraOverrides: productOverrides());

      await tester.enterText(
          find.byKey(const Key('productSearchField')), '0000000000000');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(
          find.byKey(const Key('confirmStaffEntryOrderButton')), findsNothing);
      expect(find.textContaining('Barkod bulunamadı'), findsOneWidget);
    });
  });

  group('Tartılı ürün gramaj girişi (Adım 4, 2026-11-07)', () {
    PosTableOperationalView emptyOpenTableView() {
      return const PosTableOperationalView(
        tableId: 'table-1',
        status: 'occupied',
        tableSessionId: 'tsess-1',
        subAccounts: [],
        checks: [],
        orders: [],
      );
    }

    const weighedProduct = MenuProduct(
      id: 'prod_test_tartili',
      categoryId: 'cat_test',
      name: 'Tartılı Test Ürünü',
      description: 'Test açıklaması',
      basePrice: 200,
      imageKey: 'placeholder',
      saleUnit: SaleUnit.kilogram,
    );

    testWidgets(
        'kg bazli urune dokununca Gramaj modali acilir; onaylanana kadar '
        'sepete hicbir sey eklenmez', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pump(tester, initialView: emptyOpenTableView(), extraOverrides: [
        menuProductsProvider.overrideWithValue(const [weighedProduct]),
      ]);

      await tester.enterText(
          find.byKey(const Key('productSearchField')), 'Tartılı Test');
      await tester.pump();
      await tester.tap(find.text('Tartılı Test Ürünü'));
      await tester.pump();

      expect(find.text('Gramaj / Miktar Girin'), findsOneWidget);
      expect(
          find.byKey(const Key('confirmStaffEntryOrderButton')), findsNothing,
          reason: 'gramaj onaylanmadan sepete satir eklenmemeli');
    });

    testWidgets(
        'gramaj girilince tahmini tutar hesaplanir, Kapat sepete bir sey '
        'eklemeden modali kapatir', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pump(tester, initialView: emptyOpenTableView(), extraOverrides: [
        menuProductsProvider.overrideWithValue(const [weighedProduct]),
      ]);

      await tester.enterText(
          find.byKey(const Key('productSearchField')), 'Tartılı Test');
      await tester.pump();
      await tester.tap(find.text('Tartılı Test Ürünü'));
      await tester.pump();

      await tester.enterText(find.byKey(const Key('weightGramsField')), '500');
      await tester.pump();

      expect(find.textContaining('Tahmini Tutar: 100.00 TL'), findsOneWidget);

      await tester.tap(find.byKey(const Key('closeWeightEntryDialogButton')));
      await tester.pump();

      expect(find.text('Gramaj / Miktar Girin'), findsNothing);
      expect(
          find.byKey(const Key('confirmStaffEntryOrderButton')), findsNothing);
    });

    testWidgets('"Teraziden Oku" bagli terazi yoksa dürüst mesaj gosterir',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pump(tester, initialView: emptyOpenTableView(), extraOverrides: [
        menuProductsProvider.overrideWithValue(const [weighedProduct]),
      ]);

      await tester.enterText(
          find.byKey(const Key('productSearchField')), 'Tartılı Test');
      await tester.pump();
      await tester.tap(find.text('Tartılı Test Ürünü'));
      await tester.pump();

      await tester.tap(find.byKey(const Key('readFromScaleButton')));
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('Bağlı seri port terazi bulunamadı'),
          findsOneWidget);
    });

    // ADR-067 (2026-11-09) — the weight now becomes a real cart line.
    testWidgets(
        '"1,5 kg" girilip Sepete Ekle denince satir gramajla eklenir ve '
        'Siparisi Onayla weightGrams ile gonderir', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final fakes = await _pump(tester,
          initialView: emptyOpenTableView(),
          extraOverrides: [
            menuProductsProvider.overrideWithValue(const [weighedProduct]),
          ]);

      await tester.enterText(
          find.byKey(const Key('productSearchField')), 'Tartılı Test');
      await tester.pump();
      await tester.tap(find.text('Tartılı Test Ürünü'));
      await tester.pump();

      await tester.enterText(
          find.byKey(const Key('weightGramsField')), '1,5 kg');
      await tester.pump();
      expect(find.textContaining('1,5 kg · Tahmini Tutar: 300.00 TL'),
          findsOneWidget);

      await tester.tap(find.byKey(const Key('confirmWeightEntryButton')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('cartLineWeight')), findsOneWidget);
      expect(find.text('1,5 kg'), findsOneWidget);

      await tester.tap(find.byKey(const Key('confirmStaffEntryOrderButton')));
      await tester.pumpAndSettle();

      expect(fakes.actionGateway.submitStaffEntryOrderCallCount, 1);
      final item = fakes.actionGateway.lastStaffEntryItems!.single;
      expect(item['productId'], 'prod_test_tartili');
      expect(item['quantity'], 1);
      expect(item['weightGrams'], 1500);
    });

    testWidgets('gecersiz gramajda Sepete Ekle pasif kalir ve hata gosterilir',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pump(tester, initialView: emptyOpenTableView(), extraOverrides: [
        menuProductsProvider.overrideWithValue(const [weighedProduct]),
      ]);

      await tester.enterText(
          find.byKey(const Key('productSearchField')), 'Tartılı Test');
      await tester.pump();
      await tester.tap(find.text('Tartılı Test Ürünü'));
      await tester.pump();

      await tester.enterText(
          find.byKey(const Key('weightGramsField')), '25 kg');
      await tester.pump();

      expect(find.textContaining('Geçerli bir gramaj girin'), findsOneWidget);
      expect(
          tester
              .widget<ElevatedButton>(
                  find.byKey(const Key('confirmWeightEntryButton')))
              .onPressed,
          isNull);
    });
  });

  group('"Çok Tercih Edilenler" (Top 20) (2026-11-03)', () {
    PosTableOperationalView emptyOpenTableView() {
      return const PosTableOperationalView(
        tableId: 'table-1',
        status: 'occupied',
        tableSessionId: 'tsess-1',
        subAccounts: [],
        checks: [],
        orders: [],
      );
    }

    testWidgets(
        '"Tümü" no longer exists; "Çok Tercih Edilenler" replaces it in '
        'the category rail', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pump(tester, initialView: emptyOpenTableView());

      expect(find.text('Tümü'), findsNothing);
      expect(find.text('Çok Tercih Edilenler'), findsOneWidget);
    });

    testWidgets(
        'shows the real top-selling products returned by the backend, '
        'ranked in the order the server returned them', (tester) async {
      final viewGateway = _FakePosOperationalViewGateway()
        ..viewToReturn = emptyOpenTableView()
        ..topSellingProductsToReturn = const [
          PosTopSellingProduct(
              productId: 'prod_cocacola',
              productName: 'CocaCola Şişe',
              quantitySold: 42),
        ];
      final actionGateway = _FakePosActionGateway();
      await tester.binding.setSurfaceSize(const Size(1200, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            posOperationalViewGatewayProvider.overrideWithValue(viewGateway),
            posActionGatewayProvider.overrideWithValue(actionGateway),
            posDeviceContextProvider.overrideWithValue(_ctx),
            selectedPosTableIdProvider.overrideWith((ref) => 'table-1'),
            kitchenProjectionRepositoryProvider
                .overrideWithValue(InMemoryKitchenProjectionRepository()),
          ],
          child: const MaterialApp(home: PosTableWorkspaceScreen()),
        ),
      );
      await tester.pumpAndSettle();

      final grid = find.byType(GridView);
      expect(find.descendant(of: grid, matching: find.text('CocaCola Şişe')),
          findsOneWidget);
    });

    testWidgets(
        'falls back to the fixed showcase list, never a blank grid, when '
        'there is no sales data yet', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      // The fake's topSellingProductsToReturn defaults to [] — no override
      // needed to exercise the no-sales-data fallback.
      await _pump(tester, initialView: emptyOpenTableView());
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Henüz yeterli satış verisi yok.'), findsNothing);
      final grid = find.byType(GridView);
      expect(
          find.descendant(
              of: grid, matching: find.text('Tatlı Ekşi Tavuk Bowl')),
          findsOneWidget);
    });

    testWidgets(
        'falls back to the fixed showcase list on a service error, never a '
        'dead error screen', (tester) async {
      final viewGateway = _FakePosOperationalViewGateway()
        ..viewToReturn = emptyOpenTableView()
        ..topSellingProductsError =
            const PosOperationalViewException('unavailable', 'down');
      final actionGateway = _FakePosActionGateway();
      await tester.binding.setSurfaceSize(const Size(1200, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            posOperationalViewGatewayProvider.overrideWithValue(viewGateway),
            posActionGatewayProvider.overrideWithValue(actionGateway),
            posDeviceContextProvider.overrideWithValue(_ctx),
            selectedPosTableIdProvider.overrideWith((ref) => 'table-1'),
            kitchenProjectionRepositoryProvider
                .overrideWithValue(InMemoryKitchenProjectionRepository()),
          ],
          child: const MaterialApp(home: PosTableWorkspaceScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Çok tercih edilenler yüklenemedi.'), findsNothing);
      final grid = find.byType(GridView);
      expect(
          find.descendant(
              of: grid, matching: find.text('Tatlı Ekşi Tavuk Bowl')),
          findsOneWidget);
    });
  });

  group('Ürün Özelleştirme Modalı (2026-11-03)', () {
    PosTableOperationalView emptyOpenTableView() {
      return const PosTableOperationalView(
        tableId: 'table-1',
        status: 'occupied',
        tableSessionId: 'tsess-1',
        subAccounts: [],
        checks: [],
        orders: [],
      );
    }

    /// "Tatlı Ekşi Tavuk Bowl" (`prod_bowl2_tatli_eksi_tavuk`, real
    /// catalog) — a Bowl product, so it carries the required Karbonhidrat/
    /// Salata/Turşu groups (each with a free default option already
    /// selected) plus the optional Ekstra/Ekstra Sos groups, and has
    /// `nutrition.calories == 560`. Returns the pumped fakes so callers
    /// can assert on `submitStaffEntryOrder` after further interaction.
    Future<_Fakes> openBowlCustomizationModal(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final fakes = await _pump(tester, initialView: emptyOpenTableView());

      await tester.tap(find.text("Bowl'lar"));
      await tester.pump();
      final bowlCard = find.descendant(
        of: find.byType(GridView),
        matching: find.text('Tatlı Ekşi Tavuk Bowl'),
      );
      await tester.ensureVisible(bowlCard);
      await tester.tap(bowlCard);
      await tester.pumpAndSettle();
      return fakes;
    }

    testWidgets(
        'tapping a Bowl product (required modifier groups) opens the '
        'customization modal instead of adding directly, and shows its '
        'calorie badge and required groups', (tester) async {
      await openBowlCustomizationModal(tester);

      // Only the first group ("Karbonhidrat") is guaranteed built by the
      // right panel's lazy `ListView` without scrolling first — later
      // groups ("Salata", "Turşu", ...) are exercised by the other tests
      // below, which scroll by selecting/confirming options inside them.
      expect(find.text('Karbonhidrat Değişimi'), findsOneWidget);
      expect(find.textContaining('560 kcal'), findsWidgets);
      // Real catalog allergens for this exact product (BR-BOWL-009).
      expect(find.text('gluten'), findsWidgets);
      expect(find.text('susam'), findsWidgets);
      // Every required group's default option is pre-selected, so the
      // modal opens already valid at the base price — no extra tap
      // needed before Kaydet is enabled.
      expect(find.widgetWithText(ElevatedButton, 'Kaydet (520 TL)'),
          findsOneWidget);
    });

    testWidgets(
        'scrolling the right panel reveals the 2026-11-09 PDF extra '
        'groups (Ekstra Protein / Peynir / Sos)', (tester) async {
      await openBowlCustomizationModal(tester);

      final rightPanel = find
          .descendant(
            of: find.byType(Dialog),
            matching: find.byType(Scrollable),
          )
          .last;

      await tester.scrollUntilVisible(find.text('Ekstra Protein'), 400,
          scrollable: rightPanel);
      expect(find.text('Ekstra Protein'), findsOneWidget);

      await tester.scrollUntilVisible(find.text('Labne Peyniri'), 400,
          scrollable: rightPanel);
      expect(find.text('Labne Peyniri'), findsOneWidget);

      await tester.scrollUntilVisible(find.text('Ballı Hardal'), 400,
          scrollable: rightPanel);
      expect(find.text('Ballı Hardal'), findsOneWidget);
    });

    testWidgets(
        'tapping a drink (only the optional cross-sell sauce group) still '
        'adds directly — no modal', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pump(tester, initialView: emptyOpenTableView());

      await tester.tap(find.text('İçecekler'));
      await tester.pump();
      final cocaColaCard = find.descendant(
        of: find.byType(GridView),
        matching: find.text('CocaCola Şişe'),
      );
      await tester.ensureVisible(cocaColaCard);
      await tester.tap(cocaColaCard);
      await tester.pump();

      expect(find.byType(Dialog), findsNothing);
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets(
        'confirming the modal with its default selections adds a '
        'configured line whose summary lists the chosen options, and '
        'submits those options as groupId/optionId pairs', (tester) async {
      final fakes = await openBowlCustomizationModal(tester);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Kaydet (520 TL)'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Pirinç / Basmati Pilavı'), findsOneWidget);

      await tester.tap(find.byKey(const Key('confirmStaffEntryOrderButton')));
      await tester.pumpAndSettle();

      final items = fakes.actionGateway.lastStaffEntryItems!;
      expect(items, hasLength(1));
      expect(items.first['productId'], 'prod_bowl2_tatli_eksi_tavuk');
      final selectedModifiers =
          items.first['selectedModifiers'] as List<dynamic>;
      expect(selectedModifiers, hasLength(4));
      expect(
        selectedModifiers,
        containsAll([
          {'groupId': 'bowl_carb', 'optionId': 'carb_basmati'},
          {'groupId': 'bowl_salad', 'optionId': 'salad_mevsim'},
          {'groupId': 'bowl_vegetable', 'optionId': 'veg_standard'},
          {'groupId': 'bowl_pickle', 'optionId': 'pickle_mor_lahana'},
        ]),
      );
    });

    testWidgets(
        'picking a paid option (Meksika Pilavı, +20 TL) updates the '
        "modal's total and the pending cart's total", (tester) async {
      await openBowlCustomizationModal(tester);

      // 2026-11-10: the Bowl's longer removable list (whole standard base)
      // now pushes the swap groups below the modal's first screenful.
      await tester.ensureVisible(find.text('Meksika Pilavı'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Meksika Pilavı'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ElevatedButton, 'Kaydet (540 TL)'),
          findsOneWidget);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Kaydet (540 TL)'));
      await tester.pumpAndSettle();

      // Scoped to the cart-total key, not a bare `find.text('540 TL')` —
      // some other Bowl product in the same category grid can coincide
      // with this exact price.
      expect(
        tester.widget<Text>(find.byKey(const Key('staffEntryCartTotal'))).data,
        '540 TL',
      );
    });

    testWidgets(
        'the quick note popup on a pending line updates its note, shown '
        'in the line summary and sent through submitStaffEntryOrder',
        (tester) async {
      final fakes = await openBowlCustomizationModal(tester);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Kaydet (520 TL)'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Not Ekle'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('lineNoteField')),
        'Sosu ayrı olsun',
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Kaydet'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Not: Sosu ayrı olsun'), findsOneWidget);

      await tester.tap(find.byKey(const Key('confirmStaffEntryOrderButton')));
      await tester.pumpAndSettle();

      expect(fakes.actionGateway.lastStaffEntryItems!.first['note'],
          'Sosu ayrı olsun');
    });
  });

  // 2026-11-08 — "Siparişi Onayla" replaces the payment button while the
  // cart has unsent items.
  group('Siparişi Onayla (2026-11-08)', () {
    Future<_Fakes> pumpWithOpenCheckAndCartItem(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final fakes = await _pump(tester, initialView: _acceptedLineView());
      await tester.tap(find.widgetWithText(ElevatedButton, 'Hesap Aç'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.widgetWithText(ElevatedButton, 'Ödemeye Hazırla'),
          findsOneWidget);

      await tester.tap(find.text('İçecekler'));
      await tester.pump();
      final card = find.descendant(
        of: find.byType(GridView),
        matching: find.text('CocaCola Şişe'),
      );
      await tester.ensureVisible(card);
      await tester.tap(card);
      await tester.pump();
      return fakes;
    }

    testWidgets(
        'with unsent items the primary button is Siparişi Onayla and the '
        'payment flow is hidden', (tester) async {
      await pumpWithOpenCheckAndCartItem(tester);

      expect(find.text('Siparişi Onayla'), findsOneWidget);
      expect(
          find.widgetWithText(ElevatedButton, 'Ödemeye Hazırla'), findsNothing,
          reason: 'finalizing now would leave the unsent items off both '
              'the kitchen and the bill');
    });

    testWidgets(
        'Siparişi Onayla sends the cart to the kitchen in one call, then the '
        'payment button returns', (tester) async {
      final fakes = await pumpWithOpenCheckAndCartItem(tester);

      await tester.tap(find.byKey(const Key('confirmStaffEntryOrderButton')));
      await tester.pumpAndSettle();

      expect(fakes.actionGateway.submitStaffEntryOrderCallCount, 1);
      expect(find.text('Siparişi Onayla'), findsNothing);
      expect(find.widgetWithText(ElevatedButton, 'Ödemeye Hazırla'),
          findsOneWidget);
    });
  });

  // ADR-066 (2026-11-08) — manager-tier users cancel directly.
  group('accepted-line cancellation wording by role (ADR-066)', () {
    Future<_Fakes> pumpAs(
      WidgetTester tester, {
      required Set<StaffRole> roles,
      required bool serverAppliesDirectly,
    }) async {
      final fakes = await _pump(
        tester,
        initialView: _acceptedLineView(),
        extraOverrides: [
          actorSessionProvider.overrideWith((ref) => ActorSession(
                actorId: 'actor-1',
                roles: roles,
                activeRole: roles.first,
              )),
        ],
      );
      fakes.actionGateway.cancellationAppliesDirectly = serverAppliesDirectly;
      return fakes;
    }

    Future<void> submitCancel(WidgetTester tester, String label) async {
      await tester.tap(find.byTooltip(label));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('reasonMessageField')), 'Yanlış ürün girildi');
      await tester.tap(find.widgetWithText(ElevatedButton, label));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets(
        'a manager sees Ürünü İptal Et and is told the item was cancelled',
        (tester) async {
      final fakes = await pumpAs(tester,
          roles: {StaffRole.manager}, serverAppliesDirectly: true);

      expect(find.byTooltip('İptal Talebi Gönder'), findsNothing);
      await submitCancel(tester, 'Ürünü İptal Et');

      expect(fakes.actionGateway.cancellationRequestCallCount, 1);
      expect(find.text('Ürün iptal edildi.'), findsOneWidget);
    });

    testWidgets(
        'staff still sees İptal Talebi Gönder and is told it went for approval',
        (tester) async {
      final fakes = await pumpAs(tester,
          roles: {StaffRole.staff}, serverAppliesDirectly: false);

      await submitCancel(tester, 'İptal Talebi Gönder');

      expect(fakes.actionGateway.cancellationRequestCallCount, 1);
      expect(find.text('İptal talebi yönetici onayına gönderildi.'),
          findsOneWidget);
    });

    testWidgets(
        'the message follows what the server did, not the button wording',
        (tester) async {
      await pumpAs(tester,
          roles: {StaffRole.manager}, serverAppliesDirectly: false);

      await submitCancel(tester, 'Ürünü İptal Et');

      expect(find.text('İptal talebi yönetici onayına gönderildi.'),
          findsOneWidget);
    });
  });

  // 2026-11-09 — real report: 6 identical cancel calls for one line from
  // repeated taps while the first call was still in flight.
  group('reason dialog double-submit guard (2026-11-09)', () {
    testWidgets(
        'while the cancel call is in flight the buttons are locked, a spinner '
        'shows, repeated taps send nothing more, and the dialog closes after',
        (tester) async {
      final fakes = await _pump(tester, initialView: _acceptedLineView());
      final gate = Completer<void>();
      fakes.actionGateway.cancellationGate = gate;

      await tester.tap(find.byTooltip('İptal Talebi Gönder'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('reasonMessageField')), 'Yanlış ürün girildi');

      final confirm = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(ElevatedButton),
      );
      await tester.tap(confirm);
      await tester.pump();

      expect(fakes.actionGateway.cancellationRequestCallCount, 1);
      expect(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(CircularProgressIndicator),
          ),
          findsOneWidget);
      expect(tester.widget<ElevatedButton>(confirm).onPressed, isNull);
      expect(
          tester
              .widget<TextButton>(find.widgetWithText(TextButton, 'Vazgeç'))
              .onPressed,
          isNull);

      for (var i = 0; i < 5; i++) {
        await tester.tap(confirm, warnIfMissed: false);
        await tester.pump();
      }
      expect(fakes.actionGateway.cancellationRequestCallCount, 1,
          reason: 'repeated taps must not fire a second request');

      gate.complete();
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(fakes.actionGateway.cancellationRequestCallCount, 1);
    });
  });
}
