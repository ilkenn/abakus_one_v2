import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:abakus_one_v2/core/router/app_routes.dart';
import 'package:abakus_one_v2/features/auth/data/emulator_verification_code_client.dart';
import 'package:abakus_one_v2/features/auth/data/repositories/development_local_auth_repository.dart';
import 'package:abakus_one_v2/features/auth/data/session_storage.dart';
import 'package:abakus_one_v2/features/auth/domain/models/auth_session.dart';
import 'package:abakus_one_v2/features/auth/presentation/providers/auth_provider.dart';
import 'package:abakus_one_v2/features/auth/presentation/providers/quick_test_login_provider.dart';
import 'package:abakus_one_v2/features/auth/presentation/screens/login_screen.dart';
import 'package:abakus_one_v2/features/auth/presentation/screens/otp_screen.dart';
import 'package:abakus_one_v2/features/navigation/presentation/screens/main_navigation_screen.dart';

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
      ],
      child: MaterialApp.router(routerConfig: _testRouter()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  // Faz "Development Quick Phone Login" — `flutter test` always runs with
  // no `ENVIRONMENT` dart-define, so `AppEnvironment.current` resolves to
  // `development` in every test process (see `AppEnvironment.fromDefine`'s
  // own documented default). `QuickTestLoginConfig.isAvailable` is
  // therefore always `true` here — this is exactly why the *hidden-in-
  // production/staging* proof lives in `quick_test_login_config_test.dart`
  // against the explicit-environment `isAvailableFor`, not here: this file
  // proves the screen correctly wires up the config and the flow, not the
  // gating logic itself.

  testWidgets(
      'Hızlı Test Girişi button renders in the (test-default) development context',
      (tester) async {
    await _pumpLogin(tester);

    expect(find.textContaining('Hızlı Test Girişi'), findsOneWidget);
  });

  testWidgets(
      'the normal "Telefon ile Devam Et" flow remains available and unchanged '
      '(req 6) — Quick Test Login button does not replace or hide it',
      (tester) async {
    await _pumpLogin(tester);

    expect(find.text('Devam Et'), findsOneWidget);
    expect(find.text('Misafir Olarak Devam Et'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), '5321234567');
    await tester.ensureVisible(find.text('Devam Et'));
    await tester.tap(find.text('Devam Et'));
    await tester.pumpAndSettle();

    expect(find.byType(OtpScreen), findsOneWidget);
  });

  testWidgets(
      'tapping Hızlı Test Girişi signs the user in and continues to the main app, '
      'with no manual OTP entry required', (tester) async {
    await _pumpLogin(tester);

    await tester.ensureVisible(find.textContaining('Hızlı Test Girişi'));
    await tester.tap(find.textContaining('Hızlı Test Girişi'));
    await tester.pumpAndSettle();

    expect(find.byType(MainNavigationScreen), findsOneWidget);
    expect(find.byType(OtpScreen), findsNothing);
  });

  testWidgets(
      'a missing emulator code shows a safe development error, never a fake sign-in',
      (tester) async {
    await _pumpLogin(tester, emulatorCode: null);

    await tester.ensureVisible(find.textContaining('Hızlı Test Girişi'));
    await tester.tap(find.textContaining('Hızlı Test Girişi'));
    await tester.pumpAndSettle();

    expect(find.byType(MainNavigationScreen), findsNothing);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.textContaining('bulunamadı'), findsOneWidget);
  });
}
