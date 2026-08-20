import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/otp_screen.dart';
import '../../features/customer_registration/domain/models/customer_profile_completion_state.dart';
import '../../features/customer_registration/presentation/providers/customer_registration_providers.dart';
import '../../features/customer_registration/presentation/screens/complete_profile_screen.dart';
import '../../features/navigation/presentation/screens/main_navigation_screen.dart';
import '../../features/onboarding/presentation/provider/onboarding_provider.dart';
import '../../features/onboarding/presentation/screens/onboarding_screen.dart';
import '../../features/reservation/presentation/screens/reservation_confirmation_screen.dart';
import '../../features/reservation/presentation/screens/reservation_detail_screen.dart';
import '../../features/reservation/presentation/screens/reservation_flow_screen.dart';
import '../../features/takeaway/presentation/screens/takeaway_guest_entry_screen.dart';
import '../auth/real_customer_check.dart';
import 'app_route_guard.dart';
import 'app_routes.dart';

/// Bridges the Riverpod state [AppRouteGuard] depends on into `GoRouter`'s
/// `refreshListenable`, so a state change that happens without an
/// explicit navigation call (e.g. a login/logout elsewhere in the app)
/// still re-runs the guard against the current location instead of
/// leaving a stale redirect decision in place.
class _RouterRefreshListenable extends ChangeNotifier {
  _RouterRefreshListenable(Ref ref) {
    ref.listen(authProvider, (previous, next) => notifyListeners());
    ref.listen(
      onboardingCompleteProvider,
      (previous, next) => notifyListeners(),
    );
    // Customer Registration CR.1 — a live Firestore-derived value (see
    // `customerProfileCompletionStateProvider`'s own doc comment): once a
    // real customer's `customers`/`tenantCustomers` documents actually
    // resolve or change (loading -> complete, incomplete -> complete
    // after a successful "Profilini Tamamla" submit), this re-runs the
    // guard against the current location instead of leaving a stale
    // redirect decision in place — the same reason `authProvider`/
    // `onboardingCompleteProvider` are listened to here.
    ref.listen(
      customerProfileCompletionStateProvider,
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

/// The app's router. Scoped to the Onboarding → Login/Otp → Main entry
/// flow only (per ADR-006) — not a migration of every feature screen.
/// `main` is intentionally left as a single opaque route rather than a
/// `StatefulShellRoute`: giving `MainNavigationScreen` its own nested
/// shell/tab routes would mean redesigning its existing internal
/// bottom-nav logic, which is out of scope for this foundation.
///
/// **No dedicated splash route** (startup routing cleanup, splash
/// removal) — `bootstrapApp()` (`lib/bootstrap/app_bootstrap.dart`)
/// already resolves the persisted-session check before `runApp()`, so by
/// the time this provider is first read, `authProvider`'s state is
/// already correct. `initialLocation` reads it once, here, with `ref
/// .read` (not `ref.watch` — matches the `redirect` callback's own
/// pattern below; this provider only needs the value at construction
/// time, ongoing changes are what `redirect`/`refreshListenable` are for)
/// to land the very first frame on the correct destination directly — no
/// intermediate screen, no timer.
final appRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.read(authProvider);
  final isOnboardingComplete = ref.read(onboardingCompleteProvider);
  final signedIn = authState.isAuthenticated || authState.isGuest;
  final initialLocation = signedIn
      ? AppRoutes.main
      : (isOnboardingComplete ? AppRoutes.login : AppRoutes.onboarding);

  return GoRouter(
    initialLocation: initialLocation,
    refreshListenable: _RouterRefreshListenable(ref),
    redirect: (context, state) {
      final authState = ref.read(authProvider);
      final isOnboardingComplete = ref.read(onboardingCompleteProvider);
      final realCustomer = isRealCustomer(authState);
      // Customer Registration CR.1 — reduced to a single, feature-
      // agnostic bool before ever reaching `AppRouteGuard.resolve`, which
      // stays a pure function of plain booleans, never a
      // `CustomerProfileCompletionPhase` or any other feature type (see
      // that function's own doc comment).
      final completionState = ref.read(customerProfileCompletionStateProvider);
      final needsProfileCompletion = realCustomer &&
          completionState.phase != CustomerProfileCompletionPhase.complete;
      return AppRouteGuard.resolve(
        location: state.matchedLocation,
        isAuthenticated: authState.isAuthenticated,
        isGuest: authState.isGuest,
        isOnboardingComplete: isOnboardingComplete,
        isRealCustomer: realCustomer,
        needsProfileCompletion: needsProfileCompletion,
      );
    },
    routes: [
      GoRoute(
        path: AppRoutes.onboarding,
        pageBuilder: (context, state) {
          return _fadeTransitionPage(const OnboardingScreen());
        },
      ),
      GoRoute(
        path: AppRoutes.login,
        pageBuilder: (context, state) {
          // Faz R.2 — forwarded, unvalidated here (LoginScreen re-forwards
          // it verbatim to OtpScreen without acting on it itself; OtpScreen
          // is the one place it's ever consumed, and re-sanitizes it there
          // — defense in depth, see AppRouteGuard.sanitizeReturnTo's own
          // doc comment).
          return _fadeTransitionPage(
            LoginScreen(returnTo: state.uri.queryParameters['returnTo']),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.otp,
        pageBuilder: (context, state) {
          return _fadeTransitionPage(
            OtpScreen(returnTo: state.uri.queryParameters['returnTo']),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.main,
        pageBuilder: (context, state) {
          return _fadeTransitionPage(const MainNavigationScreen());
        },
      ),
      // Customer Registration CR.1 — a first-time real customer lands
      // here (via `AppRouteGuard.resolve`'s `needsProfileCompletion`
      // branch) between a successful OTP and `main` ever becoming
      // reachable.
      GoRoute(
        path: AppRoutes.completeProfile,
        pageBuilder: (context, state) {
          return _fadeTransitionPage(const CompleteProfileScreen());
        },
      ),
      // Faz D.4 — public, login-free Gel Al QR guest entry. Never behind
      // the onboarding/login/OTP gate — see `AppRouteGuard.resolve`'s own
      // explicit bypass for this prefix, checked before either
      // signed-in/not-signed-in branch.
      GoRoute(
        path: '${AppRoutes.takeawayGuestPrefix}/:token',
        pageBuilder: (context, state) {
          return _fadeTransitionPage(
            TakeawayGuestEntryScreen(token: state.pathParameters['token']!),
          );
        },
      ),
      // Faz R.2 — customer reservation flow. Real-phone-auth-gated by
      // `AppRouteGuard.resolve`'s own dedicated branch above, not by
      // anything screen-local. `/reservation/confirmation/:id` is
      // registered before `/reservation/:id` is even relevant here since
      // both are top-level (sibling, not nested) routes distinguished by
      // segment count — go_router matches structurally, no ordering
      // trick needed, but declaring the more specific one first keeps the
      // route list itself readable.
      GoRoute(
        path: AppRoutes.reservationPrefix,
        pageBuilder: (context, state) {
          return _fadeTransitionPage(const ReservationFlowScreen());
        },
      ),
      GoRoute(
        path: '${AppRoutes.reservationConfirmationPrefix}/:reservationId',
        pageBuilder: (context, state) {
          return _fadeTransitionPage(
            ReservationConfirmationScreen(
              reservationId: state.pathParameters['reservationId']!,
            ),
          );
        },
      ),
      GoRoute(
        path: '${AppRoutes.reservationPrefix}/:reservationId',
        pageBuilder: (context, state) {
          return _fadeTransitionPage(
            ReservationDetailScreen(
              reservationId: state.pathParameters['reservationId']!,
            ),
          );
        },
      ),
    ],
  );
});
