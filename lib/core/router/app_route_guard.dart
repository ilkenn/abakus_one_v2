import 'app_routes.dart';

/// Pure, presentation-independent redirect/guard logic for the app's
/// entry flow (Splash → Onboarding → Login/Otp → Main). Deliberately not
/// a method on `GoRouter`/a widget, and takes no `BuildContext` — testable
/// as plain function calls against plain booleans.
///
/// Encodes the one hard rule this router foundation exists to preserve:
/// [AppRoutes.main] is reachable only through a valid persistent session
/// (`isAuthenticated`), successful OTP verification (which also sets
/// `isAuthenticated`), or explicit guest continuation (`isGuest`) — never
/// by directly navigating/deep-linking to it.
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
      // Splash is exempt: it is the one screen that decides, on its own
      // timeline, when to hand off to `main` (it awaits its full brand
      // animation *and* the persisted-session check before navigating
      // itself). Without this exemption, `isAuthenticated` flipping true
      // mid-animation — routed here via the router's refreshListenable —
      // would yank the user straight to `main` and cut the animation
      // short. Every other signed-in entry-flow screen (login/otp/
      // onboarding) has no such reason to be re-entered, so it's always
      // redirected to `main` instead.
      if (location == AppRoutes.main || location == AppRoutes.splash) {
        return null;
      }
      return AppRoutes.main;
    }

    // Not signed in. `main` requires proof of a real session, but
    // `isAuthenticated` only reflects a *resolved* persisted-session
    // check, and today that check only runs from Splash's own logic. A
    // direct/deep-link visit to `main` without having gone through Splash
    // yet is routed back to it, so it gets a real answer rather than this
    // guard assuming "not yet checked" means "not authenticated." This is
    // also what makes a browser refresh at `main` deterministic: it
    // always resolves through the same single decision point instead of
    // guessing.
    if (location == AppRoutes.main) {
      return AppRoutes.splash;
    }

    // Every other not-signed-in route is fine to enter directly — none of
    // them depend on an unresolved session check to render correctly.
    // Onboarding is the one exception: once already completed, it's
    // skipped in favor of login, matching Splash's own existing decision.
    if (location == AppRoutes.onboarding && isOnboardingComplete) {
      return AppRoutes.login;
    }

    return null;
  }
}
