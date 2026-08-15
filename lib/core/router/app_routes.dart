/// Centrally defined route paths — screens never hard-code a path string
/// directly; every navigation call site uses one of these constants.
abstract final class AppRoutes {
  AppRoutes._();

  static const String onboarding = '/onboarding';
  static const String login = '/login';
  static const String otp = '/otp';
  static const String main = '/main';

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
