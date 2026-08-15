import '../router/app_route_guard.dart';
import '../router/app_routes.dart';

/// Faz R.3C §13 — resolves a tapped push notification's data payload
/// (`reservationNotificationDelivery.ts`'s `data: { reservationId,
/// eventType }`) into a safe, internal route to navigate to, or `null` if
/// the payload doesn't carry a usable [reservationId].
///
/// Deliberately pure (no `FirebaseMessaging`/`BuildContext` dependency) so
/// it's testable as plain function calls. Reuses
/// [AppRouteGuard.sanitizeReturnTo] — the exact same allowlist this
/// codebase already trusts for `returnTo` deep-link values — rather than
/// inventing a second validation rule: a push payload is exactly as
/// untrusted as a query parameter, so it goes through the same gate. This
/// is also what makes an open redirect structurally impossible here: the
/// payload only ever contributes a `reservationId` used to *build*
/// [AppRoutes.reservationDetail], never a raw URL/path taken as-is.
abstract final class ReservationNotificationTapRouter {
  ReservationNotificationTapRouter._();

  static String? resolveRoute(Map<String, dynamic> data) {
    final reservationId = data['reservationId'];
    if (reservationId is! String || reservationId.isEmpty) return null;
    final candidate = AppRoutes.reservationDetail(reservationId);
    return AppRouteGuard.sanitizeReturnTo(candidate);
  }
}
