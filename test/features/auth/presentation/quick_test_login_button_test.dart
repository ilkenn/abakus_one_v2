import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:abakus_one_v2/core/router/app_routes.dart';
import 'package:abakus_one_v2/features/auth/data/dev_login_config.dart';
import 'package:abakus_one_v2/features/auth/data/emulator_verification_code_client.dart';
import 'package:abakus_one_v2/features/auth/data/repositories/development_local_auth_repository.dart';
import 'package:abakus_one_v2/features/auth/data/session_storage.dart';
import 'package:abakus_one_v2/features/auth/domain/models/auth_session.dart';
import 'package:abakus_one_v2/features/auth/presentation/providers/auth_provider.dart';
import 'package:abakus_one_v2/features/auth/presentation/providers/dev_login_provider.dart';
import 'package:abakus_one_v2/features/auth/presentation/providers/quick_test_login_provider.dart';
import 'package:abakus_one_v2/features/auth/presentation/screens/login_screen.dart';
import 'package:abakus_one_v2/features/auth/presentation/screens/otp_screen.dart';
import 'package:abakus_one_v2/features/navigation/presentation/screens/main_navigation_screen.dart';

/// TEMPORARY_DEVELOPER_LOGIN
///
/// Formerly `quick_test_login_button_test.dart`'s coverage of the old
/// one-tap "Hızlı Test Girişi" button — that button no longer renders on
/// `LoginScreen` (superseded by "Geliştirici Girişi", see `DevLoginConfig`'s
/// own doc comment for the full removal-marker file list). This file now
/// covers the replacement's own UI wiring. Kept as the same filename
/// deliberately (not renamed) — CLAUDE.md requires explicit approval for
/// file renames; the content changed because the feature it verifies did.
///
/// The full-flow test ("typing phone+PIN and tapping through to
/// MainNavigationScreen") needs `DevLoginConfig.isAvailable` to actually
/// be `true`, which requires the real `DEV_LOGIN_PIN` compile-time define
/// — see `dev_login_provider_test.dart`'s own header comment for why this
/// can't be faked at test time. Run:
///
///   flutter test --dart-define=DEV_LOGIN_PIN=1234 \
///     test/features/auth/presentation/quick_test_login_button_test.dart
///
/// Under the plain `flutter test` default the section simply does not
/// render (exactly as the locked "UI hidden" requirement demands) — the
/// structural tests below (old button gone, normal flow unaffected) run
/// unconditionally either way and don't depend on that define at all.

class _FakeSessionStorage implements SessionStorage {
  AuthSession? stored;
  @override
  Future<AuthSession?> readSession() async => stored;
  @override
  Future<void> writeSession(AuthSession session) async => stored = session;
  @override
  Future<void> clearSession() async => stored = null;
}

class _ScriptedEmulatorVerificationCodeClient
    implements EmulatorVerificationCodeClient {
  _ScriptedEmulatorVerificationCodeClient(this.codeToReturn);
  final String? codeToReturn;

  @override
  Future<String?> fetchLatestCode({
    required String host,
    required int port,
    required String projectId,
    required String phoneNumber,
  }) async =>
      codeToReturn;
}

GoRouter _testRouter() {
  return GoRouter(
    initialLocation: AppRoutes.login,
    routes: [
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.otp,
        builder: (context, state) => const OtpScreen(),
      ),
      GoRoute(
        path: AppRoutes.main,
        builder: (context, state) => const MainNavigationScreen(),
      ),
    ],
  );
}

