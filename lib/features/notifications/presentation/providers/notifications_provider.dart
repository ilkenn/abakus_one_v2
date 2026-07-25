import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/notification_settings_model.dart';

// Mevcut bildirim sayaçları ve listeleriyle entegre modern Riverpod Notifier katmanı
class NotificationSettingsNotifier extends Notifier<NotificationSettingsModel> {
  @override
  NotificationSettingsModel build() {
    return const NotificationSettingsModel();
  }

  void toggleOrderStatus(bool value) =>
      state = state.copyWith(orderStatus: value);
  void toggleCourierApproaching(bool value) =>
      state = state.copyWith(courierApproaching: value);
  void toggleCampaigns(bool value) => state = state.copyWith(campaigns: value);
  void toggleCoupons(bool value) => state = state.copyWith(coupons: value);
  void toggleLoyaltyPoints(bool value) =>
      state = state.copyWith(loyaltyPoints: value);

  void requestSystemPermission() {
    // Gerçek push notification servis bağlantı noktası simülasyonu
    state = state.copyWith(systemPermissionStatus: 'granted');
  }

  void denySystemPermission() {
    state = state.copyWith(systemPermissionStatus: 'denied');
  }
}

final notificationSettingsProvider =
    NotifierProvider<NotificationSettingsNotifier, NotificationSettingsModel>(
  () {
    return NotificationSettingsNotifier();
  },
);

// Geriye dönük okunmamış bildirim merkezi senkronizasyonunun korunması
final unreadNotificationsCountProvider = Provider<int>((ref) {
  return 2; // Sabit mock okunmamış sayaç verisi korunmuştur
});
