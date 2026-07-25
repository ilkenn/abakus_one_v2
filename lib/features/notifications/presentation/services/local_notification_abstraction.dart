import '../../domain/models/notification_payload.dart';

abstract interface class LocalNotificationAbstraction {
  Future<void> initializeLocalNotifications();
  Future<void> showLocalNotification(NotificationPayload payload);
  Future<void> cancelAllNotifications();
}

class MockLocalNotificationService implements LocalNotificationAbstraction {
  @override
  Future<void> initializeLocalNotifications() async {
    // Yerel bildirim eklenti ilk kurulum simülasyonu
  }

  @override
  Future<void> showLocalNotification(NotificationPayload payload) async {
    // Yerel sistem tepsisinde bildirim gösterme simülasyonu
  }

  @override
  Future<void> cancelAllNotifications() async {
    // Tüm anlık yerel bildirimleri iptal etme simülasyonu
  }
}
