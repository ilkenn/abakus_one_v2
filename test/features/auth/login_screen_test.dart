import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:abakus_one_v2/core/router/app_routes.dart';
import 'package:abakus_one_v2/features/auth/data/repositories/development_local_auth_repository.dart';
import 'package:abakus_one_v2/features/auth/data/session_storage.dart';
import 'package:abakus_one_v2/features/auth/domain/models/auth_session.dart';
import 'package:abakus_one_v2/features/auth/presentation/providers/auth_provider.dart';
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

/// A minimal test-local route table covering only the routes this file's
/// scenarios actually reach — [LoginScreen] now navigates via `go_router`
/// (`context.push`/`context.go`), so it needs a `GoRouter` ancestor, not
/// the bare `MaterialApp(home: ...)` this file used pre-P1-010.
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

Future<void> _pumpLogin(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(
          DevelopmentLocalAuthRepository(
            sessionStorage: _FakeSessionStorage(),
          ),
        ),
      ],
      child: MaterialApp.router(routerConfig: _testRouter()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('gecersiz telefon ile Devam Et OtpScreen acmaz', (
    tester,
  ) async {
    await _pumpLogin(tester);

    await tester.enterText(find.byType(TextFormField), '123');
    await tester.ensureVisible(find.text('Devam Et'));
    await tester.tap(find.text('Devam Et'));
    await tester.pumpAndSettle();

    expect(find.byType(OtpScreen), findsNothing);
  });

  testWidgets('gecerli telefon ile Devam Et OtpScreen\'e gecer', (
    tester,
  ) async {
    await _pumpLogin(tester);

    await tester.enterText(find.byType(TextFormField), '5321234567');
    await tester.ensureVisible(find.text('Devam Et'));
    await tester.tap(find.text('Devam Et'));
    await tester.pumpAndSettle();

    expect(find.byType(OtpScreen), findsOneWidget);
  });

  testWidgets(
    'Misafir Olarak Devam Et MainNavigationScreen\'e gecer ve stack\'i temizler',
    (tester) async {
      await _pumpLogin(tester);

      await tester.ensureVisible(find.text('Misafir Olarak Devam Et'));
      await tester.tap(find.text('Misafir Olarak Devam Et'));
      await tester.pumpAndSettle();

      expect(find.byType(MainNavigationScreen), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);
    },
  );
}
