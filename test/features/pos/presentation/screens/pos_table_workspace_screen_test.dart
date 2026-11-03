import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abakus_one_v2/features/menu/domain/models/menu_product.dart';
import 'package:abakus_one_v2/features/pos/data/kitchen_projection_repository.dart';
import 'package:abakus_one_v2/features/pos/data/pos_action_gateway.dart';
import 'package:abakus_one_v2/features/pos/data/pos_operational_view_gateway.dart';
import 'package:abakus_one_v2/features/pos/domain/kds/kitchen_line_status.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/kds_dependencies_provider.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/pos_workspace_providers.dart';
import 'package:abakus_one_v2/features/pos/presentation/screens/pos_table_workspace_screen.dart';

import '../../test_support/kds_test_fixtures.dart';

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
  KitchenProjectionRepository? kitchenRepo,
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
/// setup every split/discount/transfer/merge test below needs, now that
/// those actions live behind that sheet instead of being always-visible
/// (2026-10-31 3-column redesign; product owner's explicit choice).
Future<void> _openCheckThenToolsSheet(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(ElevatedButton, 'Hesap Aç'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tap(find.widgetWithText(OutlinedButton, 'İşlemler'));
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
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(fakes.actionGateway.finalizeCallCount, 1);
    });
  });

  group('İşlemler sheet — split / headcount / discount / transfer / merge', () {
    testWidgets('Kişiye Göre Böl calls splitByCustomer', (tester) async {
      final fakes = await _pump(tester, initialView: _acceptedLineView());
      await _openCheckThenToolsSheet(tester);

      await tester.tap(find.byTooltip('Kişiye Göre Böl'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(fakes.actionGateway.splitByCustomerCallCount, 1);
    });

    testWidgets(
        'table transfer dialog calls transferTable with the entered target table id',
        (tester) async {
      final fakes = await _pump(tester, initialView: _acceptedLineView());
      await _openCheckThenToolsSheet(tester);

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
        'quantity split dialog calls splitByQuantity with the chosen quantity',
        (tester) async {
      final fakes = await _pump(tester, initialView: _acceptedLineView());
      await _openCheckThenToolsSheet(tester);

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
      await _openCheckThenToolsSheet(tester);

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
      await _openCheckThenToolsSheet(tester);

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
      await _openCheckThenToolsSheet(tester);

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
        'and Siparişi Mutfağa Gönder submits both units in one call',
        (tester) async {
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
      await tester
          .tap(find.widgetWithText(ElevatedButton, 'Siparişi Mutfağa Gönder'));
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

      expect(find.widgetWithText(ElevatedButton, 'Siparişi Mutfağa Gönder'),
          findsNothing,
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

      expect(find.widgetWithText(ElevatedButton, 'Siparişi Mutfağa Gönder'),
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

      // "Tümü" (every active category) is the default filter — CocaCola
      // Şişe exists but isn't necessarily built yet inside the (lazy)
      // grid's initial range; searching should bring it into view
      // regardless of which category tab is selected.
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

    testWidgets('clearing the search field restores the full grid',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pump(tester, initialView: emptyOpenTableView());

      await tester.enterText(
          find.byKey(const Key('productSearchField')), 'cocacola');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.clear_rounded));
      await tester.pump();

      final grid = find.byType(GridView);
      expect(
        find.descendant(of: grid, matching: find.text('Tatlı Ekşi Tavuk Bowl')),
        findsOneWidget,
      );
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
      expect(find.text('Karbonhidrat'), findsOneWidget);
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
        'scrolling the right panel reveals the 2026-11-03 İlave Protein / '
        'Sos Tercihi / Ekstra Topping groups, each with their confirmed '
        'prices', (tester) async {
      await openBowlCustomizationModal(tester);

      final rightPanel = find
          .descendant(
            of: find.byType(Dialog),
            matching: find.byType(Scrollable),
          )
          .last;

      await tester.scrollUntilVisible(find.text('İlave Protein'), 400,
          scrollable: rightPanel);
      expect(find.text('İlave Protein'), findsOneWidget);
      expect(find.text('İlave Dana Bonfile'), findsOneWidget);

      await tester.scrollUntilVisible(find.text('Sos Tercihi'), 400,
          scrollable: rightPanel);
      expect(find.text('Sos Tercihi'), findsOneWidget);
      expect(find.text('Sweet Chilli'), findsOneWidget);

      await tester.scrollUntilVisible(find.text('Ekstra Topping'), 400,
          scrollable: rightPanel);
      expect(find.text('Ekstra Topping'), findsOneWidget);
      expect(find.text('Avokado'), findsOneWidget);
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

      await tester
          .tap(find.widgetWithText(ElevatedButton, 'Siparişi Mutfağa Gönder'));
      await tester.pumpAndSettle();

      final items = fakes.actionGateway.lastStaffEntryItems!;
      expect(items, hasLength(1));
      expect(items.first['productId'], 'prod_bowl2_tatli_eksi_tavuk');
      final selectedModifiers =
          items.first['selectedModifiers'] as List<dynamic>;
      expect(selectedModifiers, hasLength(3));
      expect(
        selectedModifiers,
        containsAll([
          {'groupId': 'bowl_carb', 'optionId': 'carb_basmati'},
          {'groupId': 'bowl_salad', 'optionId': 'salad_mevsim'},
          {'groupId': 'bowl_pickle', 'optionId': 'pickle_mor_lahana'},
        ]),
      );
    });

    testWidgets(
        'picking a paid option (Meksika Pilavı, +20 TL) updates the '
        "modal's total and the pending cart's total", (tester) async {
      await openBowlCustomizationModal(tester);

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

      await tester
          .tap(find.widgetWithText(ElevatedButton, 'Siparişi Mutfağa Gönder'));
      await tester.pumpAndSettle();

      expect(fakes.actionGateway.lastStaffEntryItems!.first['note'],
          'Sosu ayrı olsun');
    });
  });
}
