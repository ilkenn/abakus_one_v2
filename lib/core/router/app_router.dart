import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/otp_screen.dart';
import '../../features/navigation/presentation/screens/main_navigation_screen.dart';
import '../../features/navigation/presentation/screens/splash_screen.dart';
import '../../features/onboarding/presentation/provider/onboarding_provider.dart';
import '../../features/onboarding/presentation/screens/onboarding_screen.dart';
import 'app_route_guard.dart';
import 'app_routes.dart';

/// Bridges the Riverpod state [AppRouteGuard] depends on into `GoRouter`'s
/// `refreshListenable`, so a state change that happens without an
/// explicit navigation call (e.g. Splash's persisted-session check
/// resolving) still re-runs the guard against the current location
/// instead of leaving a stale redirect decision in place.
class _RouterRefreshListenable extends ChangeNotifier {
  _RouterRefreshListenable(Ref ref) {
    ref.listen(authProvider, (previous, next) => notifyListeners());
    ref.listen(
      onboardingCompleteProvider,
      (previous, next) => notifyListeners(),
    );
  }
}

/// Wraps [child] in the app's single shared route transition — a 450ms
/// fade — so migrating a screen onto `go_router` doesn't silently change
/// its existing visual transition behavior.
CustomTransitionPage<void> _fadeTransitionPage(Widget child) {
  return CustomTransitionPage<void>(
    child: child,
    transitionDuration: const Duration(milliseconds: 450),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(opacity: animation, child: child);
    },
  );
}

/// The app's router. Scoped to the Splash → Onboarding → Login/Otp → Main
/// entry flow only (per ADR-006) — not a migration of every feature
/// screen. `main` is intentionally left as a single opaque route rather
/// than a `StatefulShellRoute`: giving `MainNavigationScreen` its own
/// nested shell/tab routes would mean redesigning its existing internal
/// bottom-nav logic, which is out of scope for this foundation.
final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: _RouterRefreshListenable(ref),
    redirect: (context, state) {
      final authState = ref.read(authProvider);
      final isOnboardingComplete = ref.read(onboardingCompleteProvider);
      return AppRouteGuard.resolve(
        location: state.matchedLocation,
        isAuthenticated: authState.isAuthenticated,
        isGuest: authState.isGuest,
        isOnboardingComplete: isOnboardingComplete,
      );
    },
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        pageBuilder: (context, state) {
          return _fadeTransitionPage(const SplashScreen());
        },
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        pageBuilder: (context, state) {
          return _fadeTransitionPage(const OnboardingScreen());
        },
      ),
      GoRoute(
        path: AppRoutes.login,
        pageBuilder: (context, state) {
          return _fadeTransitionPage(const LoginScreen());
        },
      ),
      GoRoute(
        path: AppRoutes.otp,
        pageBuilder: (context, state) {
          return _fadeTransitionPage(const OtpScreen());
        },
      ),
      GoRoute(
        path: AppRoutes.main,
        pageBuilder: (context, state) {
          return _fadeTransitionPage(const MainNavigationScreen());
        },
      ),
    ],
  );
});
