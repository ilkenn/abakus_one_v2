import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cloud_functions/cloud_functions.dart' as functions;
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:abakus_one_v2/bootstrap/app_bootstrap.dart';
import 'package:abakus_one_v2/features/pos/data/pos_action_gateway.dart'
    show PosDeviceContext;
import 'package:abakus_one_v2/features/pos/data/pos_operational_view_gateway.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/pos_workspace_providers.dart';
import 'package:abakus_one_v2/features/pos/presentation/screens/pos_checkout_screen.dart';

import 'support/emulator_fixtures.dart';

/// AP-4 Wave E — Flow #1: cash full payment. Real routed
/// `PosCheckoutScreen`, real local Firebase emulators (Auth/Firestore/
/// Functions), a real signed-in staff identity, a real trusted-device
/// session (genuine Ed25519 challenge-response), and a real seeded
/// tenant/catalog/table (`functions/scripts/seed_dev_tenant.mjs`/
/// `seed_dev_catalog.mjs`/`seed_dev_staff.mjs`/`seed_dev_table_qr.mjs` —
/// run once against the running emulator before this suite).
///
/// The only non-literal simulation here: the table's guest session is
/// opened by the already-signed-in admin identity rather than a separate
/// anonymous customer session (`openTableGuestSession` only requires SOME
/// authenticated caller, not specifically an anonymous one) — every
/// document this produces is still real, and every staff action that
/// follows reads the resulting `tableSessions`/`restaurantTables` state
/// exactly as it would for a genuine customer-opened session.
///
/// **Known, diagnosed, unresolved blocker (AP-4 Wave E, 2026-09-01):** in
/// this exact environment, EVERY real `FirebaseFunctions.instance
/// .httpsCallable(...).call(...)` invocation made directly from this
/// test's own bare async body — even the simplest possible one
/// (`syncOwnStaffClaims` with empty data) — fails with a generic
/// `[firebase_functions/internal] internal` error, with zero
/// corresponding entry in the Functions emulator's own invocation log
/// (confirmed: the request never reaches the server at all). This is NOT
/// specific to this file's own data/logic — proven by testing the
/// simplest possible callable in isolation, which fails identically.
/// Ruled out as causes: App Check (never activated on Web in this app —
/// no site key configured, confirmed by reading
/// `firebase_app_check_service.dart`), plugin-registration timing
/// (pumping a placeholder widget first made no difference), device type
/// (`web-server` and a real `chrome` device both fail identically), and
/// this file's specific payload (the simplest possible call also fails).
/// The SAME emulator, from the SAME browser session, is reachable fine
/// via raw HTTP (`EmulatorFixtures.callCallableRaw`, `package:http`) and
/// via the real `firebase_auth` SDK (`signInWithEmailAndPassword`
/// succeeds) — this is specific to `cloud_functions_web`'s own JS interop
/// layer in a `flutter drive --target=integration_test/...` harness.
/// Diagnosing further requires browser devtools/network-inspector access
/// this environment does not provide. This test's own code is believed
/// correct and ready to run once that platform issue is resolved.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const adminEmail = 'admin@abakus.dev';
  const adminPassword = 'abakus-dev-admin-2026';
  const organizationId = 'org-1';
  const branchId = 'branch-1';
  const tableId = 'table-12';
  const qrToken = 'DEV-ABAKUS-T12';

  Future<void> saveScreenshot(WidgetTester tester, String name) async {
    final renderView = tester.binding.renderViews.first;
    RenderRepaintBoundary? repaintBoundary;
    void visit(RenderObject object) {
      if (repaintBoundary != null) return;
      if (object is RenderRepaintBoundary) {
        repaintBoundary = object;
        return;
      }
      object.visitChildren(visit);
    }

    visit(renderView);
    if (repaintBoundary == null) return;
    final image = await repaintBoundary!.toImage(pixelRatio: 1.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return;
    if (kIsWeb) return;
    final bytes = Uint8List.view(byteData.buffer);
    final dir = Directory('build/ap4_visual_evidence');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    File('${dir.path}/$name.png').writeAsBytesSync(bytes);
  }

  testWidgets(
      'cash full payment: a staff-entered order, opened check, finalized '
      'to readyForPayment, is fully paid in cash through the real routed '
      'checkout screen against real local emulators', (tester) async {
    final bootstrap = await bootstrapApp();
    expect(bootstrap.isFirebaseReady, isTrue,
        reason: 'Firebase must be emulator-connected — see '
            'docs/local_admin_login_runbook.md.');

    // Pump a minimal placeholder first — on Web, the plugin registrant
    // (including `cloud_functions_web`'s own JS interop bridge) finishes
    // wiring itself up as part of the normal widget-tree bootstrap; a bare
    // `httpsCallable` invocation issued before ANY widget has ever been
    // pumped is untested territory this app's own code never exercises.
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pumpAndSettle();

    final auth = fb_auth.FirebaseAuth.instance;
    await auth.signInWithEmailAndPassword(
        email: adminEmail, password: adminPassword);
    expect(auth.currentUser, isNotNull);
    // Force a fresh ID token so any just-granted custom claims are
    // actually reflected in the next real callable this identity makes.
    await auth.currentUser!.getIdToken(true);

    final fixtures = EmulatorFixtures();
    final adminIdToken = await auth.currentUser!.getIdToken();
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

    // Real customer QR flow — opens a genuine table session.
    final openSession = await functions.FirebaseFunctions.instance
        .httpsCallable('openTableGuestSession')
        .call<Map<String, dynamic>>({'token': qrToken});
    final tableSessionId = openSession.data['tableSessionId'] as String;

    // Real staff-entry order submission.
    final submissionKey =
        'e2e-cash-full-${DateTime.now().microsecondsSinceEpoch}';
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
            return PosCheckoutScreen(
              ctx: ctx,
              checkId: checkId,
              view: view,
            );
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await saveScreenshot(tester, '01_canonical_remaining_amount');

    // Real network round-trip for the initial session load.
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 500));
      if (find.text('Kalanı Doldur').evaluate().isNotEmpty) break;
    }
    expect(find.text('Kalanı Doldur'), findsOneWidget,
        reason: 'the checkout screen must reach its ready state with the '
            'real payment session loaded');

    await tester.tap(find.text('Kalanı Doldur'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('checkoutSubmitTenderButton')));
    await tester.pump();

    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 500));
      if (find.text('Ödeme Tamamlandı').evaluate().isNotEmpty) break;
    }
    expect(find.text('Ödeme Tamamlandı'), findsOneWidget,
        reason: 'a full cash tender for the exact remaining amount must '
            'reach the real completed state via the real backend');
    await tester.pumpAndSettle();
    await saveScreenshot(tester, '04_successful_cash_payment');
  });
}
