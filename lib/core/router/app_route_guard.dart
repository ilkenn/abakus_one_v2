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

  /// Faz R.2 — the exact, allowlisted shapes a `returnTo` value may take.
  /// A strict allowlist, not a blocklist: only the app's own three
  /// reservation routes are ever accepted, so there is no scheme, no
  /// `//host` protocol-relative form, and no arbitrary path an attacker
  /// could smuggle through a crafted deep link (`/login?returnTo=...`) —
  /// open redirect is structurally impossible, not merely discouraged.
  static final RegExp _reservationDetailPattern =
      RegExp(r'^/reservation/[A-Za-z0-9_-]{1,200}$');
  static final RegExp _reservationConfirmationPattern =
      RegExp(r'^/reservation/confirmation/[A-Za-z0-9_-]{1,200}$');

  /// Returns [location] unchanged if it matches one of the three known
  /// reservation route shapes, or `null` if it doesn't — `null` means
  /// "not a safe returnTo target," never "trust it anyway." Applied both
  /// where a `returnTo` is generated ([resolve] below) and, independently,
  /// wherever one is consumed ([OtpScreen]'s success handler) — defense in
  /// depth, since `/login`/`/otp` are reachable by direct deep link with an
  /// arbitrary query string, not only via a redirect this guard itself
  /// produced.
  static String? sanitizeReturnTo(String? location) {
    if (location == null) return null;
    if (location == AppRoutes.reservationPrefix) return location;
    if (_reservationConfirmationPattern.hasMatch(location)) return location;
    if (_reservationDetailPattern.hasMatch(location)) return location;
    return null;
  }

  /// Returns the path the router should redirect to instead of
  /// [location], or `null` if [location] is already correct and no
  /// redirect is needed.
  static String? resolve({
    required String location,
    required bool isAuthenticated,
    required bool isGuest,
    required bool isOnboardingComplete,
    required bool isRealCustomer,
    bool needsProfileCompletion = false,
  }) {
    // Faz D.4 — the Gel Al QR guest flow is public by design: a customer
    // scanning a kasadaki QR has not signed in to anything yet, and must
    // never be bounced through onboarding/login/OTP just to view a menu
    // and place a takeaway order. This bypass is checked first,
    // unconditionally, before either branch below — critically including
    // the `signedIn` branch, which otherwise redirects *every* location to
    // [AppRoutes.main] once a session (real or guest) exists; without this
    // check, an already-signed-in customer opening a QR link would be
    // bounced straight past the QR flow into the main app shell instead.
    if (location.startsWith(AppRoutes.takeawayGuestPrefix)) return null;

    // AP-3 — the dine-in table QR guest flow is public by design for the
    // exact same reason the Gel Al QR flow immediately above is: a
    // customer opening a table's QR link has not signed in to anything
    // yet, and must never be bounced through onboarding/login/OTP (nor,
    // for an already-signed-in customer, swept straight to `main` by the
    // `signedIn` branch below) just to sit at their table.
    if (location.startsWith(AppRoutes.tableGuestPrefix)) return null;

    // AP-2 Stage B — Admin/staff authorization is a wholly separate
    // identity system from the customer signed-in/guest concept this
    // guard otherwise governs (mirrors [AppRoutes.admin]'s own doc
    // comment). Bypassed here for the same reason the takeaway QR prefix
    // is: [AdminShellScreen] performs its own real, internal staff-session
    // check and redirects to `StaffSignInScreen`/`AdminUnauthorizedScreen`
    // itself — this guard must never intercept that with an unrelated
    // customer-session redirect (a signed-out customer opening `/admin`
    // must reach the real staff sign-in flow, not `/login`).
    if (location.startsWith(AppRoutes.admin)) return null;

    // AP-2 final wiring — same reasoning as [AppRoutes.admin] immediately
    // above, one tier up: Platform Owner authorization is a wholly
    // separate identity system this guard must never intercept.
    if (location.startsWith(AppRoutes.platform)) return null;

    // Faz R.2 — reservation routes need REAL phone-auth specifically,
    // stricter than the generic "signedIn" (authenticated OR guest)
    // concept the rest of this guard uses for reaching [AppRoutes.main].
    // Checked before the generic `signedIn` branch below, which would
    // otherwise force ANY signed-in (including merely-guest) user straight
    // to `main` without ever reaching this branch.
    if (location.startsWith(AppRoutes.reservationPrefix)) {
      if (isRealCustomer) return null;
      final landing =
          isOnboardingComplete ? AppRoutes.login : AppRoutes.onboarding;
      // Carrying `returnTo` through an incomplete onboarding is
      // deliberately not attempted — by the time a user can reach a
      // location under this prefix via the in-app "Rezervasyon" tap, they
      // are already at `main`, which itself requires onboarding to be
      // complete; this branch of the cold-deep-link edge case is disclosed
      // as an accepted, minor scope limit, not silently handled.
      return isOnboardingComplete
          ? AppRoutes.withReturnTo(landing, location)
          : landing;
    }

    final signedIn = isAuthenticated || isGuest;

    if (signedIn) {
      // Customer Registration CR.1 — a real, phone-authenticated customer
      // whose canonical registration is not yet complete is redirected to
      // [AppRoutes.completeProfile] from EVERY other signed-in route,
      // never just `main` — this is what closes "an incomplete customer
      // must not be able to manually deep-link around the gate," the
      // audit's own locked requirement. [needsProfileCompletion] is
      // already the caller's precomputed `isRealCustomer && phase !=
      // complete` (see `app_router.dart`) — this function never itself
      // reads Firestore or knows what "complete" means beyond that one
      // bool, keeping it exactly as pure as every other parameter here.
      if (location == AppRoutes.completeProfile) {
        // Already complete (or never needed the gate at all, e.g. a
        // guest) — nothing to do here, redirected onward like any other
        // signed-in route below. Never a redirect back to itself.
        if (!needsProfileCompletion) return AppRoutes.main;
        return null;
      }
      if (needsProfileCompletion) return AppRoutes.completeProfile;

      if (location == AppRoutes.main) return null;
      return AppRoutes.main;
    }

    // Not signed in. Every not-signed-in-only route redirects to the same
    // landing every other not-signed-in case computes below (onboarding
    // if incomplete, else login) — `main` requires proof of a real
    // session, and this is where someone lands instead if they don't have
    // one, whether they arrived by direct navigation, a stale deep link,
    // or a browser refresh; there's no separate "not yet checked" state
    // to route through first. `completeProfile` needs the identical
    // protection — without it, a stale/bookmarked link would render the
    // registration form for a signed-out visitor.
    final notSignedInLanding =
        isOnboardingComplete ? AppRoutes.login : AppRoutes.onboarding;

    if (location == AppRoutes.main || location == AppRoutes.completeProfile) {
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
