/// Centrally defined route paths — screens never hard-code a path string
/// directly; every navigation call site uses one of these constants.
abstract final class AppRoutes {
  AppRoutes._();

  static const String onboarding = '/onboarding';
  static const String login = '/login';
  static const String otp = '/otp';
  static const String main = '/main';

  /// Customer Registration CR.1 — the mandatory "Profilini Tamamla"
  /// screen a first-time, real phone-authenticated customer is routed to
  /// before `main` ever becomes reachable. See [AppRouteGuard.resolve]'s
  /// own `needsProfileCompletion` branch — this route is never entered by
  /// a guest or an unauthenticated visitor (there is nothing for either
  /// to complete).
  static const String completeProfile = '/complete-profile';

  /// Faz D.4 — the public, login-free Gel Al QR guest entry point. A
  /// customer scanning a kasadaki QR lands here directly, with no
  /// onboarding/login/OTP gate — see [AppRouteGuard.resolve]'s explicit
  /// bypass for any location under this prefix. `:token` is the opaque
  /// `takeawayQrCodes` token `resolveTakeawayQrToken`/
  /// `openTakeawayGuestSession` independently re-resolve server-side; the
  /// client never derives organization/restaurant/branch scope from it
  /// directly.
  static const String takeawayGuestPrefix = '/takeaway';

  static String takeawayGuest(String token) => '$takeawayGuestPrefix/$token';

  /// AP-3 — the public, login-free dine-in table QR guest entry point,
  /// mirroring [takeawayGuestPrefix] exactly: a customer opening a table's
  /// QR link (by scanning it, tapping it, or any other way the link
  /// reaches them) lands here directly, with no onboarding/login/OTP gate
  /// — see [AppRouteGuard.resolve]'s explicit bypass for any location
  /// under this prefix. `:token` is the opaque `tableQrCodes` token
  /// `resolveTableQrToken`/`openTableGuestSession` independently
  /// re-resolve server-side; the client never derives organization/
  /// restaurant/branch/table scope from it directly.
  static const String tableGuestPrefix = '/table';

  static String tableGuest(String token) => '$tableGuestPrefix/$token';

  /// AP-2 Stage B — the Admin/staff shell entry point. Staff/Platform
  /// authorization is an entirely separate identity system from the
  /// customer [authProvider]/[AppRouteGuard] stack (Firebase email/
  /// password + custom claims vs. customer phone+OTP) — this route is
  /// bypassed by the customer-facing guard exactly like
  /// [takeawayGuestPrefix], and [AdminShellScreen] performs its own real,
  /// internal `actorSessionProvider` check before rendering anything
  /// (see its own `build()` — already real, not new this phase),
  /// mirroring the screen-level "deny by default" pattern
  /// `ModuleEntitlementGate` already established elsewhere.
  static const String admin = '/admin';

  /// AP-2 final wiring — the Platform Owner console entry point.
  /// Deliberately NOT linked from anywhere in the ordinary customer or
  /// tenant-Admin UI — no button, no nav item, nothing in
  /// [AdminShellScreen] or the onboarding/login flow references this
  /// constant. A real deep link/typed URL is the only way in, matching
  /// this console's own "structural separation from ordinary tenant
  /// Admin" requirement: Platform Owner authorization is a wholly
  /// separate identity system (ADR-025) that must never be discoverable
  /// from, or confusable with, the tenant-facing surface. Bypassed by
  /// [AppRouteGuard.resolve] exactly like [admin] — [PlatformShellScreen]
  /// performs its own real, internal `platformActorSessionProvider` check
  /// and redirects to [PlatformSignInScreen] itself.
  static const String platform = '/platform';

  /// Faz R.2 — the customer reservation flow's entry route. Requires real
  /// phone-auth ([AppRouteGuard.resolve]'s own `isRealCustomer`-gated
  /// branch, stricter than the generic "signed in" concept the rest of
  /// this guard uses) — an unauthenticated or guest-only visitor is
  /// redirected to login/onboarding with this location preserved as a
  /// sanitized `returnTo`, landing back here after a successful OTP.
  static const String reservationPrefix = '/reservation';

  /// The confirmation screen shown immediately after a successful
  /// `submitReservation` call.
  static const String reservationConfirmationPrefix =
      '/reservation/confirmation';

  static String reservationDetail(String reservationId) =>
      '$reservationPrefix/$reservationId';

  static String reservationConfirmation(String reservationId) =>
      '$reservationConfirmationPrefix/$reservationId';

  /// Appends [returnTo] (already-sanitized — see
  /// [AppRouteGuard.sanitizeReturnTo]) as a query parameter onto
  /// [basePath], so a location the guard redirected away from can be
  /// carried through login/OTP and restored on success.
  static String withReturnTo(String basePath, String returnTo) =>
      '$basePath?returnTo=${Uri.encodeQueryComponent(returnTo)}';
}
