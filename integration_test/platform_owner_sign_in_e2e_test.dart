import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:abakus_one_v2/bootstrap/app_bootstrap.dart';
import 'package:abakus_one_v2/features/platform/presentation/screens/platform_shell_screen.dart';
import 'package:abakus_one_v2/features/platform/presentation/screens/platform_sign_in_screen.dart';

/// AP-4 Wave F — requirement id `E2E-PLATFORM-OWNER-REGRESSION`. Web is the
/// correct, supported surface for the Platform Owner console (unlike
/// operational POS) — see `docs/decisions.md`'s "Web POS evidence
/// classification" entry for why that distinction matters. This test needs
/// no device session and makes no platform claim at all; it is unambiguous
/// Web-appropriate evidence.
///
/// Requires the local emulators running and seeded via
/// `functions/scripts/seed_local_admin.js` (creates `sahip@abakus.test` as
/// a real Platform Owner account — see that script's own output for exact
/// credentials).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const platformOwnerEmail = 'sahip@abakus.test';
  const platformOwnerPassword = 'GorselKabul2026!';

  testWidgets(
      'real Platform Owner sign-in against the local emulators reaches the '
      'real Platform console, a real tab switch works, and sign-out '
      'returns to the real sign-in screen — end-to-end, no mocks',
      (tester) async {
    final bootstrap = await bootstrapApp();
    expect(bootstrap.isFirebaseReady, isTrue,
        reason: 'Firebase must actually be initialized and '
            'emulator-connected — see docs/local_admin_login_runbook.md.');

    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: bootstrap.providerOverrides,
        child: const MaterialApp(home: PlatformSignInScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextFormField, 'E-posta'), platformOwnerEmail);
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Şifre'), platformOwnerPassword);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Giriş Yap'));
    await tester.pump();

    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 500));
      if (find.byType(PlatformShellScreen).evaluate().isNotEmpty) break;
      final failed = find
          .text('Giriş başarısız. Bilgilerinizi kontrol edin.')
          .evaluate();
      if (failed.isNotEmpty) {
        fail('signIn returned an invalid-credential error — the seeded '
            'Platform Owner account/claims are not what this test expects. '
            'Rerun functions/scripts/seed_local_admin.js against the '
            'running emulators.');
      }
    }
    expect(find.byType(PlatformShellScreen), findsOneWidget,
        reason: 'a real sign-in with the seeded Platform Owner credential '
            'must reach the real Platform console within 30s');
    await tester.pumpAndSettle();

    // Real tab navigation within the real shell.
    expect(find.text('İzleme'), findsOneWidget);
    await tester.tap(find.text('Yayın Hazırlığı'));
    await tester.pumpAndSettle();
    expect(find.text('Mağaza Uyumluluğu'), findsOneWidget,
        reason: 'the tab bar itself must still be present after switching '
            'tabs — proving a real, working tab navigation, not a static '
            'screenshot');

    // Sign out — must clear the session and return to the real sign-in
    // screen, never a blank screen or a stuck spinner.
    await tester.tap(find.byIcon(Icons.logout_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(PlatformSignInScreen), findsOneWidget,
        reason: 'signing out must clear the platform session and return to '
            'the real sign-in screen');
  });
}
