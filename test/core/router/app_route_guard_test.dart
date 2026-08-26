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
          isRealCustomer: false,
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
          isRealCustomer: false,
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
          isRealCustomer: false,
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
          isRealCustomer: false,
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
          isRealCustomer: false,
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
          isRealCustomer: false,
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
          isRealCustomer: false,
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
          isRealCustomer: false,
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
          isRealCustomer: false,
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
          isRealCustomer: false,
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
          isRealCustomer: false,
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
          isRealCustomer: false,
        ),
        AppRoutes.login,
      );
    });
  });

  group(
      'AppRouteGuard.resolve — Faz D.4 takeaway QR guest route is always '
      'public, regardless of session state', () {
    test('not signed in: no redirect', () {
      expect(
        AppRouteGuard.resolve(
          location: AppRoutes.takeawayGuest('some-token'),
          isAuthenticated: false,
          isGuest: false,
          isOnboardingComplete: false,
          isRealCustomer: false,
        ),
        isNull,
      );
    });

    test(
        'a real, authenticated (phone-verified) session does NOT get '
        'bounced to /main — the one case the blanket "signed in -> main" '
        'branch would otherwise hijack', () {
      expect(
        AppRouteGuard.resolve(
          location: AppRoutes.takeawayGuest('some-token'),
          isAuthenticated: true,
          isGuest: false,
          isOnboardingComplete: true,
          isRealCustomer: false,
        ),
        isNull,
      );
    });

    test('an existing guest session does NOT get bounced to /main either', () {
      expect(
        AppRouteGuard.resolve(
          location: AppRoutes.takeawayGuest('some-token'),
          isAuthenticated: false,
          isGuest: true,
          isOnboardingComplete: true,
          isRealCustomer: false,
        ),
        isNull,
      );
    });

    test('onboarding not yet complete: still no redirect (never onboarding)',
        () {
      expect(
        AppRouteGuard.resolve(
          location: AppRoutes.takeawayGuest('some-token'),
          isAuthenticated: false,
          isGuest: false,
          isOnboardingComplete: false,
          isRealCustomer: false,
        ),
        isNull,
      );
    });

    test('the bare prefix without a token is also never redirected', () {
      expect(
        AppRouteGuard.resolve(
          location: AppRoutes.takeawayGuestPrefix,
          isAuthenticated: true,
          isGuest: false,
          isOnboardingComplete: true,
          isRealCustomer: false,
        ),
        isNull,
      );
    });
  });

  group(
      'AppRouteGuard.resolve — AP-2 Stage B: /admin is always bypassed, '
      'regardless of customer session state', () {
    test('not signed in: no redirect', () {
      expect(
        AppRouteGuard.resolve(
          location: AppRoutes.admin,
          isAuthenticated: false,
          isGuest: false,
          isOnboardingComplete: false,
          isRealCustomer: false,
        ),
        isNull,
      );
    });

    test(
        'a real, authenticated customer is NOT bounced to /main — the one '
        'case the blanket "signed in -> main" branch would otherwise '
        'hijack', () {
      expect(
        AppRouteGuard.resolve(
          location: AppRoutes.admin,
          isAuthenticated: true,
          isGuest: false,
          isOnboardingComplete: true,
          isRealCustomer: false,
        ),
        isNull,
      );
    });

    test('an existing guest session does NOT get bounced to /main either', () {
      expect(
        AppRouteGuard.resolve(
          location: AppRoutes.admin,
          isAuthenticated: false,
          isGuest: true,
          isOnboardingComplete: true,
          isRealCustomer: false,
        ),
        isNull,
      );
    });

    test(
        'a real customer needing profile completion is still not '
        'redirected to /complete-profile from /admin', () {
      expect(
        AppRouteGuard.resolve(
          location: AppRoutes.admin,
          isAuthenticated: true,
          isGuest: false,
          isOnboardingComplete: true,
          isRealCustomer: true,
          needsProfileCompletion: true,
        ),
        isNull,
      );
    });
  });

  group(
      'AppRouteGuard.resolve — Faz R.2 reservation routes require real phone-auth',
      () {
    test('a real, authenticated customer is not redirected', () {
      expect(
        AppRouteGuard.resolve(
          location: AppRoutes.reservationPrefix,
          isAuthenticated: true,
          isGuest: false,
          isOnboardingComplete: true,
          isRealCustomer: true,
        ),
        isNull,
      );
    });

    test(
        'a merely-guest session (isGuest true) is NOT treated as sufficient — '
        'redirected to login with a returnTo, unlike the generic "signedIn" '
        'branch which would otherwise send a guest straight to main', () {
      final redirect = AppRouteGuard.resolve(
        location: AppRoutes.reservationPrefix,
        isAuthenticated: false,
        isGuest: true,
        isOnboardingComplete: true,
        isRealCustomer: false,
      );
      expect(redirect, startsWith(AppRoutes.login));
      expect(redirect, contains('returnTo'));
    });

    test(
        'a fully unauthenticated visitor is redirected to login with a returnTo',
        () {
      final redirect = AppRouteGuard.resolve(
        location: AppRoutes.reservationPrefix,
        isAuthenticated: false,
        isGuest: false,
        isOnboardingComplete: true,
        isRealCustomer: false,
      );
      expect(
        redirect,
        AppRoutes.withReturnTo(AppRoutes.login, AppRoutes.reservationPrefix),
      );
    });

    test('a reservation detail route also carries its own path as returnTo',
        () {
      final detailPath = AppRoutes.reservationDetail('reservation-abc123');
      final redirect = AppRouteGuard.resolve(
        location: detailPath,
        isAuthenticated: false,
        isGuest: false,
        isOnboardingComplete: true,
        isRealCustomer: false,
      );
      expect(redirect, AppRoutes.withReturnTo(AppRoutes.login, detailPath));
    });

    test(
        'onboarding not yet complete: lands on onboarding, returnTo not attempted',
        () {
      final redirect = AppRouteGuard.resolve(
        location: AppRoutes.reservationPrefix,
        isAuthenticated: false,
        isGuest: false,
        isOnboardingComplete: false,
        isRealCustomer: false,
      );
      expect(redirect, AppRoutes.onboarding);
    });
  });

  group(
      'AppRouteGuard.resolve — Customer Registration CR.1 profile completion gate',
      () {
    test(
        'a real customer needing completion, at main, is redirected to completeProfile',
        () {
      expect(
        AppRouteGuard.resolve(
          location: AppRoutes.main,
          isAuthenticated: true,
          isGuest: false,
          isOnboardingComplete: true,
          isRealCustomer: true,
          needsProfileCompletion: true,
        ),
        AppRoutes.completeProfile,
      );
    });

    test(
        'a real customer needing completion cannot deep-link around the gate '
        'into ANY other signed-in route — not just main', () {
      for (final location in [
        AppRoutes.main,
        AppRoutes.login,
        AppRoutes.otp,
        AppRoutes.onboarding,
      ]) {
        expect(
          AppRouteGuard.resolve(
            location: location,
            isAuthenticated: true,
            isGuest: false,
            isOnboardingComplete: true,
            isRealCustomer: true,
            needsProfileCompletion: true,
          ),
          AppRoutes.completeProfile,
          reason: 'location=$location must still redirect to completeProfile',
        );
      }
    });

    test(
        'a real customer needing completion, already at completeProfile, is not redirected',
        () {
      expect(
        AppRouteGuard.resolve(
          location: AppRoutes.completeProfile,
          isAuthenticated: true,
          isGuest: false,
          isOnboardingComplete: true,
          isRealCustomer: true,
          needsProfileCompletion: true,
        ),
        isNull,
      );
    });

    test(
        'a real customer who is already complete, at completeProfile, is redirected to main — no re-showing the form',
        () {
      expect(
        AppRouteGuard.resolve(
          location: AppRoutes.completeProfile,
          isAuthenticated: true,
          isGuest: false,
          isOnboardingComplete: true,
          isRealCustomer: true,
          needsProfileCompletion: false,
        ),
        AppRoutes.main,
      );
    });

    test(
        'a real customer who is already complete is treated exactly as before this feature — reaches main freely',
        () {
      expect(
        AppRouteGuard.resolve(
          location: AppRoutes.main,
          isAuthenticated: true,
          isGuest: false,
          isOnboardingComplete: true,
          isRealCustomer: true,
          needsProfileCompletion: false,
        ),
        isNull,
      );
    });

    test(
        'a guest never needs profile completion — completeProfile redirects them straight to main, never shown the form',
        () {
      expect(
        AppRouteGuard.resolve(
          location: AppRoutes.completeProfile,
          isAuthenticated: false,
          isGuest: true,
          isOnboardingComplete: true,
          isRealCustomer: false,
          needsProfileCompletion: false,
        ),
        AppRoutes.main,
      );
    });

    test(
        'a not-signed-in visitor hitting completeProfile directly (stale/bookmarked link) is redirected to login, never shown the form',
        () {
      expect(
        AppRouteGuard.resolve(
          location: AppRoutes.completeProfile,
          isAuthenticated: false,
          isGuest: false,
          isOnboardingComplete: true,
          isRealCustomer: false,
        ),
        AppRoutes.login,
      );
    });

    test(
        'a not-signed-in visitor hitting completeProfile before onboarding is complete lands on onboarding',
        () {
      expect(
        AppRouteGuard.resolve(
          location: AppRoutes.completeProfile,
          isAuthenticated: false,
          isGuest: false,
          isOnboardingComplete: false,
          isRealCustomer: false,
        ),
        AppRoutes.onboarding,
      );
    });

    test(
        'omitting needsProfileCompletion defaults to false — every pre-existing call site/test in this file is unaffected',
        () {
      expect(
        AppRouteGuard.resolve(
          location: AppRoutes.main,
          isAuthenticated: true,
          isGuest: false,
          isOnboardingComplete: true,
          isRealCustomer: true,
        ),
        isNull,
      );
    });
  });

  group(
      'AppRouteGuard.sanitizeReturnTo — strict allowlist, open redirect impossible',
      () {
    test('the bare reservation flow entry is accepted', () {
      expect(
        AppRouteGuard.sanitizeReturnTo(AppRoutes.reservationPrefix),
        AppRoutes.reservationPrefix,
      );
    });

    test('a reservation detail path is accepted', () {
      final path = AppRoutes.reservationDetail('reservation-abc123');
      expect(AppRouteGuard.sanitizeReturnTo(path), path);
    });

    test('a reservation confirmation path is accepted', () {
      final path = AppRoutes.reservationConfirmation('reservation-abc123');
      expect(AppRouteGuard.sanitizeReturnTo(path), path);
    });

    test('null is rejected', () {
      expect(AppRouteGuard.sanitizeReturnTo(null), isNull);
    });

    test('an absolute external URL is rejected', () {
      expect(AppRouteGuard.sanitizeReturnTo('https://evil.com'), isNull);
    });

    test('a protocol-relative URL (//evil.com) is rejected', () {
      expect(AppRouteGuard.sanitizeReturnTo('//evil.com'), isNull);
    });

    test('an unrelated in-app route is rejected — allowlist, not a blocklist',
        () {
      expect(AppRouteGuard.sanitizeReturnTo(AppRoutes.main), isNull);
      expect(AppRouteGuard.sanitizeReturnTo('/admin'), isNull);
    });

    test('a reservation-prefixed path with an unsafe id segment is rejected',
        () {
      expect(AppRouteGuard.sanitizeReturnTo('/reservation/../../etc/passwd'),
          isNull);
      expect(
          AppRouteGuard.sanitizeReturnTo('/reservation/abc?x=https://evil.com'),
          isNull);
    });
  });
}
