import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/core/router/app_router.dart';
import 'package:abakus_one_v2/features/auth/data/repositories/development_local_auth_repository.dart';
import 'package:abakus_one_v2/features/auth/data/session_storage.dart';
import 'package:abakus_one_v2/features/auth/domain/models/auth_session.dart';
import 'package:abakus_one_v2/features/auth/presentation/providers/auth_provider.dart';
import 'package:abakus_one_v2/features/auth/presentation/screens/login_screen.dart';
import 'package:abakus_one_v2/features/auth/presentation/screens/otp_screen.dart';
import 'package:abakus_one_v2/features/navigation/presentation/screens/main_navigation_screen.dart';
import 'package:abakus_one_v2/features/navigation/presentation/screens/splash_screen.dart';
import 'package:abakus_one_v2/features/onboarding/presentation/provider/onboarding_provider.dart';
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

class _GuestAuthNotifier extends AuthNotifier {
  @override
  AuthState build() => const AuthState(isAuthenticated: false, isGuest: true);
}

class _CompletedOnboardingNotifier extends OnboardingCompleteNotifier {
  @override
  bool build() => true;
}

Future<void> _pumpAt(
  WidgetTester tester,
  String location, {
  List<Override> overrides = const [],
}) async {
  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(
        DevelopmentLocalAuthRepository(
          sessionStorage: _FakeSessionStorage(),
        ),
      ),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);

  // Navigated before the first pump (rather than inside a widget's
  // build method, e.g. via a `Consumer`) so this is a plain state
  // change, not a build-time side effect.
  final router = container.read(appRouterProvider);
  router.go(location);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pump();
}

void main() {
  group('appRouterProvider — route resolution', () {
    testWidgets('/login resolves to LoginScreen when not signed in', (
      tester,
    ) async {
      await _pumpAt(tester, '/login');
      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets('/otp resolves to OtpScreen when not signed in', (
      tester,
    ) async {
      await _pumpAt(tester, '/otp');
      expect(find.byType(OtpScreen), findsOneWidget);

      // OtpScreen arms a resend-cooldown Timer as soon as it's built; run
      // it out so none is left pending when the test ends.
      await tester.pump(
        DevelopmentLocalAuthRepository.resendCooldown +
            const Duration(seconds: 1),
      );
    });

    testWidgets(
      '/onboarding resolves to OnboardingScreen when not yet complete',
      (tester) async {
        await _pumpAt(tester, '/onboarding');
        expect(find.byType(OnboardingScreen), findsOneWidget);
      },
    );

    testWidgets(
      '/onboarding redirects to LoginScreen when already complete',
      (tester) async {
        await _pumpAt(
          tester,
          '/onboarding',
          overrides: [
            onboardingCompleteProvider.overrideWith(
              _CompletedOnboardingNotifier.new,
            ),
          ],
        );
        expect(find.byType(LoginScreen), findsOneWidget);
        expect(find.byType(OnboardingScreen), findsNothing);
      },
    );
  });

  group('appRouterProvider — guard redirects applied through the router', () {
    testWidgets('/main redirects to SplashScreen when not signed in', (
      tester,
    ) async {
      await _pumpAt(tester, '/main');
      expect(find.byType(SplashScreen), findsOneWidget);
      expect(find.byType(MainNavigationScreen), findsNothing);

      // Flush SplashScreen's own reveal-animation timers so none are
      // left pending when the test ends.
      await tester.pump(const Duration(milliseconds: 3000));
      await tester.pumpAndSettle();
    });

    testWidgets('/login redirects to MainNavigationScreen for a guest', (
      tester,
    ) async {
      await _pumpAt(
        tester,
        '/login',
        overrides: [authProvider.overrideWith(_GuestAuthNotifier.new)],
      );
      expect(find.byType(MainNavigationScreen), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);
    });
  });
}
