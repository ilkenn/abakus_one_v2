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
import 'package:abakus_one_v2/features/navigation/presentation/screens/main_navigation_screen.dart';
import 'package:abakus_one_v2/features/onboarding/presentation/screens/onboarding_screen.dart';

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
/// scenario reaches — [OnboardingScreen] now navigates via `go_router`
/// (`context.go`), so it needs a `GoRouter` ancestor, not the bare
/// `MaterialApp(home: ...)` this file used pre-P1-010.
GoRouter _testRouter() {
  return GoRouter(
    initialLocation: AppRoutes.onboarding,
    routes: [
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.main,
        builder: (context, state) => const MainNavigationScreen(),
      ),
    ],
  );
}

void main() {
  testWidgets(
    'Onboarding tamamlaninca MainNavigationScreen degil LoginScreen acilir',
    (tester) async {
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

      await tester.tap(find.text('Atla'));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(MainNavigationScreen), findsNothing);
    },
  );

  testWidgets(
    'Onboarding image render box extends close to the controls area, '
    'not stopping well short of it',
    (tester) async {
      // A realistic tall-phone viewport (h/w > the 656x1372 source
      // artwork's own ratio) -- this is the case where BoxFit.cover inside
      // a full-screen box crops the image's *sides*, not its top/bottom,
      // which is exactly why the image's box must be explicitly bounded
      // instead of relying on `alignment` alone.
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

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
      // Lets the post-frame controls-height measurement land and rebuild.
      await tester.pumpAndSettle();

      final imageRect = tester.getRect(find.byType(PageView));
      final controlsRect = tester.getRect(find.byKey(onboardingControlsKey));

      // The image must stay pinned to the very top of the screen -- only
      // the bottom is trimmed, never the top (crop-position fix, not a
      // "move the image down" layout change).
      expect(imageRect.top, 0);

      final gap = controlsRect.top - imageRect.bottom;

      // The image's bottom edge must sit just above the controls -- not
      // flush (0) and not stopping well short of them (the old bug: a
      // large leftover cream gap).
      expect(gap, greaterThanOrEqualTo(0));
      expect(gap, lessThan(24));
    },
  );
}
