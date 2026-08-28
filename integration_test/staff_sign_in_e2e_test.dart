import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:abakus_one_v2/bootstrap/app_bootstrap.dart';
import 'package:abakus_one_v2/features/admin/presentation/screens/admin_shell_screen.dart';
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
    final bytes = Uint8List.view(byteData.buffer);
    final dir = Directory('build/ap3_visual_evidence');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    File('${dir.path}/$name.png').writeAsBytesSync(bytes);
  }

  testWidgets(
      'real staff sign-in against the local emulators reaches the real '
      'Admin shell — end-to-end, no mocks', (tester) async {
    // Intentionally left enabled-but-documented, not silently deleted: this
    // test is real, correct, and currently expected to fail on the two
    // platforms available in this environment — see
    // `docs/local_admin_login_runbook.md`'s "Known blockers" section for
    // the two independently diagnosed, disclosed causes (Windows: cloud_
    // functions has no Windows plugin implementation at all in this
    // package version; Web: a deeper, undiagnosed isolate-level stall this
    // session's own timeout fix could not observe/bound). Re-run this on
    // Android/iOS once available — cloud_functions genuinely supports
    // both, and neither blocker above applies there.
    final bootstrap = await bootstrapApp();
    expect(bootstrap.isFirebaseReady, isTrue,
        reason:
            'Firebase must actually be initialized and emulator-connected — '
            'if this is false, the emulators are not reachable from this '
            'test run; see docs/local_admin_login_runbook.md.');

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
  });
}
