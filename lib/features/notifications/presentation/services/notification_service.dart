import '../../domain/models/notification_payload.dart';
import '../../domain/repositories/notification_repository.dart';
import 'local_notification_abstraction.dart';

class NotificationService {
  final NotificationRepository _repository;
  final LocalNotificationAbstraction _localNotifications;

  NotificationService({
    required NotificationRepository repository,
    required LocalNotificationAbstraction localNotifications,
  })  : _repository = repository,
        _localNotifications = localNotifications;

  Future<void> initializeService() async {
    await _localNotifications.initializeLocalNotifications();
    await setupNotificationHandlers();
  }

  Future<NotificationPermission> checkAndRequestPermission() async {
    return NotificationPermission.granted;
  }

  Future<void> setupNotificationHandlers() async {
    // Foreground Handler Simülasyonu
  }

  static Future<void> handleBackgroundMessage(
      Map<String, dynamic> message) async {
    // Background / Terminated Handler Simülasyonu
  }

  Future<void> handleNotificationClick(NotificationPayload payload) async {
    if (payload.deepLinkUrl != null && payload.deepLinkUrl!.isNotEmpty) {
      _executeDeepLinkRoute(payload.deepLinkUrl!);
    }
    await _repository.logNotificationReceived(payload);
  }

  void _executeDeepLinkRoute(String url) {
    // Yönlendirme modülü lojiği buraya bağlanacaktır.
  }
}
