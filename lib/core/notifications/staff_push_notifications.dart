import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'courier_push_tap_router.dart';

/// 2026-11-12 (Faz 3c) — shows a courier-pool push (ADR-078) as a system
/// notification while the app is in the foreground (product owner choice:
/// a real notification, not an in-app banner). In the background/terminated
/// state Android and iOS show FCM's own `notification` payload; this class
/// only covers the foreground, where FCM shows nothing by itself.
///
/// Android: the high-importance `courier_alerts` channel the server
/// targets (`COURIER_ALERTS_CHANNEL_ID` in `courierNotifications.ts`).
abstract interface class StaffPushNotifications {
  /// Prepares the plugin and the Android channel; [onTap] receives the
  /// push data of a tapped foreground notification.
  Future<void> initialize(void Function(Map<String, dynamic> data) onTap);

  /// Shows [message] if it is a courier-pool push; ignores anything else.
  Future<void> showForeground(RemoteMessage message);
}

class LocalStaffPushNotifications implements StaffPushNotifications {
  LocalStaffPushNotifications({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;
  int _nextId = 0;

  static const _channel = AndroidNotificationChannel(
    'courier_alerts',
    'Kurye ve havuz bildirimleri',
    description: 'Yeni kurye talepleri ve size atanan paketler.',
    importance: Importance.high,
  );

  @override
  Future<void> initialize(
      void Function(Map<String, dynamic> data) onTap) async {
    if (_initialized) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          // Permission is asked by FirebaseMessaging.requestPermission()
          // at token registration — not twice.
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestSoundPermission: false,
            requestBadgePermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (response) {
          final payload = response.payload;
          if (payload == null || payload.isEmpty) return;
          try {
            final data = jsonDecode(payload);
            if (data is Map<String, dynamic>) onTap(data);
          } catch (_) {
            // A malformed payload just opens nothing.
          }
        },
      );
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_channel);
      _initialized = true;
    } catch (_) {
      // Best effort, like FcmRegistrationService: a device that cannot show
      // local notifications still gets background pushes and the live
      // in-app lists.
    }
  }

  @override
  Future<void> showForeground(RemoteMessage message) async {
    if (!_initialized || !CourierPushTapRouter.handles(message.data)) return;
    final notification = message.notification;
    try {
      await _plugin.show(
        id: _nextId++,
        title: notification?.title,
        body: notification?.body,
        payload: jsonEncode(message.data),
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _channel.id,
            _channel.name,
            channelDescription: _channel.description,
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentSound: true,
          ),
        ),
      );
    } catch (_) {
      // Best effort — see initialize().
    }
  }
}

class NoOpStaffPushNotifications implements StaffPushNotifications {
  const NoOpStaffPushNotifications();

  @override
  Future<void> initialize(
      void Function(Map<String, dynamic> data) onTap) async {}

  @override
  Future<void> showForeground(RemoteMessage message) async {}
}
