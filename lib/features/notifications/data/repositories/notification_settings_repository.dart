import '../../domain/models/notification_settings_model.dart';

class NotificationSettingsRepository {
  // Gelecekte SharedPreferences veya Local Storage entegrasyonu için köprü noktası
  Future<NotificationSettingsModel> loadSettings() async {
    return const NotificationSettingsModel();
  }

  Future<void> saveSettings(NotificationSettingsModel settings) async {
    // Kaydetme lojikleri buraya eklenecektir
  }
}
