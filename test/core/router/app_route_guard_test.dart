import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/core/router/app_route_guard.dart';
import 'package:abakus_one_v2/core/router/app_routes.dart';

void main() {
  group('AppRouteGuard.resolve — signed in (persisted session)', () {
    test('at main, no redirect', () {
      expect(
        AppRouteGuard.resolve(
          location: AppRoutes.main,
          isAuthenticated: true,
          isGuest: false,
          isOnboardingComplete: true,
        ),
        isNull,
      );
    });

    test('at login, redirected to main', () {
      expect(
        AppRouteGuard.resolve(
          location: AppRoutes.login,
          isAuthenticated: true,
          isGuest: false,
          isOnboardingComplete: true,
        ),
        AppRoutes.main,
      );
    });

    test('at otp, redirected to main', () {
      expect(
        AppRouteGuard.resolve(
          location: AppRoutes.otp,
          isAuthenticated: true,
          isGuest: false,
          isOnboardingComplete: true,
        ),
        AppRoutes.main,
      );
    });

    test('at onboarding, redirected to main', () {
      expect(
        AppRouteGuard.resolve(
          location: AppRoutes.onboarding,
          isAuthenticated: true,
          isGuest: false,
          isOnboardingComplete: false,
        ),
        AppRoutes.main,
      );
    });
  });

  group('AppRouteGuard.resolve — signed in (guest)', () {
    test('at main, no redirect', () {
      expect(
        AppRouteGuard.resolve(
          location: AppRoutes.main,
          isAuthenticated: false,
          isGuest: true,
          isOnboardingComplete: true,
        ),
        isNull,
      );
    });

    test('at login, redirected to main', () {
      expect(
        AppRouteGuard.resolve(
          location: AppRoutes.login,
          isAuthenticated: false,
          isGuest: true,
          isOnboardingComplete: true,
        ),
        AppRoutes.main,
      );
    });
  });

  group('AppRouteGuard.resolve — not signed in', () {
    test(
        'at main, onboarding not yet complete, redirected to onboarding '
        '(no splash to route back through — bootstrap already resolved '
        'the session before the router was ever built)', () {
      expect(
        AppRouteGuard.resolve(
          location: AppRoutes.main,
          isAuthenticated: false,
          isGuest: false,
          isOnboardingComplete: false,
        ),
        AppRoutes.onboarding,
      );
    });

    test('at main, onboarding already complete, redirected to login', () {
      expect(
        AppRouteGuard.resolve(
          location: AppRoutes.main,
          isAuthenticated: false,
          isGuest: false,
          isOnboardingComplete: true,
        ),
        AppRoutes.login,
      );
    });

    test('at login, no redirect', () {
      expect(
        AppRouteGuard.resolve(
          location: AppRoutes.login,
          isAuthenticated: false,
          isGuest: false,
          isOnboardingComplete: false,
        ),
        isNull,
      );
    });

    test('at otp, no redirect', () {
      expect(
        AppRouteGuard.resolve(
          location: AppRoutes.otp,
          isAuthenticated: false,
          isGuest: false,
          isOnboardingComplete: false,
        ),
        isNull,
      );
    });

    test('at onboarding, not yet complete, no redirect', () {
      expect(
        AppRouteGuard.resolve(
          location: AppRoutes.onboarding,
          isAuthenticated: false,
          isGuest: false,
          isOnboardingComplete: false,
        ),
        isNull,
      );
    });

    test('at onboarding, already complete, redirected to login', () {
      expect(
        AppRouteGuard.resolve(
          location: AppRoutes.onboarding,
          isAuthenticated: false,
          isGuest: false,
          isOnboardingComplete: true,
        ),
        AppRoutes.login,
      );
    });
  });
}
