import 'package:abakus_one_v2/core/notifications/reservation_notification_tap_router.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ReservationNotificationTapRouter.resolveRoute', () {
    test('resolves a valid reservationId to the canonical detail route', () {
      final route = ReservationNotificationTapRouter.resolveRoute(
        {
          'reservationId': 'reservation-123',
          'eventType': 'reservationConfirmed'
        },
      );

      expect(route, '/reservation/reservation-123');
    });

    test('returns null when reservationId is missing', () {
      final route = ReservationNotificationTapRouter.resolveRoute(
        {'eventType': 'reservationConfirmed'},
      );

      expect(route, isNull);
    });

    test('returns null when reservationId is empty', () {
      final route = ReservationNotificationTapRouter.resolveRoute(
        {'reservationId': ''},
      );

      expect(route, isNull);
    });

    test('returns null when reservationId is not a string', () {
      final route = ReservationNotificationTapRouter.resolveRoute(
        {'reservationId': 12345},
      );

      expect(route, isNull);
    });

    // Faz R.3C §13/§19 — an arbitrary external URL smuggled into the
    // payload must never be accepted; only the app's own sanitized
    // reservation-detail shape survives `AppRouteGuard.sanitizeReturnTo`.
    test('an attempted open-redirect payload never produces a route', () {
      final route = ReservationNotificationTapRouter.resolveRoute(
        {'reservationId': 'https://evil.example.com'},
      );

      // The candidate path becomes `/reservation/https://evil.example.com`,
      // which does not match the strict reservation-id character
      // allowlist, so it is rejected — never trusted as-is.
      expect(route, isNull);
    });

    test('a path-traversal-shaped reservationId is rejected', () {
      final route = ReservationNotificationTapRouter.resolveRoute(
        {'reservationId': '../../etc/passwd'},
      );

      expect(route, isNull);
    });
  });
}
