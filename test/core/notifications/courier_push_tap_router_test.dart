import 'package:abakus_one_v2/core/notifications/courier_push_tap_router.dart';
import 'package:abakus_one_v2/core/notifications/staff_push_notifications.dart';
import 'package:abakus_one_v2/core/router/app_routes.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-11-12 (Faz 3c) — where a tapped courier-pool push opens.
void main() {
  test('a staff pool-request push opens the delivery-dispatch board', () {
    final data = {'type': 'courierPoolRequest', 'requestId': 'r1'};
    expect(CourierPushTapRouter.handles(data), isTrue);
    expect(CourierPushTapRouter.resolveRoute(data),
        '${AppRoutes.admin}?nav=delivery-dispatch');
  });

  test('courier pushes open the staff shell (Kurye Ekranım)', () {
    for (final type in [
      'courierAssigned',
      'courierReserved',
      'courierRequestRejected',
    ]) {
      expect(CourierPushTapRouter.resolveRoute({'type': type}), AppRoutes.admin,
          reason: type);
    }
  });

  test('anything else is left to the reservation router', () {
    final data = {'reservationId': 'res-1'};
    expect(CourierPushTapRouter.handles(data), isFalse);
    expect(CourierPushTapRouter.resolveRoute(data), isNull);
  });

  test('the no-op notifier (Windows / tests) never throws', () async {
    const notifier = NoOpStaffPushNotifications();
    await notifier.initialize((_) {});
    await notifier.showForeground(const RemoteMessage(
        data: {'type': 'courierAssigned', 'orderId': 'o1'}));
  });
}
