import 'package:cloud_functions/cloud_functions.dart' as functions;
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:abakus_one_v2/bootstrap/app_bootstrap.dart';
import 'package:abakus_one_v2/features/pos/data/pos_action_gateway.dart'
    show PosDeviceContext;
import 'package:abakus_one_v2/features/pos/data/payment_gateway.dart';
import 'package:abakus_one_v2/features/pos/data/pos_operational_view_gateway.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/pos_workspace_providers.dart';
import 'package:abakus_one_v2/features/pos/presentation/screens/pos_checkout_screen.dart';

import 'support/emulator_fixtures.dart';

/// AP-4 Wave F — requirement ID `E2E-PARTIAL-REFUND` (see
/// `docs/decisions.md`'s "Web POS evidence classification" entry for why
/// this is a stable descriptive id, not a guessed ordinal position in the
/// original 22-item flow enumeration — that list was never committed to
/// this repository and is not recoverable from repository state; only
/// Flow #1 (`pos_cash_full_payment_e2e_test.dart`, AP-4 Wave E) is
/// confirmed to correspond to a real original position).
///
/// **Scope, precisely**: a fully cash-paid check has a partial refund
/// requested through the real routed `PosCheckoutScreen`, approved by a
/// real, distinct second approver identity via a real remote-approval round
/// trip, and the resulting "Tamamlandı" (succeeded) status is confirmed by
/// re-fetching the real operational view — never asserted against a
/// mocked/local state. This proves the real checkout/payment/refund/
/// approval UI and backend engine, exactly like Flow #1. It does **not**
/// prove Web operational POS is supported (it is not, and remains
/// fail-closed by construction for any client using the real
/// `TrustedDeviceSessionController` — see that same decisions.md entry):
/// the device session here is provisioned directly via
/// `EmulatorFixtures.issueDeviceSessionForCurrentUser`, which calls the
/// backend `requestDeviceRegistration` callable directly with a
/// fixture-supplied `platform: "android"` claim, bypassing the real app's
/// own `devicePlatformWireValueProvider`/`isPlatformSupported` gate
/// entirely — a deliberate, documented testability seam
/// (`trusted_device_session_controller.dart`'s own comment: "so a test can
/// supply any platform value without needing platform-detection test
/// doubles"), not a demonstration that a genuine Web client could ever
/// reach this state.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const adminEmail = 'admin@abakus.dev';
  const adminPassword = 'abakus-dev-admin-2026';
  const organizationId = 'org-1';
  const branchId = 'branch-1';
  const tableId = 'table-12';
  const qrToken = 'DEV-ABAKUS-T12';

  testWidgets(
      'partial refund: a fully cash-paid check has a partial refund '
      'requested via the real checkout screen, approved by a real second '
      'approver, and the UI reflects the succeeded status after refresh',
      (tester) async {
    final bootstrap = await bootstrapApp();
    expect(bootstrap.isFirebaseReady, isTrue,
        reason: 'Firebase must be emulator-connected — see '
            'docs/local_admin_login_runbook.md.');

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pumpAndSettle();

    final auth = fb_auth.FirebaseAuth.instance;
    await auth.signInWithEmailAndPassword(
        email: adminEmail, password: adminPassword);
    expect(auth.currentUser, isNotNull);
    await auth.currentUser!.getIdToken(true);

    final fixtures = EmulatorFixtures();
    final adminIdToken = await auth.currentUser!.getIdToken();
    // Admin starts with branchAccess: [] by design (staffAuthorization.ts) —
    // self-grant before operating a branch-scoped POS device, exactly like
    // Flow #1.
    await fixtures.callCallableRaw(
      'grantStaffBranchAccess',
      {
        'organizationId': organizationId,
        'targetUid': auth.currentUser!.uid,
        'branchId': branchId,
      },
      idToken: adminIdToken,
    );
    await auth.currentUser!.getIdToken(true);
    final approverIdToken = await fixtures.createApproverActor(
      organizationId: organizationId,
      branchId: branchId,
      adminIdToken: adminIdToken!,
    );
    final device = await fixtures.issueDeviceSessionForCurrentUser(
      organizationId: organizationId,
      branchId: branchId,
      approverIdToken: approverIdToken,
    );
    final ctx = PosDeviceContext(
      organizationId: organizationId,
      branchId: branchId,
      deviceId: device.deviceId,
      deviceSessionId: device.deviceSessionId,
    );

    final openSession = await functions.FirebaseFunctions.instance
        .httpsCallable('openTableGuestSession')
        .call<Map<String, dynamic>>({'token': qrToken});
    final tableSessionId = openSession.data['tableSessionId'] as String;

    final submissionKey =
        'e2e-partial-refund-${DateTime.now().microsecondsSinceEpoch}';
    final submit = await functions.FirebaseFunctions.instance
        .httpsCallable('submitDineInOrder')
        .call<Map<String, dynamic>>({
      'mode': 'staffEntry',
      'submissionKey': submissionKey,
      ...ctx.toWire(),
      'tableId': tableId,
      'items': [
        {'kind': 'product', 'productId': 'prod_ayran', 'quantity': 1},
      ],
      'subAccountSelection': {'mode': 'staffGeneral'},
    });
    final orderId = submit.data['orderId'] as String;
    final subAccountId = submit.data['subAccountId'] as String;

    final openCheck = await functions.FirebaseFunctions.instance
        .httpsCallable('openCheck')
        .call<Map<String, dynamic>>({
      ...ctx.toWire(),
      'tableSessionId': tableSessionId,
    });
    final checkId = openCheck.data['checkId'] as String;

    await functions.FirebaseFunctions.instance
        .httpsCallable('splitCheckByProduct')
        .call<Map<String, dynamic>>({
      ...ctx.toWire(),
      'checkId': checkId,
      'subAccountId': subAccountId,
      'sourceOrderId': orderId,
      'sourceLineIndex': 0,
    });

    await functions.FirebaseFunctions.instance
        .httpsCallable('finalizeCheckReadyForPayment')
        .call<Map<String, dynamic>>({...ctx.toWire(), 'checkId': checkId});

    final view = await const FirebasePosOperationalViewGateway().getTableView(
      organizationId: organizationId,
      branchId: branchId,
      tableId: tableId,
      deviceId: ctx.deviceId,
      deviceSessionId: ctx.deviceSessionId,
    );

    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...bootstrap.providerOverrides,
          posDeviceContextProvider.overrideWithValue(ctx),
        ],
        child: MaterialApp(
          home: Builder(builder: (context) {
            return PosCheckoutScreen(ctx: ctx, checkId: checkId, view: view);
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 500));
      if (find.text('Kalanı Doldur').evaluate().isNotEmpty) break;
    }
    expect(find.text('Kalanı Doldur'), findsOneWidget);

    // Full cash payment first — the refund dialog only opens once at least
    // one payment attempt exists (session.attempts.isEmpty gate).
    await tester.tap(find.text('Kalanı Doldur'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('checkoutSubmitTenderButton')));
    await tester.pump();
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 500));
      if (find.text('Ödeme Tamamlandı').evaluate().isNotEmpty) break;
    }
    expect(find.text('Ödeme Tamamlandı'), findsOneWidget,
        reason: 'the check must be fully cash-paid before a refund can be '
            'requested against it');
    await tester.pumpAndSettle();

    // Open the refund dialog and request a genuine PARTIAL refund (1500 of
    // the 4000 paid) through the real UI.
    await tester.tap(find.text('İade Talep Et'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kısmi İade'));
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, 'Tutar'), '15,00');
    await tester.enterText(find.widgetWithText(TextField, 'İade Nedeni'),
        'Müşteri şikayeti — E2E test.');
    await tester.pump();
    await tester.tap(find.text('Talebi Gönder'));
    await tester.pumpAndSettle();

    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 500));
      if (find.text('Onay Bekliyor').evaluate().isNotEmpty) break;
    }
    expect(find.text('Onay Bekliyor'), findsOneWidget,
        reason: 'the partial refund request must appear in the refunds '
            'list as pending approval, driven entirely through the real '
            'UI and real backend — no mocked state');

    // Approve via a real, distinct second identity (self-approval is
    // server-rejected) — mirrors the device-activation approval pattern.
    // RefundRequestSummary (the UI-facing model) exposes refundId but not
    // its approvalRequestId, so the deterministic id is derived the exact
    // same way remoteApproval.ts's own createApprovalRequest does:
    // `approval-{actionType}-{targetAggregateRef with / -> _}-v{version}`,
    // where paymentRefund's targetAggregateRef is
    // `refundRequests/{refundId}` and version is always 1 at creation.
    final sessionView = await const FirebasePaymentGateway()
        .getPaymentSessionView(ctx: ctx, checkId: checkId);
    final pendingRefund =
        sessionView.refunds.firstWhere((r) => r.status == 'pendingApproval');
    final approvalRequestId =
        'approval-paymentRefund-refundRequests_${pendingRefund.refundId}-v1';
    final approve = await fixtures.callCallableRaw(
      'respondToApprovalRequest',
      {'requestId': approvalRequestId, 'decision': 'approved'},
      idToken: approverIdToken,
    );
    expect(approve['status'], 'approved');

    // Diagnostic: confirm the SERVER's own state directly, independent of
    // the widget tree, before re-pumping. print() isn't visible through
    // `flutter drive`'s harness, so embed in a failure message instead if
    // it doesn't show the expected post-approval state.
    final postApproveView = await const FirebasePaymentGateway()
        .getPaymentSessionView(ctx: ctx, checkId: checkId);
    final postApproveStatuses = postApproveView.refunds
        .map((r) => '${r.refundId}:${r.status}')
        .join(', ');
    if (!postApproveView.refunds.any((r) => r.status == 'succeeded')) {
      fail('POST-APPROVE SERVER STATE did not show succeeded — '
          'requestId=$approvalRequestId refunds=[$postApproveStatuses]');
    }

    // Unmount to a blank tree first — pumping a structurally-identical
    // PosCheckoutScreen widget directly (same type/position, no distinct
    // Key) would let Flutter's element reconciliation REUSE the existing
    // State object instead of creating a fresh one, so initState's own
    // getPaymentSessionView re-fetch would never re-run and the screen
    // would keep showing the stale pre-approval session forever — genuinely
    // confirmed to be the cause here (the diagnostic above already proved
    // the SERVER shows "succeeded" immediately after approval).
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pumpAndSettle();

    // Re-pump the real screen with a genuinely fresh instance — its own
    // initState re-fetches PaymentSessionView from the real backend (see
    // PosCheckoutScreen's own doc comment: "re-fetched after EVERY
    // action"), so this proves the approval genuinely took effect
    // server-side and is reflected through the real read path, not a
    // client-local optimistic update.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...bootstrap.providerOverrides,
          posDeviceContextProvider.overrideWithValue(ctx),
        ],
        child: MaterialApp(
          home: Builder(builder: (context) {
            return PosCheckoutScreen(ctx: ctx, checkId: checkId, view: view);
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 500));
      if (find.text('Tamamlandı').evaluate().isNotEmpty) break;
    }
    if (find.text('Tamamlandı').evaluate().isEmpty) {
      final allText = find
          .byType(Text)
          .evaluate()
          .map((e) => (e.widget as Text).data)
          .whereType<String>()
          .toSet()
          .join(' | ');
      fail('Expected "Tamamlandı" not found. Visible text on screen: '
          '$allText');
    }
    expect(find.text('Tamamlandı'), findsOneWidget,
        reason: 'after real manager approval, the refund must show as '
            'succeeded — proving the full request -> approve -> settle '
            'round trip end-to-end');
  });
}
