import '../models/notification_payload.dart';

abstract interface class NotificationRepository {
  Future<void> saveToken(String token);
  Future<void> deleteToken();
  Future<void> logNotificationReceived(NotificationPayload payload);
}
