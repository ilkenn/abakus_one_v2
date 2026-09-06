import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:abakus_one_v2/bootstrap/app_bootstrap.dart';
import 'package:abakus_one_v2/features/navigation/presentation/screens/main_navigation_screen.dart';
import 'package:abakus_one_v2/features/qr/presentation/screens/table_guest_entry_screen.dart';

/// AP-4 Wave F — requirement id `E2E-CUSTOMER-QR-ENTRY`. The customer-facing
/// QR table-entry surface is a correct, supported Web use case (unlike
/// operational POS) — see `docs/decisions.md`'s "Web POS evidence
/// classification" entry. No trusted-device session or platform claim is
/// involved anywhere in this flow.
///
/// Requires the local emulators running and seeded via
/// `functions/scripts/seed_local_admin.js`, which provisions a real, active
/// `tableQrCodes` token (`qrtoken-ap3vis-available`, deterministic —
/// confirmed by direct Firestore query, not guessed) for its "available"
/// table.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const qrToken = 'qrtoken-ap3vis-available';

  testWidgets(
      'a real customer opens a table via its real QR token, sees the real '
      'server-resolved preview, confirms, and reaches the real main app — '
      'end-to-end, no mocks', (tester) async {
    final bootstrap = await bootstrapApp();
    expect(bootstrap.isFirebaseReady, isTrue,
        reason: 'Firebase must be emulator-connected — see '
            'docs/local_admin_login_runbook.md.');

    // A genuine anonymous customer session — the real entry point this
    // screen is reached by ("a customer opening a table's QR link has not
    // signed in to anything yet", per the screen's own doc comment).
    await fb_auth.FirebaseAuth.instance.signInAnonymously();
    expect(fb_auth.FirebaseAuth.instance.currentUser, isNotNull);

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: bootstrap.providerOverrides,
        child: const MaterialApp(
          home: TableGuestEntryScreen(token: qrToken),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 500));
      if (find.text('Masaya Otur').evaluate().isNotEmpty) break;
      final error = find.byType(Text).evaluate().where((e) {
        final text = (e.widget as Text).data;
        return text != null &&
            (text.contains('bulunamadı') ||
                text.contains('geçersiz') ||
                text.contains('süresi dolmuş'));
      });
      if (error.isNotEmpty) {
        fail('the token was rejected as invalid/expired/not-found — rerun '
            'functions/scripts/seed_local_admin.js against a fresh '
            'emulator, or confirm the token via a direct Firestore query.');
      }
    }
    expect(find.text('Masaya Otur'), findsOneWidget,
        reason: 'the real server-resolved preview must reach its usable '
            'state within 15s and offer the real confirm button');

    await tester.tap(find.text('Masaya Otur'));
    await tester.pump();

    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 500));
      if (find.byType(MainNavigationScreen).evaluate().isNotEmpty) break;
    }
    expect(find.byType(MainNavigationScreen), findsOneWidget,
        reason: 'confirming must open a real table guest session and land '
            'on the real main app shell — proving the full QR entry -> '
            'preview -> confirm -> session round trip end-to-end');
  });
}
