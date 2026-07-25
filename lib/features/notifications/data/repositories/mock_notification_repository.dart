import '../../domain/models/notification_payload.dart';
import '../../domain/repositories/notification_repository.dart';

class MockNotificationRepository implements NotificationRepository {
  @override
  Future<void> saveToken(String token) async {
    // Mock token kaydetme lojiği köprüsü
  }

  @override
  Future<void> deleteToken() async {
    // Mock token silme lojiği köprüsü
  }

  @override
  Future<void> logNotificationReceived(NotificationPayload payload) async {
    // Mock bildirim loglama köprüsü
  }
}
