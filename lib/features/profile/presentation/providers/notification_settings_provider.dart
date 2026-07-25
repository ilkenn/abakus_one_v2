import 'package:flutter_riverpod/flutter_riverpod.dart';

class NotificationSettingsState {
  final bool orderStatus;
  final bool campaigns;
  final bool newProducts;
  final bool loyaltyPoints;
  final bool emailNotifications;
  final bool smsNotifications;

  const NotificationSettingsState({
    required this.orderStatus,
    required this.campaigns,
    required this.newProducts,
    required this.loyaltyPoints,
    required this.emailNotifications,
    required this.smsNotifications,
  });

  NotificationSettingsState copyWith({
    bool? orderStatus,
    bool? campaigns,
    bool? newProducts,
    bool? loyaltyPoints,
    bool? emailNotifications,
    bool? smsNotifications,
  }) {
    return NotificationSettingsState(
      orderStatus: orderStatus ?? this.orderStatus,
      campaigns: campaigns ?? this.campaigns,
      newProducts: newProducts ?? this.newProducts,
      loyaltyPoints: loyaltyPoints ?? this.loyaltyPoints,
      emailNotifications: emailNotifications ?? this.emailNotifications,
      smsNotifications: smsNotifications ?? this.smsNotifications,
    );
  }
}

class NotificationSettingsNotifier extends Notifier<NotificationSettingsState> {
  @override
  NotificationSettingsState build() {
    return const NotificationSettingsState(
      orderStatus: true,
      campaigns: false,
      newProducts: true,
      loyaltyPoints: true,
      emailNotifications: false,
      smsNotifications: false,
    );
  }

  void toggleOrderStatus(bool value) =>
      state = state.copyWith(orderStatus: value);
  void toggleCampaigns(bool value) => state = state.copyWith(campaigns: value);
  void toggleNewProducts(bool value) =>
      state = state.copyWith(newProducts: value);
  void toggleLoyaltyPoints(bool value) =>
      state = state.copyWith(loyaltyPoints: value);
  void toggleEmailNotifications(bool value) =>
      state = state.copyWith(emailNotifications: value);
  void toggleSmsNotifications(bool value) =>
      state = state.copyWith(smsNotifications: value);
}

final notificationSettingsProvider =
    NotifierProvider<NotificationSettingsNotifier, NotificationSettingsState>(
  () {
    return NotificationSettingsNotifier();
  },
);
