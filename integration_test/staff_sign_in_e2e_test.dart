import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:abakus_one_v2/bootstrap/app_bootstrap.dart';
import 'package:abakus_one_v2/features/admin/presentation/screens/admin_shell_screen.dart';
import 'package:abakus_one_v2/features/admin/presentation/screens/admin_unauthorized_screen.dart';
import 'package:abakus_one_v2/features/admin/presentation/screens/customer_management_screen.dart';
import 'package:abakus_one_v2/features/admin/presentation/screens/staff_sign_in_screen.dart';

/// AP-3 closure — the one test this pass's own requirements insist on:
/// "at least one test must exercise the real local Firebase emulators
/// end-to-end, not only mocked repositories or widget providers." This
/// runs the REAL `bootstrapApp()` (the exact entry point `main.dart`
/// itself calls) against a REAL, already-seeded local Firebase Auth/
/// Firestore/Functions emulator (see `functions/scripts/seed_local_admin
/// .js` — this test's credentials come from exactly that script's fixed
/// output, not a mock).
///
/// Driven entirely through Flutter's own `WidgetTester` (`tester.tap`/
/// `tester.enterText`) — an in-process widget-tree interaction, never an
/// OS-level input-injection mechanism. Screenshots are captured via
/// `RenderRepaintBoundary.toImage()`, a pure Flutter rendering API with no
/// platform-specific screenshot call and therefore no risk of touching
/// anything outside this app's own render tree — the earlier, correctly
/// abandoned Windows automation attempt is exactly the class of risk this
/// mechanism structurally cannot reproduce.
///
/// Requires the emulators to already be running AND seeded — see
/// `docs/local_admin_login_runbook.md` for the exact, verified command
/// sequence. This test is not part of `flutter test` (it lives in
/// `integration_test/`, run via `flutter test integration_test/... -d
/// <device>`) and is never executed by the ordinary CI/quality-gate suite.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const cashierEmail = 'kasiyer@abakus.test';
  const password = 'GorselKabul2026!';

  Future<void> saveScreenshot(WidgetTester tester, String name) async {
    // Locate the nearest RenderRepaintBoundary under the root render view —
    // a pure Flutter rendering API, not a platform-specific screenshot
    // call, so this cannot touch anything outside this app's own render
    // tree regardless of platform.
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
    // `dart:io`'s `Directory`/`File` compile fine for Web (the web `dart:io`
    // shim exists) but throw `UnsupportedError` at runtime the moment
    // they're actually used — confirmed the hard way (this test previously
    // crashed here on `-d web-server`). Rendering the image is still real
    // proof-of-state on every platform; only the disk write is native-only.
    if (kIsWeb) return;
    final bytes = Uint8List.view(byteData.buffer);
    final dir = Directory('build/ap3_visual_evidence');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    File('${dir.path}/$name.png').writeAsBytesSync(bytes);
  }

  testWidgets(
      'real staff sign-in against the local emulators reaches the real '
      'Admin shell, opens Customers, and signs out — end-to-end, no mocks',
      (tester) async {
    // AP-3 (Wave 4) — the Web-specific hang this test's doc comment
    // previously described as "a deeper, undiagnosed isolate-level stall"
    // was root-caused: `functions/scripts/seed_local_admin.js` provisioned
    // its fixture organization under a self-invented `org-${RUN_ID}` id,
    // never the app's own hardcoded single-tenant `kSingleTenantOrganizationId`
    // ('org-1', `lib/core/config/current_organization.dart`) that
    // `FirebaseStaffAuthRepository._organizationId()` actually looks claims
    // up under — so `claims.rolesFor('org-1')` was always empty despite a
    // fully successful auth sign-in + claims sync, and `ActorSession
    // .tryFromRaw` correctly failed closed. Fixed by seeding under `'org-1'`
    // — verified end-to-end here, not just by re-reading the fix. Windows
    // remains genuinely blocked (`cloud_functions` has no Windows plugin
    // implementation in this package version — confirmed via
    // `windows/flutter/generated_plugin_registrant.cc`); that is a real,
    // narrow platform-support gap, not the "impossible on Windows" framing
    // an earlier pass overstated (see `docs/local_admin_login_runbook.md`).
    final bootstrap = await bootstrapApp();
    expect(bootstrap.isFirebaseReady, isTrue,
        reason:
            'Firebase must actually be initialized and emulator-connected — '
            'if this is false, the emulators are not reachable from this '
            'test run; see docs/local_admin_login_runbook.md.');

    // Desktop-width viewport — `AdminShellScreen` picks its layout
    // (`_DesktopShell`/`_TabletShell`/`_MobileShell`) by width, and only
    // `_DesktopShell` renders every nav item directly (no drawer to open
    // first), which the "Müşteri 360" tap below relies on.
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: bootstrap.providerOverrides,
        child: const MaterialApp(home: StaffSignInScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await saveScreenshot(tester, '02_staff_admin_sign_in_form');

    await tester.enterText(
        find.widgetWithText(TextFormField, 'E-posta'), cashierEmail);
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Şifre'), password);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Giriş Yap'));
    await tester.pump();

    // Real network round-trip against the real local emulators — give it
    // real wall-clock time via repeated pumps rather than pumpAndSettle
    // (which would time out waiting for the CircularProgressIndicator's
    // own animation to settle).
    for (var i = 0; i < 90; i++) {
      await tester.pump(const Duration(milliseconds: 1000));
      if (find.byType(AdminShellScreen).evaluate().isNotEmpty) break;
      if (find
          .text('Giriş başarısız. Bilgilerinizi kontrol edin.')
          .evaluate()
          .isNotEmpty) {
        fail('signIn returned null (invalid credential) — the seeded '
            'cashier account/claims are not what this test expects. Rerun '
            'functions/scripts/seed_local_admin.js against the running '
            'emulators.');
      }
      final errorText = find
          .byWidgetPredicate(
              (w) => w is Text && w.data != null && w.data!.isNotEmpty)
          .evaluate()
          .map((e) => (e.widget as Text).data!)
          .where((t) => t.contains('zaman aşım') || t.contains('Beklenmeyen'))
          .toList();
      if (errorText.isNotEmpty) {
        fail('sign-in surfaced an error instead of succeeding: '
            '${errorText.first}');
      }
    }

    expect(find.byType(AdminShellScreen), findsOneWidget,
        reason: 'a real sign-in with the seeded cashier credential must reach '
            'the real Admin shell within 90s — if this fails, the sign-in '
            'hang this AP-3 wave investigated has not actually been '
            'resolved end-to-end, only in unit tests');
    await tester.pumpAndSettle();
    await saveScreenshot(tester, '01_admin_shell_reached_after_real_sign_in');

    // Section 2 (AP-3, Wave 4) requires: "... -> Admin shell visible ->
    // Customers destination opens -> logout succeeds." The cashier fixture
    // has `customer-360` in its `visibleToRoles` (`admin_shell_screen.dart`)
    // — tap it and confirm the real `CustomerManagementScreen` renders.
    await tester.tap(find.text('Müşteri 360'));
    await tester.pumpAndSettle();
    expect(find.byType(CustomerManagementScreen), findsOneWidget,
        reason: 'the Customers (Müşteri 360) destination must open from the '
            'real Admin shell nav — this is a required Section 2 step, not '
            'optional evidence');
    await saveScreenshot(tester, '12_admin_customer_directory');

    // Logout — the `Çıkış Yap` IconButton this pass added to `_TopBar`
    // (previously `StaffSessionController.signOut()` existed with no UI
    // wired to it at all). A successful logout must clear the session and
    // return to `AdminUnauthorizedScreen` (`AdminShellScreen.build()`'s own
    // `session == null` branch) — never a blank screen or a stuck spinner.
    await tester.tap(find.byIcon(Icons.logout_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(AdminUnauthorizedScreen), findsOneWidget,
        reason: 'signing out must clear the staff session and return to the '
            'real unauthorized gate, proving StaffSessionController.signOut() '
            'is actually reachable end-to-end, not just unit-tested');
  });
}
