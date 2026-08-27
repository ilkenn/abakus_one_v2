import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/core/router/app_router.dart';
import 'package:abakus_one_v2/core/router/app_routes.dart';
import 'package:abakus_one_v2/features/admin/presentation/screens/admin_shell_screen.dart';
import 'package:abakus_one_v2/features/auth/data/repositories/development_local_auth_repository.dart';
import 'package:abakus_one_v2/features/auth/data/session_storage.dart';
import 'package:abakus_one_v2/features/auth/domain/models/auth_session.dart';
import 'package:abakus_one_v2/features/auth/presentation/providers/auth_provider.dart';
import 'package:abakus_one_v2/features/auth/presentation/screens/login_screen.dart';
import 'package:abakus_one_v2/features/auth/presentation/screens/otp_screen.dart';
import 'package:abakus_one_v2/features/customer_registration/domain/models/customer_profile_completion_state.dart';
import 'package:abakus_one_v2/features/customer_registration/presentation/providers/customer_registration_providers.dart';
import 'package:abakus_one_v2/features/navigation/presentation/screens/main_navigation_screen.dart';
import 'package:abakus_one_v2/features/onboarding/presentation/provider/onboarding_provider.dart';
import 'package:abakus_one_v2/features/onboarding/presentation/screens/onboarding_screen.dart';
import 'package:abakus_one_v2/features/platform/presentation/screens/platform_shell_screen.dart';
import 'package:abakus_one_v2/features/platform/presentation/screens/platform_sign_in_screen.dart';

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

/// Unlike [_pumpAt], never calls `router.go(...)` — proves
/// `appRouterProvider`'s own `initialLocation` (resolved once, from
/// whatever `authProvider`/`onboardingCompleteProvider` state [overrides]
/// seed) lands the very first frame on the right screen by itself.
/// Startup routing cleanup (splash removal): this is the direct test of
/// "no Flutter splash route is entered" / "no double navigation" — with
/// no dedicated splash route left at all, there is nothing else for the
/// router to redirect *through* on the way to the first real screen.
Future<void> _pumpInitial(
  WidgetTester tester, {
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

  final router = container.read(appRouterProvider);

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
    testWidgets(
      '/main redirects to OnboardingScreen when not signed in and '
      'onboarding is not yet complete (no splash to redirect through)',
      (tester) async {
        await _pumpAt(tester, '/main');
        expect(find.byType(OnboardingScreen), findsOneWidget);
        expect(find.byType(MainNavigationScreen), findsNothing);
      },
    );

    testWidgets(
      '/main redirects to LoginScreen when not signed in and onboarding '
      'is already complete',
      (tester) async {
        await _pumpAt(
          tester,
          '/main',
          overrides: [
            onboardingCompleteProvider.overrideWith(
              _CompletedOnboardingNotifier.new,
            ),
          ],
        );
        expect(find.byType(LoginScreen), findsOneWidget);
        expect(find.byType(MainNavigationScreen), findsNothing);
      },
    );

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

  group('appRouterProvider — initialLocation (startup, splash removal)', () {
    testWidgets(
      'a pre-resolved authenticated session lands the very first frame on '
      'MainNavigationScreen directly — no other screen ever mounts',
      (tester) async {
        final resolvedSession = AuthSession(
          uid: 'uid-1',
          phoneNumber: '+905321234567',
          createdAt: DateTime(2026, 1, 1),
          expiresAt: DateTime(2026, 12, 31),
        );
        await _pumpInitial(
          tester,
          overrides: [
            authProvider.overrideWith(
              () => SeededAuthNotifier(
                AuthState(
                  isAuthenticated: true,
                  isGuest: false,
                  session: resolvedSession,
                ),
              ),
            ),
            // Customer Registration CR.1 — a real customer session now
            // also routes through the profile-completion gate, which
            // otherwise reaches a live Firestore-backed provider
            // unavailable under `flutter test` (mirrors the identical
            // fix `customerPhotoGatewayProvider` needed for the same
            // reason). This test is about startup routing, not profile
            // completion — treated as already complete.
            customerProfileCompletionStateProvider.overrideWithValue(
              const CustomerProfileCompletionState.complete(),
            ),
          ],
        );

        expect(find.byType(MainNavigationScreen), findsOneWidget);
        expect(find.byType(OnboardingScreen), findsNothing);
        expect(find.byType(LoginScreen), findsNothing);
      },
    );

    testWidgets(
      'no session, onboarding not yet complete -> first frame is '
      'OnboardingScreen directly',
      (tester) async {
        await _pumpInitial(tester);

        expect(find.byType(OnboardingScreen), findsOneWidget);
        expect(find.byType(MainNavigationScreen), findsNothing);
        expect(find.byType(LoginScreen), findsNothing);
      },
    );

    testWidgets(
      'no session, onboarding already complete -> first frame is '
      'LoginScreen directly',
      (tester) async {
        await _pumpInitial(
          tester,
          overrides: [
            onboardingCompleteProvider.overrideWith(
              _CompletedOnboardingNotifier.new,
            ),
          ],
        );

        expect(find.byType(LoginScreen), findsOneWidget);
        expect(find.byType(OnboardingScreen), findsNothing);
        expect(find.byType(MainNavigationScreen), findsNothing);
      },
    );
  });

  group('appRouterProvider — AP-2 Stage B: /admin route', () {
    testWidgets(
      '/admin resolves to AdminShellScreen even for a signed-out customer '
      '— never redirected to /login (staff auth is a separate identity '
      'system; AdminShellScreen performs its own internal gate)',
      (tester) async {
        await _pumpAt(tester, AppRoutes.admin);

        expect(find.byType(AdminShellScreen), findsOneWidget);
        expect(find.byType(LoginScreen), findsNothing);
        expect(find.byType(OnboardingScreen), findsNothing);
      },
    );

    testWidgets(
      '/admin resolves to AdminShellScreen for an already-signed-in '
      'customer too — never hijacked by the blanket "signed in -> main" '
      'branch the way every other unlisted signed-in route would be',
      (tester) async {
        await _pumpAt(
          tester,
          AppRoutes.admin,
          overrides: [authProvider.overrideWith(_GuestAuthNotifier.new)],
        );

        expect(find.byType(AdminShellScreen), findsOneWidget);
        expect(find.byType(MainNavigationScreen), findsNothing);
      },
    );
  });

  group('appRouterProvider — AP-2 final wiring: /platform route', () {
    testWidgets(
      '/platform resolves to PlatformShellScreen (which falls back to its '
      'own PlatformSignInScreen with no platform session) even for a '
      'signed-out customer — never redirected to /login, mirroring '
      '/admin\'s exact bypass one tier up',
      (tester) async {
        await _pumpAt(tester, AppRoutes.platform);

        expect(find.byType(PlatformShellScreen), findsOneWidget);
        expect(find.byType(PlatformSignInScreen), findsOneWidget);
        expect(find.byType(LoginScreen), findsNothing);
        expect(find.byType(OnboardingScreen), findsNothing);
      },
    );

    testWidgets(
      '/platform resolves to PlatformShellScreen for an already-signed-in '
      'customer too — never hijacked by the blanket "signed in -> main" '
      'branch, mirroring /admin\'s exact bypass one tier up',
      (tester) async {
        await _pumpAt(
          tester,
          AppRoutes.platform,
          overrides: [authProvider.overrideWith(_GuestAuthNotifier.new)],
        );

        expect(find.byType(PlatformShellScreen), findsOneWidget);
        expect(find.byType(MainNavigationScreen), findsNothing);
      },
    );
  });
}
