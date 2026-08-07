import 'app_routes.dart';

/// Pure, presentation-independent redirect/guard logic for the app's
/// entry flow (Onboarding → Login/Otp → Main). Deliberately not a method
/// on `GoRouter`/a widget, and takes no `BuildContext` — testable as plain
/// function calls against plain booleans.
///
/// Encodes the one hard rule this router foundation exists to preserve:
/// [AppRoutes.main] is reachable only through a valid persistent session
/// (`isAuthenticated`), successful OTP verification (which also sets
/// `isAuthenticated`), or explicit guest continuation (`isGuest`) — never
/// by directly navigating/deep-linking to it.
///
/// **No dedicated splash route** (startup routing cleanup, splash
/// removal) — `isAuthenticated`/`isGuest` are always already resolved by
/// the time this guard ever runs (`bootstrapApp()` resolves the persisted
/// session before `runApp()`), so there is no "unresolved session check"
/// state left for a splash screen to protect the timing of.
abstract final class AppRouteGuard {
  AppRouteGuard._();

  /// Returns the path the router should redirect to instead of
  /// [location], or `null` if [location] is already correct and no
  /// redirect is needed.
  static String? resolve({
    required String location,
    required bool isAuthenticated,
    required bool isGuest,
    required bool isOnboardingComplete,
  }) {
    final signedIn = isAuthenticated || isGuest;

    if (signedIn) {
      if (location == AppRoutes.main) return null;
      return AppRoutes.main;
    }

    // Not signed in. Every not-signed-in-only route redirects to the same
    // landing every other not-signed-in case computes below (onboarding
    // if incomplete, else login) — `main` requires proof of a real
    // session, and this is where someone lands instead if they don't have
    // one, whether they arrived by direct navigation, a stale deep link,
    // or a browser refresh; there's no separate "not yet checked" state
    // to route through first.
    final notSignedInLanding =
        isOnboardingComplete ? AppRoutes.login : AppRoutes.onboarding;

    if (location == AppRoutes.main) {
      return notSignedInLanding;
    }

    // Every other not-signed-in route is fine to enter directly — none of
    // them depend on an unresolved session check to render correctly.
    // Onboarding is the one exception: once already completed, it's
    // skipped in favor of login.
    if (location == AppRoutes.onboarding && isOnboardingComplete) {
      return AppRoutes.login;
    }

    return null;
  }
}
