import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:abakus_one_v2/core/router/app_routes.dart';
import 'package:abakus_one_v2/features/auth/data/repositories/auth_repository.dart';
import 'package:abakus_one_v2/features/auth/data/repositories/development_local_auth_repository.dart';
import 'package:abakus_one_v2/features/auth/data/repositories/firebase_auth_repository.dart';
import 'package:abakus_one_v2/features/auth/data/session_storage.dart';
import 'package:abakus_one_v2/features/auth/domain/models/auth_session.dart';
import 'package:abakus_one_v2/features/auth/presentation/providers/auth_provider.dart';
import 'package:abakus_one_v2/features/auth/presentation/screens/login_screen.dart';
import 'package:abakus_one_v2/features/auth/presentation/screens/otp_screen.dart';
import 'package:abakus_one_v2/features/navigation/presentation/screens/main_navigation_screen.dart';

import '../../core/services/auth/fake_firebase_auth_client.dart';

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
      // A minimal stand-in for AdminShellScreen — the real screen needs its
      // own heavy provider setup this file has no reason to duplicate; this
      // test only cares that the shortcut navigates to AppRoutes.admin at
      // all, not what that real screen itself then does.
      GoRoute(
        path: AppRoutes.admin,
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('ADMIN_SHELL_STUB'))),
      ),
    ],
  );
}

AuthRepository _firebaseRepository(FakeFirebaseAuthClient client) =>
    FirebaseAuthRepository(
      client: client,
      sessionStorage: _FakeSessionStorage(),
    );

Future<void> _pumpLogin(WidgetTester tester,
    {AuthRepository? repository}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(
          repository ??
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

    // .first — the phone field is the first TextFormField on screen;
    // "Geliştirici Girişi" (TEMPORARY_DEVELOPER_LOGIN) may render 2 more
    // when DEV_LOGIN_PIN is configured at test time.
    await tester.enterText(find.byType(TextFormField).first, '123');
    await tester.ensureVisible(find.text('Devam Et'));
    await tester.tap(find.text('Devam Et'));
    await tester.pumpAndSettle();

    expect(find.byType(OtpScreen), findsNothing);
  });

  testWidgets('gecerli telefon ile Devam Et OtpScreen\'e gecer', (
    tester,
  ) async {
    await _pumpLogin(tester);

    // .first — see the sibling test above for why.
    await tester.enterText(find.byType(TextFormField).first, '5321234567');
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

  testWidgets(
    'ADR-085: the debug-only staff-entry shortcut is gone — staff use '
    '"Şifre ile giriş" on this same screen',
    (tester) async {
      await _pumpLogin(tester);

      expect(find.byIcon(Icons.admin_panel_settings_outlined), findsNothing);
      expect(find.text('Şifre ile giriş'), findsOneWidget);
    },
  );

  testWidgets(
    'ADR-085: "Şifre ile giriş" shows the password field and "Giriş Yap"; '
    'switching back restores the SMS flow',
    (tester) async {
      await _pumpLogin(tester);
      expect(find.byKey(const Key('loginPasswordField')), findsNothing);

      await tester.tap(find.byKey(const Key('loginModeToggle')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('loginPasswordField')), findsOneWidget);
      expect(find.text('Giriş Yap'), findsOneWidget);
      expect(find.text('SMS kodu ile giriş'), findsOneWidget);

      await tester.tap(find.byKey(const Key('loginModeToggle')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('loginPasswordField')), findsNothing);
      expect(find.text('Devam Et'), findsOneWidget);
    },
  );

  testWidgets(
    'ADR-085: a correct phone + password signs in and opens the app',
    (tester) async {
      final client = FakeFirebaseAuthClient()
        ..passwordsByEmail['905321234567@staff-login.abakus.invalid'] =
            'dogru-sifre-123';
      await _pumpLogin(tester, repository: _firebaseRepository(client));

      await tester.tap(find.byKey(const Key('loginModeToggle')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '5321234567');
      await tester.enterText(
          find.byKey(const Key('loginPasswordField')), 'dogru-sifre-123');
      await tester.ensureVisible(find.text('Giriş Yap'));
      await tester.tap(find.text('Giriş Yap'));
      await tester.pumpAndSettle();

      expect(find.byType(MainNavigationScreen), findsOneWidget);
    },
  );

  testWidgets(
    'ADR-085: a wrong password and an unknown number get the same message, '
    'so the screen never reveals who is staff',
    (tester) async {
      final client = FakeFirebaseAuthClient()
        ..passwordsByEmail['905321234567@staff-login.abakus.invalid'] =
            'dogru-sifre-123';
      await _pumpLogin(tester, repository: _firebaseRepository(client));
      await tester.tap(find.byKey(const Key('loginModeToggle')));
      await tester.pumpAndSettle();

      for (final phone in ['5321234567', '5329999999']) {
        await tester.enterText(find.byType(TextFormField).first, phone);
        await tester.enterText(
            find.byKey(const Key('loginPasswordField')), 'yanlis-sifre');
        await tester.ensureVisible(find.text('Giriş Yap'));
        await tester.tap(find.text('Giriş Yap'));
        await tester.pumpAndSettle();

        expect(find.text('Telefon numarası veya şifre hatalı.'), findsOneWidget,
            reason: phone);
        expect(find.byType(LoginScreen), findsOneWidget);
      }
    },
  );
}