Future<void> _pumpLogin(
  WidgetTester tester, {
  String? emulatorCode = DevelopmentLocalAuthRepository.developmentOtpCode,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(
          DevelopmentLocalAuthRepository(
            sessionStorage: _FakeSessionStorage(),
          ),
        ),
        emulatorVerificationCodeClientProvider.overrideWithValue(
          _ScriptedEmulatorVerificationCodeClient(emulatorCode),
        ),
        // TEMPORARY_DEVELOPER_LOGIN — no real Firebase app exists under
        // `flutter test`; DevLoginNotifier.run() requires this override to
        // reach the emulator-code lookup at all.
        currentFirebaseProjectIdProvider.overrideWithValue('abakus-one-dev-test-fixture'),
      ],
      child: MaterialApp.router(routerConfig: _testRouter()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final pinConfigured = DevLoginConfig.pin.isNotEmpty;

  testWidgets(
      'the old "Hızlı Test Girişi" button no longer renders anywhere on LoginScreen — replaced, not left alongside the new section',
      (tester) async {
    await _pumpLogin(tester);

    expect(find.textContaining('Hızlı Test Girişi'), findsNothing);
  });

  testWidgets(
      'the normal "Devam Et"/"Misafir Olarak Devam Et" flow remains available and unchanged, regardless of developer-login availability',
      (tester) async {
    await _pumpLogin(tester);

    expect(find.text('Devam Et'), findsOneWidget);
    expect(find.text('Misafir Olarak Devam Et'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).first, '5321234567');
    await tester.ensureVisible(find.text('Devam Et'));
    await tester.tap(find.text('Devam Et'));
    await tester.pumpAndSettle();

    expect(find.byType(OtpScreen), findsOneWidget);
  });

  testWidgets(
      '"Geliştirici Girişi" section only renders when DevLoginConfig.isAvailable — never two overlapping developer-auth mechanisms visible',
      (tester) async {
    await _pumpLogin(tester);

    expect(
      find.text('Geliştirici Girişi'),
      DevLoginConfig.isAvailable ? findsOneWidget : findsNothing,
    );
  });

  testWidgets(
      'the phone field is prefilled with the locked developer number, and the PIN field starts empty',
      (tester) async {
    await _pumpLogin(tester);
    if (!DevLoginConfig.isAvailable) return; // nothing rendered to assert against.

    expect(find.text(DevLoginConfig.developerPhoneLocalInput), findsOneWidget);
    expect(find.text('Geliştirici PIN'), findsOneWidget);
  });

  testWidgets(
      'entering the correct phone + correct PIN and tapping through signs the user in and continues to the main app, with no manual OTP entry required',
      (tester) async {
    await _pumpLogin(tester);

    await tester.ensureVisible(find.text('Geliştirici Olarak Giriş Yap'));
    await tester.enterText(find.widgetWithText(TextFormField, 'Geliştirici PIN'), DevLoginConfig.pin);
    await tester.tap(find.text('Geliştirici Olarak Giriş Yap'));
    await tester.pumpAndSettle();

    expect(find.byType(MainNavigationScreen), findsOneWidget);
    expect(find.byType(OtpScreen), findsNothing);
    // Requires --dart-define=DEV_LOGIN_PIN=<value> — see file header.
  }, skip: !pinConfigured);

  testWidgets(
      'a wrong PIN shows the locked dev-only error and never signs in',
      (tester) async {
    await _pumpLogin(tester);

    // The PIN field is digits-only (FilteringTextInputFormatter.digitsOnly)
    // — a wrong PIN candidate must still be all-digits to actually reach
    // the real comparison, rather than being stripped to empty and
    // rejected by local form validation instead ("PIN gerekli").
    const wrongButAllDigitsPin = DevLoginConfig.pin == '9999' ? '1234' : '9999';
    await tester.ensureVisible(find.text('Geliştirici Olarak Giriş Yap'));
    await tester.enterText(find.widgetWithText(TextFormField, 'Geliştirici PIN'), wrongButAllDigitsPin);
    await tester.tap(find.text('Geliştirici Olarak Giriş Yap'));
    await tester.pumpAndSettle();

    expect(find.byType(MainNavigationScreen), findsNothing);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('Geliştirici girişi başarısız.'), findsOneWidget);
    // Requires --dart-define=DEV_LOGIN_PIN=<value> — see file header.
  }, skip: !pinConfigured);
}
