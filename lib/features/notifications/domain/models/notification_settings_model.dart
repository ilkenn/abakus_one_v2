class NotificationSettingsModel {
  final bool orderStatus;
  final bool courierApproaching;
  final bool campaigns;
  final bool coupons;
  final bool loyaltyPoints;
  final bool accountSecurity; // Önemli hesap bildirimleri (Zorunlu)
  final String systemPermissionStatus; // 'granted', 'denied', 'prompt'

  const NotificationSettingsModel({
    this.orderStatus = true,
    this.courierApproaching = true,
    this.campaigns = true,
    this.coupons = true,
    this.loyaltyPoints = true,
    this.accountSecurity = true,
    this.systemPermissionStatus = 'prompt',
  });

  NotificationSettingsModel copyWith({
    bool? orderStatus,
    bool? courierApproaching,
    bool? campaigns,
    bool? coupons,
    bool? loyaltyPoints,
    bool? accountSecurity,
    String? systemPermissionStatus,
  }) {
    return NotificationSettingsModel(
      orderStatus: orderStatus ?? this.orderStatus,
      courierApproaching: courierApproaching ?? this.courierApproaching,
      campaigns: campaigns ?? this.campaigns,
      coupons: coupons ?? this.coupons,
      loyaltyPoints: loyaltyPoints ?? this.loyaltyPoints,
      accountSecurity: accountSecurity ?? this.accountSecurity,
      systemPermissionStatus:
          systemPermissionStatus ?? this.systemPermissionStatus,
    );
  }
}
